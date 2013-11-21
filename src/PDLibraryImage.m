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

#import "PDAppDelegate.h"
#import "PDImageHash.h"

#import <QuartzCore/CATransaction.h>

#import <sys/stat.h>

#define CACHE_DIR "proxy-cache-v1"

/* JPEG compression quality of 50% seems to be the lowest setting that
   doesn't introduce banding in smooth gradients. */

#define CACHE_QUALITY .5

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
writeImageToPath(CGImageRef im, NSString *path, double quality)
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
      NSDictionary *opts = [[NSDictionary alloc] initWithObjectsAndKeys:
			    [NSNumber numberWithDouble:quality],
			    (id)kCGImageDestinationLossyCompressionQuality,
			    nil];

      CGImageDestinationAddImage(dest, im, (CFDictionaryRef)opts);
      CGImageDestinationFinalize(dest);
      CFRelease(dest);

      [opts release];
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
      CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
      CGContextDrawImage(ctx, CGRectMake(0, 0, dw, dh), src_im);

      im = CGBitmapContextCreateImage(ctx);

      CGContextRelease(ctx);
    }

  CGColorSpaceRelease(srgb);

  return im;
}

static NSString *_cachePath;
static dispatch_once_t _cachePathOnce;

static void
cachePathInit(void *unused_arg)
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
						       NSUserDomainMask, YES);
  _cachePath = [[[[paths lastObject] stringByAppendingPathComponent:
		  [[NSBundle mainBundle] bundleIdentifier]]
		 stringByAppendingPathComponent:@CACHE_DIR]
		copy];
}

static NSString *
cachedPathForType(PDImageHash *hash, NSInteger type)
{
  /* This function may be called from multiple threads, so serialize. */

  dispatch_once_f(&_cachePathOnce, NULL, cachePathInit);

  NSString *hstr = [hash hashString];

  NSString *path
   = [[hstr substringToIndex:2]
      stringByAppendingPathComponent:[hstr substringFromIndex:2]];

  if (type == PDLibraryImage_Tiny)
    path = [path stringByAppendingString:@"_tiny.jpg"];
  else if (type == PDLibraryImage_Small)
    path = [path stringByAppendingString:@"_small.jpg"];
  else /* if (type == PDLibraryImage_Medium) */
    path = [path stringByAppendingString:@"_medium.jpg"];

  return [_cachePath stringByAppendingPathComponent:path];
}

static BOOL
validCachedImage(NSString *filePath, PDImageHash *hash, NSInteger type)
{
  return fileNewerThanFile(cachedPathForType(hash, type), filePath);
}

@implementation PDLibraryImage

@synthesize path = _path;

static NSOperationQueue *_wideQueue;
static NSOperationQueue *_narrowQueue;

- (NSOperationQueue *)wideQueue
{
  if (_wideQueue == nil)
    {
      _wideQueue = [[NSOperationQueue alloc] init];
      [_wideQueue setName:@"PDLibraryImage.wideQueue"];
      [_wideQueue addObserver:(id)[self class]
       forKeyPath:@"operationCount" options:0 context:NULL];
    }

  return _wideQueue;
}

- (NSOperationQueue *)narrowQueue
{
  if (_narrowQueue == nil)
    {
      _narrowQueue = [[NSOperationQueue alloc] init];
      [_narrowQueue setName:@"PDLibraryImage.narrowQueue"];
      [_narrowQueue setMaxConcurrentOperationCount:1];
      [_narrowQueue addObserver:(id)[self class]
       forKeyPath:@"operationCount" options:0 context:NULL];
    }

  return _narrowQueue;
}

+ (void)observeValueForKeyPath:(NSString *)path ofObject:(id)obj
    change:(NSDictionary *)dict context:(void *)ctx
{
  if ([path isEqualToString:@"operationCount"])
    {
      dispatch_async(dispatch_get_main_queue(), ^{
	NSInteger count = ([_wideQueue operationCount]
			   + [_narrowQueue operationCount]);
	PDAppDelegate *delegate = [NSApp delegate];
	if (count != 0)
	  [delegate addBackgroundActivity:@"PDLibraryImage"];
	else
	  [delegate removeBackgroundActivity:@"PDLibraryImage"];
      });
    }
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
  [_hash release];

  if (_imageProperties)
    CFRelease(_imageProperties);

  assert([_imageHosts count] == 0);
  [_imageHosts release];

  [_prefetchOp cancel];
  [_prefetchOp release];

  [super dealloc];
}

