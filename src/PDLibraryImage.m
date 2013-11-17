/* -*- c-style: gnu -*-

   Copyright (c) 2013 John Harper <jsh@unfactored.org>

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation files
   (the "Software"), to deal in the Software without restriction,
   including without limitation the rights to use, copy, modify, merge,
   publish, distribute, sublicense, and/or sell copies of the Software,
   and to permit persons to whom the Software is furnished to do so,
   subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. */

#import "PDLibraryImage.h"

#import "PDUUIDManager.h"

#import <QuartzCore/CATransaction.h>

#import <sys/stat.h>

enum
{
  PDLibraryImage_Tiny,			/* 256px */
  PDLibraryImage_Small,			/* 512px */
  PDLibraryImage_Medium,		/* 1024px */
};

enum
{
  PDLibraryImage_TinySize = 256,
  PDLibraryImage_SmallSize = 512,
  PDLibraryImage_MediumSize = 1024,
};

@interface PDLibraryImagePrefetchOperation : NSOperation
{
  NSString *_path;
  NSUUID *_uuid;
}

- (id)initWithPath:(NSString *)path UUID:(NSUUID *)uuid;

@end

NSString * const PDLibraryImageHost_Size = @"size";
NSString * const PDLibraryImageHost_Thumbnail = @"thumbnail";
NSString * const PDLibraryImageHost_ColorSpace = @"colorSpace";

static size_t
fileMTime(NSString *path)
{
  struct stat st;

  if (stat([path fileSystemRepresentation], &st) == 0)
    return st.st_mtime;
  else
    return 0;
}

static BOOL
fileNewerThanFile(NSString *path1, NSString *path2)
{
  return fileMTime(path1) > fileMTime(path2);
}

static CGImageSourceRef
createImageSourceFromPath(NSString *path)
{
  NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
  NSDictionary *opts = [[NSDictionary alloc] initWithObjectsAndKeys:
			(id)kCFBooleanFalse, kCGImageSourceShouldCache,
			nil];

  CGImageSourceRef src = CGImageSourceCreateWithURL((CFURLRef)url,
						    (CFDictionaryRef)opts);

  [opts release];
  [url release];

  return src;
}

static void
writeImageToPath(CGImageRef im, NSString *path)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [path stringByDeletingLastPathComponent];

  if (![fm fileExistsAtPath:dir])
    {
      if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES
	    attributes:nil error:nil])
	return;
    }

  NSURL *url = [[NSURL alloc] initFileURLWithPath:path];

  CGImageDestinationRef dest = CGImageDestinationCreateWithURL((CFURLRef)url,
						CFSTR("public.jpeg"), 1, NULL);

  [url release];

  if (dest != NULL)
    {
      CGImageDestinationAddImage(dest, im, NULL);
      CGImageDestinationFinalize(dest);
      CFRelease(dest);
    }
}

static CGImageRef
createCroppedThumbnailImage(CGImageSourceRef src)
{
  CGImageRef im = CGImageSourceCreateThumbnailAtIndex(src, 0, NULL);
  if (im == NULL)
    return NULL;

  /* Embedded JPEG thumbnails are often a fixed size and aspect ratio,
     so crop them to the original image's aspect ratio. */

  CFDictionaryRef dict = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
  if (dict == NULL)
    return im;

  CGFloat pix_w
   = [(id)CFDictionaryGetValue(dict, kCGImagePropertyPixelWidth) doubleValue];
  CGFloat pix_h
   = [(id)CFDictionaryGetValue(dict, kCGImagePropertyPixelHeight) doubleValue];

  CFRelease(dict);

  CGFloat im_w = CGImageGetWidth(im);
  CGFloat im_h = CGImageGetHeight(im);

  CGRect imR = CGRectMake(0, 0, im_w, im_h);

  if (pix_w > pix_h)
    {
      CGFloat h = im_w * (pix_h / pix_w);
      imR.origin.y = ceil((im_h - h) * (CGFloat).5);
      imR.size.height = im_h - (imR.origin.y * 2);
    }
  else
    {
      CGFloat w = im_h * (pix_w / pix_h);
      imR.origin.x = ceil((im_w - w) * (CGFloat).5);
      imR.size.width = im_w - (imR.origin.x * 2);
    }

  if (!CGRectEqualToRect(imR, CGRectMake(0, 0, im_w, im_h)))
    {
      CGImageRef copy = CGImageCreateWithImageInRect(im, imR);
      CGImageRelease(im);
      im = copy;
    }

  return im;
}

