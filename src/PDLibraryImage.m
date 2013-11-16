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

@interface PDLibraryImageHostOperation : NSOperation
{
  id<PDLibraryImageHost> _imageHost;
  NSDictionary *_options;

  CGImageSourceRef _imageSource;
  NSDictionary *_imageProperties;
}

- (id)initWithImageHost:(id<PDLibraryImageHost>)host
    imageSource:(CGImageSourceRef)src imageProperties:(NSDictionary *)props;

@end

NSString * const PDLibraryImageHost_Size = @"size";
NSString * const PDLibraryImageHost_Thumbnail = @"thumbnail";

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

static NSString *
cachedPathForType(NSUUID *uuid, NSString *filePath, NSInteger type)
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

  if (_imageSource)
    CFRelease(_imageSource);
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

- (CGImageSourceRef)imageSource
{
  if (_imageSource == NULL)
    _imageSource = createImageSourceFromPath(_path);

  return _imageSource;
}

- (NSDictionary *)imageProperties
{
  if (_imageProperties == NULL)
    {
      CGImageSourceRef src = [self imageSource];

      if (src != NULL)
	_imageProperties = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
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

- (void)addImageHost:(id<PDLibraryImageHost>)obj
{
  PDLibraryImageHostOperation *op;

  assert([_imageHosts objectForKey:obj] == nil);

  op = [[PDLibraryImageHostOperation alloc]
	initWithImageHost:obj imageSource:[self imageSource]
	imageProperties:[self imageProperties]];

  [imageHostQueue() addOperation:op];
  [_imageHosts setObject:op forKey:obj];

  [op release];
}

- (void)removeImageHost:(id<PDLibraryImageHost>)obj
{
  PDLibraryImageHostOperation *op;

  op = [_imageHosts objectForKey:obj];
  if (op == nil)
    return;

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
  NSString *tiny_path = cachedPathForType(_uuid, _path, PDLibraryImage_Tiny);

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
	      writeImageToPath(im, cachedPathForType(_uuid, _path, type));
	      CGImageRelease(src_im);
	      src_im = im;
	    }
	}
    };

  /* Since we're generating one image, do them all, it will probably
     be quicker overall that way. */

  cache_image(PDLibraryImage_Medium, PDLibraryImage_MediumSize);
  cache_image(PDLibraryImage_Small, PDLibraryImage_SmallSize);
  cache_image(PDLibraryImage_Tiny, PDLibraryImage_TinySize);

  CGColorSpaceRelease(srgb);
  CGImageRelease(src_im);
}

@end

@implementation PDLibraryImageHostOperation

- (id)initWithImageHost:(id<PDLibraryImageHost>)host
    imageSource:(CGImageSourceRef)src imageProperties:(NSDictionary *)props;
{
  self = [super init];
  if (self == nil)
    return nil;

  _imageHost = [host retain];
  _options = [[host imageHostOptions] copy];

  _imageSource = (CGImageSourceRef)CFRetain(src);
  _imageProperties = [props copy];

  return self;
}

- (void)dealloc
{
  [_imageHost release];
  [_options release];
  if (_imageSource)
    CFRelease(_imageSource);
  [_imageProperties release];

  [super dealloc];
}

- (void)main
{
  CGImageRef im = NULL;

  // FIXME: ignoring size for now..

  if ([[_options objectForKey:PDLibraryImageHost_Thumbnail] boolValue])
    im = createCroppedThumbnailImage(_imageSource);

  if (im == NULL)
    im = CGImageSourceCreateImageAtIndex(_imageSource, 0, NULL);

  dispatch_async(dispatch_get_main_queue(), ^{
    [_imageHost setHostedImage:im];
    CGImageRelease(im);
  });
}

@end