- (PDImageHash *)hash
{
  if (_hash == nil)
    _hash = [[PDImageHash fileHash:_path] retain];

  return _hash;
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
  if (_prefetchOp == nil && !_donePrefetch)
    {
      /* Prevent the block retaining self. */

      PDImageHash *hash = [self hash];
      NSString *path = [self path];

      NSString *tiny_path = cachedPathForType(hash, PDLibraryImage_Tiny);

      if (fileNewerThanFile(tiny_path, path))
	{
	  _donePrefetch = YES;
	  return;
	}

      _prefetchOp = [NSBlockOperation blockOperationWithBlock:^{

	CGImageSourceRef src = createImageSourceFromPath(path);
	if (src == NULL)
	  return;

	__block CGImageRef src_im
	  = CGImageSourceCreateImageAtIndex(src, 0, NULL);

	CFRelease(src);

	if (src_im == NULL)
	  return;

	CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

	void (^cache_image)(NSInteger type, size_t size) =
	  ^(NSInteger type, size_t size)
	  {
	    CGFloat sw = CGImageGetWidth(src_im);
	    CGFloat sh = CGImageGetHeight(src_im);

	    CGFloat dw = sw > sh ? size : size * ((CGFloat)sw / (CGFloat)sh);
	    CGFloat dh = sh > sw ? size : size * ((CGFloat)sh / (CGFloat)sw);

	    CGImageRef im = copyScaledImage(src_im, CGSizeMake(dw, dh), srgb);

	    if (im != NULL)
	      {
		NSString *cachePath = cachedPathForType(hash, type);
		writeImageToPath(im, cachePath, CACHE_QUALITY);
		CGImageRelease(src_im);
		src_im = im;
	      }
	  };

	cache_image(PDLibraryImage_Medium, PDLibraryImage_MediumSize);
	cache_image(PDLibraryImage_Small, PDLibraryImage_SmallSize);
	cache_image(PDLibraryImage_Tiny, PDLibraryImage_TinySize);

	CGColorSpaceRelease(srgb);
	CGImageRelease(src_im);
      }];

      [_prefetchOp setQueuePriority:NSOperationQueuePriorityLow];
      [[self narrowQueue] addOperation:_prefetchOp];
      [_prefetchOp retain];
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

- (BOOL)isPrefetching
{
  return ![_prefetchOp isFinished];
}

/* Takes ownership of 'im'. */

static void
setHostedImage(PDLibraryImage *self, id<PDLibraryImageHost> obj, CGImageRef im)
{
  dispatch_queue_t queue;

  if ([obj respondsToSelector:@selector(imageHostQueue)])
    queue = [obj imageHostQueue];
  else
    queue = dispatch_get_main_queue();

  dispatch_async(queue, ^{
    [obj libraryImage:self setHostedImage:im];
    CGImageRelease(im);
    [CATransaction flush];
  });
}

- (void)addImageHost:(id<PDLibraryImageHost>)obj
{
  assert([_imageHosts objectForKey:obj] == nil);

  PDImageHash *hash = [self hash];
  NSString *path = [self path];

  NSSize imageSize = [self pixelSize];
  if (imageSize.width == 0 || imageSize.height == 0)
    return;

  NSDictionary *opts = [obj imageHostOptions];
  BOOL thumb = [[opts objectForKey:PDLibraryImageHost_Thumbnail] boolValue];
  NSSize size = [[opts objectForKey:PDLibraryImageHost_Size] sizeValue];

  if (size.width == 0 || size.width > imageSize.width
      || size.height == 0 || size.height > imageSize.height)
    size = imageSize;

  CGFloat max_size = fmax(size.width, size.height);

  NSInteger type;
  CGFloat type_size;
  if (max_size < PDLibraryImage_TinySize)
    type = PDLibraryImage_Tiny, type_size = PDLibraryImage_TinySize;
  else if (max_size < PDLibraryImage_SmallSize)
    type = PDLibraryImage_Small, type_size = PDLibraryImage_SmallSize;
  else
    type = PDLibraryImage_Medium, type_size = PDLibraryImage_MediumSize;

  BOOL cache_is_valid = validCachedImage(path, hash, type);

  NSMutableArray *ops = [NSMutableArray array];

  NSOperationQueuePriority next_pri = NSOperationQueuePriorityHigh;

  /* If the proxy (tiny/small/medium) cache hasn't been built yet,
     display the embedded image thumbnail until it's ready. */

  if (thumb && !cache_is_valid)
    {
      NSOperation *thumb_op = [NSBlockOperation blockOperationWithBlock:^{
	CGImageSourceRef src = createImageSourceFromPath(path);
	if (src != NULL)
	  {
	    CGImageRef im = createCroppedThumbnailImage(src);
	    CFRelease(src);
	    if (im != NULL)
	      setHostedImage(self, obj, im);
	  }
      }];

      [thumb_op setQueuePriority:next_pri];
      next_pri = NSOperationQueuePriorityNormal;
      [ops addObject:thumb_op];
    }

  /* Then access the cached proxy that's larger than the requested size.

     FIXME: the prefetch op may be backed up behind a million other
     prefetch operations. Raising its priority at this point seems to
     have no effect. So just skip this stage if prefetch op has not
     completed yet..

     (But remember that thumbnails won't try to load anything better so
     they should use the proxy to replace the embedded thumbnail.) */

  if (cache_is_valid || thumb)
    {
      NSOperation *cache_op = [NSBlockOperation blockOperationWithBlock:^{
	NSString *cachedPath = cachedPathForType(hash, type);
	CGImageSourceRef src = createImageSourceFromPath(cachedPath);
	if (src != NULL)
	  {
	    CGImageRef im = CGImageSourceCreateImageAtIndex(src, 0, NULL);
	    CFRelease(src);

	    if (im != NULL)
	      setHostedImage(self, obj, im);
	  }
      }];

      /* Cached operation can't run until proxy cache is fully built for
	 this image. */

      [self startPrefetching];
      [cache_op setQueuePriority:next_pri];

      if (_prefetchOp)
	[cache_op addDependency:_prefetchOp];

      [ops addObject:cache_op];
    }

  /* Finally, if necessary, downsample from the proxy or the full
     image. I'm choosing to create yet another CGImageRef for the proxy
     if that's the one being used, rather than trying to reuse the one
     loaded above, ImageIO will probably cache it.

     FIXME: we should be tiling large images here. */

  if (!thumb && max_size != type_size)
    {
      /* Using 'id' so the block retains it, actually CGColorSpaceRef. */

      id space = [opts objectForKey:PDLibraryImageHost_ColorSpace];

      NSOperation *full_op = [NSBlockOperation blockOperationWithBlock:^{
	NSString *src_path = (max_size > type_size || !cache_is_valid
			      ? path : cachedPathForType(hash, type));

	CGImageSourceRef src = createImageSourceFromPath(src_path);
	if (src != NULL)
	  {
	    CGImageRef src_im = CGImageSourceCreateImageAtIndex(src, 0, NULL);
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

	    CGImageRef dst_im = copyScaledImage(src_im, size,
					     (CGColorSpaceRef)space);
	    CGImageRelease(src_im);

	    if (dst_im != NULL)
	      setHostedImage(self, obj, dst_im);
	  }
      }];

      [ops addObject:full_op];
    }

  [_imageHosts setObject:ops forKey:obj];

  /* First operation always goes into the maximally-concurrent queue,
     the goal is to get something visible as soon as possible. The
     other (more-refined and longer-running) operations go into the
     narrow queue to prevent them blocking other higher-priority ops
     (once they start running, they can't be preempted). */

  NSOperationQueue *q1 = [self wideQueue];
  NSOperationQueue *q2 = [self narrowQueue];
  NSOperation *pred = nil;

  for (NSOperation *op in ops)
    {
      if (pred == nil)
	[q1 addOperation:op];
      else
	{
	  [op addDependency:pred];
	  [q2 addOperation:op];
	}
      pred = op;
    }
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
  /* FIXME: not ideal, but ok for now. (Actually, it's quite bad. E.g.
     when zooming in above 100% we load the full-size image again for
     no reason.) */

  [self removeImageHost:obj];
  [self addImageHost:obj];
}

@end