static CGImageRef
copyScaledImage(CGImageRef src_im, CGSize size, CGColorSpaceRef space)
{
  if (src_im == NULL)
    return NULL;

  CGColorSpaceRef srgb = NULL;

  if (space == NULL)
    {
      srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
      space = srgb;
    }

  size_t dw = ceil(size.width);
  size_t dh = ceil(size.height);

  CGContextRef ctx = CGBitmapContextCreate(NULL, dw, dh, 8, 0, space,
		kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst);

  CGImageRef im = NULL;

  if (ctx != NULL)
    {
      CGContextSetBlendMode(ctx, kCGBlendModeCopy);
      CGContextDrawImage(ctx, CGRectMake(0, 0, dw, dh), src_im);

      im = CGBitmapContextCreateImage(ctx);

      CGContextRelease(ctx);
    }

  return im;
}

static NSString *
cachedPathForType(NSString *filePath, NSUUID *uuid, NSInteger type)
{
  static NSString *_cachePath;

  if (_cachePath == nil)
    {
      NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
							NSUserDomainMask, YES);
      _cachePath = [[[[paths lastObject] stringByAppendingPathComponent:
		      [[NSBundle mainBundle] bundleIdentifier]]
		     stringByAppendingPathComponent:@"PDLibraryImageCache"]
		    copy];
    }

  NSString *ustr = [uuid UUIDString];

  NSString *path
   = [[ustr substringToIndex:2]
      stringByAppendingPathComponent:[ustr substringFromIndex:2]];

  if (type == PDLibraryImage_Tiny)
    path = [path stringByAppendingString:@"_tiny.jpg"];
  else if (type == PDLibraryImage_Small)
    path = [path stringByAppendingString:@"_small.jpg"];
  else /* if (type == PDLibraryImage_Medium) */
    path = [path stringByAppendingString:@"_medium.jpg"];

  return [_cachePath stringByAppendingPathComponent:path];
}

static BOOL
validCachedImage(NSString *filePath, NSUUID *uuid, NSInteger type)
{
  return fileNewerThanFile(cachedPathForType(filePath, uuid, type), filePath);
}

@implementation PDLibraryImage

@synthesize path = _path;

static NSOperationQueue *
prefetchQueue(void)
{
  static NSOperationQueue *queue;

  if (queue == nil)
    {
      queue = [[NSOperationQueue alloc] init];
      [queue setName:@"PDLibraryImage.prefetchQueue"];
      [queue setMaxConcurrentOperationCount:1];
    }

  return queue;
}

static NSOperationQueue *
imageHostQueue(void)
{
  static NSOperationQueue *queue;

  if (queue == nil)
    {
      queue = [[NSOperationQueue alloc] init];
      [queue setName:@"PDLibraryImage"];
    }

  return queue;
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];
  _imageHosts = [[NSMapTable strongToStrongObjectsMapTable] retain];

  return self;
}

- (void)dealloc
{
  [_path release];
  [_uuid release];

  if (_imageProperties)
    CFRelease(_imageProperties);

  [_imageHosts release];

  [_prefetchOp cancel];
  [_prefetchOp release];

  [super dealloc];
}

- (NSUUID *)UUID
{
  if (_uuid == nil)
    _uuid = [[PDUUIDManager sharedManager] UUIDOfFileAtPath:_path];

  return _uuid;
}

- (NSString *)title
{
  return [[_path lastPathComponent] stringByDeletingPathExtension];
}

- (NSDictionary *)imageProperties
{
  if (_imageProperties == NULL)
    {
      CGImageSourceRef src = createImageSourceFromPath(_path);

      if (src != NULL)
	{
	  _imageProperties = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
	  CFRelease(src);
	}
    }

  return (NSDictionary *)_imageProperties;
}

- (id)imagePropertyForKey:(CFStringRef)key
{
  return [[self imageProperties] objectForKey:(NSString *)key];
}

- (CGSize)pixelSize
{
  NSDictionary *dict = [self imageProperties];

  CGFloat pw = [[dict objectForKey:
		 (id)kCGImagePropertyPixelWidth] doubleValue];
  CGFloat ph = [[dict objectForKey:
		 (id)kCGImagePropertyPixelHeight] doubleValue];

  return CGSizeMake(pw, ph);
}

- (unsigned int)orientation
{
  return [[self imagePropertyForKey:
	   kCGImagePropertyOrientation] unsignedIntValue];
}

- (CGSize)orientedPixelSize
{
  CGSize pixelSize = [self pixelSize];
  unsigned int orientation = [self orientation];

  if (orientation <= 4)
    return pixelSize;
  else
    return CGSizeMake(pixelSize.height, pixelSize.width);
}

- (void)startPrefetching
{
  if (_prefetchOp == nil)
    {
      _prefetchOp = [[PDLibraryImagePrefetchOperation alloc]
		     initWithPath:[self path] UUID:[self UUID]];
      [_prefetchOp setQueuePriority:NSOperationQueuePriorityLow];
      [prefetchQueue() addOperation:_prefetchOp];
    }
}

- (void)stopPrefetching
{
  if (_prefetchOp != nil
      && !([_prefetchOp isExecuting] || [_prefetchOp isFinished])
      && [[_prefetchOp dependencies] count] == 0)
    {
      [_prefetchOp cancel];
      [_prefetchOp release];
      _prefetchOp = nil;
    }
}

/* Takes ownership of 'im'. */

static void
setHostedImage(id<PDLibraryImageHost> obj, CGImageRef im)
{
  dispatch_queue_t queue;

  if ([obj respondsToSelector:@selector(imageHostQueue)])
    queue = [obj imageHostQueue];
  else
    queue = dispatch_get_main_queue();

  dispatch_async(queue, ^{
    [obj setHostedImage:im];
    CGImageRelease(im);
    [CATransaction flush];
  });
}

- (void)addImageHost:(id<PDLibraryImageHost>)obj
{
  assert([_imageHosts objectForKey:obj] == nil);

  NSUUID *uuid = [self UUID];
  NSString *path = [self path];

  NSDictionary *opts = [obj imageHostOptions];
  BOOL thumb = [[opts objectForKey:PDLibraryImageHost_Thumbnail] boolValue];
  NSSize size = [[opts objectForKey:PDLibraryImageHost_Size] sizeValue];

  if (size.width == 0 && size.height == 0)
    size = [self pixelSize];

  CGFloat max_size = fmax(size.width, size.height);

  NSInteger type;
  if (max_size < PDLibraryImage_TinySize)
    type = PDLibraryImage_Tiny;
  else if (max_size < PDLibraryImage_SmallSize)
    type = PDLibraryImage_Small;
  else
    type = PDLibraryImage_Medium;

  NSMutableArray *ops = [NSMutableArray array];
  NSOperation *thumb_op = nil;
  NSOperation *cache_op = nil;
  NSOperation *full_op = nil;

  /* If the proxy (tiny/small/medium) cache hasn't been built yet,
     display the embedded image thumbnail until it's ready. */

  if (thumb && !validCachedImage(path, uuid, type))
    {
      thumb_op = [NSBlockOperation blockOperationWithBlock:^{
	CGImageSourceRef src = createImageSourceFromPath(path);
	if (src != NULL)
	  {
	    CGImageRef im = createCroppedThumbnailImage(src);
	    CFRelease(src);
	    if (im != NULL)
	      setHostedImage(obj, im);
	  }
      }];

      [thumb_op setQueuePriority:NSOperationQueuePriorityHigh];
      [ops addObject:thumb_op];
    }

  /* Then access the cached proxy that's larger than the requested size. */

  cache_op = [NSBlockOperation blockOperationWithBlock:^{
    NSString *cachedPath = cachedPathForType(path, uuid, type);
    CGImageSourceRef src = createImageSourceFromPath(cachedPath);
    if (src != NULL)
      {
	CGImageRef im = CGImageSourceCreateImageAtIndex(src, 0, NULL);
	CFRelease(src);

	/* FIXME: resize proxy to requested size? */

	if (im != NULL)
	  setHostedImage(obj, im);
      }
  }];

  /* Cached operation can't run until proxy cache is fully built for
     this image. */

  [self startPrefetching];
  [cache_op addDependency:_prefetchOp];

  if (thumb_op != nil)
    [cache_op addDependency:thumb_op];

  [ops addObject:cache_op];

  /* If necessary, load the full image last.

     FIXME: we should be tiling large images here. */

  if (!thumb && max_size > PDLibraryImage_MediumSize)
    {
      /* Using 'id' so the block retains it, actually CGColorSpaceRef. */

      id space = [opts objectForKey:PDLibraryImageHost_ColorSpace];

      full_op = [NSBlockOperation blockOperationWithBlock:^{
	CGImageSourceRef src = createImageSourceFromPath(path);
	if (src != NULL)
	  {
	    CGImageRef im1 = CGImageSourceCreateImageAtIndex(src, 0, NULL);
	    CFRelease(src);

	    /* Scale the image to required size, this has several side-
	       effects: (1) everything looks as good as possible, even
	       when using a cheap GL filter, (2) uses as little memory
	       as possible, (3) stops CA needing to decompress and
	       color-match the image before displaying it.

	       (Even though PDImageLayer tries to arrange for the
	       decompression to happen on a background thread, and
	       CALayer should never decompress with the CATransaction
	       lock held, both those things appear to happen when
	       directly using the raw CGImage from ImageIO.) */

	    CGImageRef im2 = copyScaledImage(im1, size,
					     (CGColorSpaceRef)space);
	    CGImageRelease(im1);

	    if (im2 != NULL)
	      setHostedImage(obj, im2);
	  }
      }];

      [full_op addDependency:cache_op];

      [ops addObject:full_op];
    }

  [_imageHosts setObject:ops forKey:obj];

  NSOperationQueue *q = imageHostQueue();
  for (NSOperation *op in ops)
    [q addOperation:op];
}

- (void)removeImageHost:(id<PDLibraryImageHost>)obj
{
  NSArray *ops = [_imageHosts objectForKey:obj];
  if (ops == nil)
    return;

  for (NSOperation *op in ops)
    [op cancel];

  [_imageHosts removeObjectForKey:obj];
}

- (void)updateImageHost:(id<PDLibraryImageHost>)obj
{
  // FIXME: not ideal, but ok for now

  [self removeImageHost:obj];
  [self addImageHost:obj];
}

@end

@implementation PDLibraryImagePrefetchOperation

- (id)initWithPath:(NSString *)path UUID:(NSUUID *)uuid;
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];
  _uuid = [uuid copy];

  return self;
}

- (void)main
{
  NSString *tiny_path = cachedPathForType(_path, _uuid, PDLibraryImage_Tiny);

  if (fileNewerThanFile(tiny_path, _path))
    return;

  CGImageSourceRef src = createImageSourceFromPath(_path);
  if (src == NULL)
    return;

  __block CGImageRef src_im = CGImageSourceCreateImageAtIndex(src, 0, NULL);

  CFRelease(src);

  if (src_im == NULL)
    return;

  CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

  void (^cache_image)(NSInteger type, size_t size) =
    ^(NSInteger type, size_t size)
    {
      CGFloat sw = CGImageGetWidth(src_im);
      CGFloat sh = CGImageGetHeight(src_im);

      size_t dw = sw > sh ? size : round(size * ((CGFloat)sw / (CGFloat)sh));
      size_t dh = sh > sw ? size : round(size * ((CGFloat)sh / (CGFloat)sw));

      CGContextRef ctx = CGBitmapContextCreate(NULL, dw, dh, 8, 0, srgb,
		kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst);
      if (ctx != NULL)
	{
	  CGContextSetBlendMode(ctx, kCGBlendModeCopy);
	  CGContextDrawImage(ctx, CGRectMake(0, 0, dw, dh), src_im);

	  CGImageRef im = CGBitmapContextCreateImage(ctx);

	  CGContextRelease(ctx);

	  if (im != NULL)
	    {
	      writeImageToPath(im, cachedPathForType(_path, _uuid, type));
	      CGImageRelease(src_im);
	      src_im = im;
	    }
	}
    };

  cache_image(PDLibraryImage_Medium, PDLibraryImage_MediumSize);
  cache_image(PDLibraryImage_Small, PDLibraryImage_SmallSize);
  cache_image(PDLibraryImage_Tiny, PDLibraryImage_TinySize);

  CGColorSpaceRelease(srgb);
  CGImageRelease(src_im);
}

@end
