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

#import "PDImage.h"

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
  PDImage_Tiny,				/* 256px */
  PDImage_Small,			/* 512px */
  PDImage_Medium,			/* 1024px */
};

enum
{
  PDImage_TinySize = 256,
  PDImage_SmallSize = 512,
  PDImage_MediumSize = 1024,
};

NSString * const PDImage_Name = @"Name";
NSString * const PDImage_Path = @"Path";

NSString * const PDImage_FileSize = @"FileSize";
NSString * const PDImage_PixelWidth = @"PixelWidth";
NSString * const PDImage_PixelHeight = @"PixelHeight";
NSString * const PDImage_Orientation = @"Orientation";
NSString * const PDImage_ColorModel = @"ColorModel";
NSString * const PDImage_ProfileName = @"ProfileName";

NSString * const PDImage_Title = @"Title";
NSString * const PDImage_Caption = @"Caption";
NSString * const PDImage_Keywords = @"Keywords";
NSString * const PDImage_Copyright = @"Copyright";
NSString * const PDImage_Rating = @"Rating";

NSString * const PDImage_Altitude = @"Altitude";
NSString * const PDImage_Aperture = @"Aperture";
NSString * const PDImage_CameraMake = @"CameraMake";
NSString * const PDImage_CameraModel = @"CameraModel";
NSString * const PDImage_CameraSoftware = @"CameraSoftware";
NSString * const PDImage_Contrast = @"Contrast";
NSString * const PDImage_DigitizedDate = @"DigitizedDate";
NSString * const PDImage_Direction = @"Direction";
NSString * const PDImage_DirectionRef = @"DirectionRef";
NSString * const PDImage_ExposureBias = @"ExposureBias";
NSString * const PDImage_ExposureLength = @"ExposureLength";
NSString * const PDImage_ExposureMode = @"ExposureMode";
NSString * const PDImage_ExposureProgram = @"ExposureProgram";
NSString * const PDImage_Flash = @"Flash";
NSString * const PDImage_FlashCompensation = @"FlashCompensation";
NSString * const PDImage_FNumber = @"FNumber";
NSString * const PDImage_FocalLength = @"FocalLength";
NSString * const PDImage_FocalLength35mm = @"FocalLength35mm";
NSString * const PDImage_FocusMode = @"FocusMode";
NSString * const PDImage_ISOSpeed = @"ISOSpeed";
NSString * const PDImage_ImageStabilization = @"ImageStabilization";
NSString * const PDImage_Latitude = @"Latitude";
NSString * const PDImage_LightSource = @"LightSource";
NSString * const PDImage_Longitude = @"Longitude";
NSString * const PDImage_MaxAperture = @"MaxAperture";
NSString * const PDImage_MeteringMode = @"MeteringMode";
NSString * const PDImage_OriginalDate = @"OriginalDate";
NSString * const PDImage_Saturation = @"Saturation";
NSString * const PDImage_SceneCaptureType = @"SceneCaptureType";
NSString * const PDImage_SceneType = @"SceneType";
NSString * const PDImage_Sharpness = @"Sharpness";
NSString * const PDImage_WhiteBalance = @"WhiteBalance";

NSString * const PDImageHost_Size = @"Size";
NSString * const PDImageHost_Thumbnail = @"Thumbnail";
NSString * const PDImageHost_ColorSpace = @"ColorSpace";

static size_t
file_mtime(NSString *path)
{
  struct stat st;

  if (stat([path fileSystemRepresentation], &st) == 0)
    return st.st_mtime;
  else
    return 0;
}

static BOOL
file_newer_than(NSString *path1, NSString *path2)
{
  return file_mtime(path1) > file_mtime(path2);
}

static CGImageSourceRef
create_image_source_from_path(NSString *path)
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
write_image_to_path(CGImageRef im, NSString *path, double quality)
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
create_cropped_thumbnail_image(CGImageSourceRef src)
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
copy_scaled_image(CGImageRef src_im, CGSize size, CGColorSpaceRef space)
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

static CFDictionaryRef
property_map(void)
{
  static CFDictionaryRef map;
  
  if (map == NULL)
    {
      const void *tiff_keys[] =
	{
	  kCGImagePropertyTIFFMake,
	  kCGImagePropertyTIFFModel,
	  kCGImagePropertyTIFFSoftware,
	};
      const void *tiff_values[] =
	{
	  PDImage_CameraMake,
	  PDImage_CameraModel,
	  PDImage_CameraSoftware,
	};

      const void *exif_keys[] =
	{
	  kCGImagePropertyExifApertureValue,
	  kCGImagePropertyExifContrast,
	  kCGImagePropertyExifDateTimeDigitized,
	  kCGImagePropertyExifExposureBiasValue,
	  kCGImagePropertyExifExposureTime,
	  kCGImagePropertyExifExposureMode,
	  kCGImagePropertyExifExposureProgram,
	  kCGImagePropertyExifFlash,
	  kCGImagePropertyExifFNumber,
	  kCGImagePropertyExifFocalLength,
	  kCGImagePropertyExifFocalLenIn35mmFilm,
	  kCGImagePropertyExifISOSpeed,
	  kCGImagePropertyExifISOSpeedRatings,
	  kCGImagePropertyExifLightSource,
	  kCGImagePropertyExifMaxApertureValue,
	  kCGImagePropertyExifMeteringMode,
	  kCGImagePropertyExifDateTimeOriginal,
	  kCGImagePropertyExifSaturation,
	  kCGImagePropertyExifSceneCaptureType,
	  kCGImagePropertyExifSceneType,
	  kCGImagePropertyExifSharpness,
	  kCGImagePropertyExifWhiteBalance,
 	};
      const void *exif_values[] =
	{
	  PDImage_Aperture,
	  PDImage_Contrast,
	  PDImage_DigitizedDate,
	  PDImage_ExposureBias,
	  PDImage_ExposureLength,
	  PDImage_ExposureMode,
	  PDImage_ExposureProgram,
	  PDImage_Flash,
	  PDImage_FNumber,
	  PDImage_FocalLength,
	  PDImage_FocalLength35mm,
	  PDImage_ISOSpeed,
	  kCFNull,			/* ISOSpeedRatings */
	  PDImage_LightSource,
	  PDImage_MaxAperture,
	  PDImage_MeteringMode,
	  PDImage_OriginalDate,
	  PDImage_Saturation,
	  PDImage_SceneCaptureType,
	  PDImage_SceneType,
	  PDImage_Sharpness,
	  PDImage_WhiteBalance,
	};

      const void *exif_aux_keys[] =
	{
	  kCGImagePropertyExifAuxFlashCompensation,
	  CFSTR("ImageStabilization"),
	};
      const void *exif_aux_values[] =
	{
	  PDImage_FlashCompensation,
	  PDImage_ImageStabilization,
	};

      const void *iptc_keys[] =
	{
	  kCGImagePropertyIPTCKeywords,
	  kCGImagePropertyIPTCStarRating,
 	};
      const void *iptc_values[] =
	{
	  PDImage_Keywords,
	  PDImage_Rating,
	};

      CFDictionaryRef tiff_map = CFDictionaryCreate(NULL, tiff_keys,
	tiff_values, sizeof(tiff_keys) / sizeof(tiff_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
      CFDictionaryRef exif_map = CFDictionaryCreate(NULL, exif_keys,
	exif_values, sizeof(exif_keys) / sizeof(exif_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
      CFDictionaryRef exif_aux_map = CFDictionaryCreate(NULL, exif_aux_keys,
	exif_aux_values, sizeof(exif_aux_keys) / sizeof(exif_aux_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
      CFDictionaryRef iptc_map = CFDictionaryCreate(NULL, iptc_keys,
	iptc_values, sizeof(iptc_keys) / sizeof(iptc_keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

      const void *keys[] =
	{
	  kCGImagePropertyFileSize,
	  kCGImagePropertyPixelWidth,
	  kCGImagePropertyPixelHeight,
	  kCGImagePropertyOrientation,
	  kCGImagePropertyColorModel,
	  kCGImagePropertyProfileName,
	  kCGImagePropertyTIFFDictionary,
	  kCGImagePropertyExifDictionary,
	  kCGImagePropertyExifAuxDictionary,
	  kCGImagePropertyIPTCDictionary,
	  kCGImagePropertyGPSDictionary,
	};
      const void *values[] =
	{
	  PDImage_FileSize,
	  PDImage_PixelWidth,
	  PDImage_PixelHeight,
	  PDImage_Orientation,
	  PDImage_ColorModel,
	  PDImage_ProfileName,
	  tiff_map,
	  exif_map,
	  exif_aux_map,
	  iptc_map,
	  kCFNull,
	};
      
      map = CFDictionaryCreate(NULL, keys, values, sizeof(keys) / sizeof(keys[0]),
	&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

      CFRelease(tiff_map);
      CFRelease(exif_map);
      CFRelease(exif_aux_map);
      CFRelease(iptc_map);
    }

  return map;
}

struct map_closure
{
  CFDictionaryRef map;
  NSMutableDictionary *dict;
};

static void
process_gps_dictionary(CFDictionaryRef gps_dict, NSMutableDictionary *dict)
{
  double value;
  CFTypeRef ptr;
  CFTypeID number_type = CFNumberGetTypeID();

  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLatitude);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      CFNumberGetValue(ptr, kCFNumberDoubleType, &value);
      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLatitudeRef);
      if (ptr != NULL && CFEqual(ptr, CFSTR("S")))
	value = -value;
      id obj = [NSNumber numberWithDouble:value];
      [dict setObject:obj forKey:PDImage_Latitude];
    }
      
  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLongitude);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      CFNumberGetValue(ptr, kCFNumberDoubleType, &value);
      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSLongitudeRef);
      if (ptr != NULL && CFEqual(ptr, CFSTR("W")))
	value = -value;
      id obj = [NSNumber numberWithDouble:value];
      [dict setObject:obj forKey:PDImage_Longitude];
    }

  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSAltitude);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      CFNumberGetValue(ptr, kCFNumberDoubleType, &value);
      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSAltitudeRef);
      if (ptr != NULL && CFGetTypeID(ptr) == number_type)
	{
	  int x;
	  CFNumberGetValue(ptr, kCFNumberIntType, &x);
	  if (x == 1)
	    value = -value;
	}
      id obj = [NSNumber numberWithDouble:value];
      [dict setObject:obj forKey:PDImage_Altitude];
    }

  ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSImgDirection);
  if (ptr != NULL && CFGetTypeID(ptr) == number_type)
    {
      [dict setObject:(id)ptr forKey:PDImage_Direction];

      ptr = CFDictionaryGetValue(gps_dict, kCGImagePropertyGPSImgDirectionRef);
      if (ptr != NULL)
	[dict setObject:(id)ptr forKey:PDImage_DirectionRef];
    }
}

static void
map_property(const void *key, const void *value, void *ctx)
{
  struct map_closure *c = ctx;

  const void *mapped_key = CFDictionaryGetValue(c->map, key);

  if (mapped_key == NULL)
    return;

  if (CFGetTypeID(mapped_key) == CFDictionaryGetTypeID()
      && CFGetTypeID(value) == CFDictionaryGetTypeID())
    {
      struct map_closure cc;

      cc.map = mapped_key;
      cc.dict = c->dict;

      CFDictionaryApplyFunction((CFDictionaryRef)value, map_property, &cc);
    }
  else if (mapped_key == kCFNull)
    {
      /* Manual fix-ups. */

      if (CFEqual(key, kCGImagePropertyExifISOSpeedRatings)
	  && CFGetTypeID(value) == CFArrayGetTypeID()
	  && CFArrayGetCount(value) >= 1
	  && [c->dict objectForKey:PDImage_ISOSpeed] == nil)
	{
	  [c->dict setObject:CFArrayGetValueAtIndex(value, 0)
	   forKey:PDImage_ISOSpeed];
	}
      else if (CFEqual(key, kCGImagePropertyGPSDictionary)
	       && CFGetTypeID(value) == CFDictionaryGetTypeID())
	{
	  process_gps_dictionary((CFDictionaryRef)value, c->dict);
	}
      else
	abort();
    }
  else
    {
      [c->dict setObject:(id)value forKey:(id)mapped_key];
    }
}

static NSDictionary *
copy_image_properties(CGImageSourceRef src)
{
  CFDictionaryRef dict = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
  if (dict == NULL)
    return [[NSDictionary alloc] init];

  struct map_closure c;

  c.map = property_map();
  c.dict = [[NSMutableDictionary alloc] init];

  CFDictionaryApplyFunction(dict, map_property, &c);

  CFRelease(dict);

  return c.dict;
}

static NSString *cache_path;
static dispatch_once_t cache_path_once;

static void
cache_path_init(void *unused_arg)
{
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
						       NSUserDomainMask, YES);
  cache_path = [[[[paths lastObject] stringByAppendingPathComponent:
		  [[NSBundle mainBundle] bundleIdentifier]]
		 stringByAppendingPathComponent:@CACHE_DIR]
		copy];
}

static NSString *
cache_path_for_type(PDImageHash *hash, NSInteger type)
{
  NSString *hstr = [hash hashString];

  NSString *path
   = [[hstr substringToIndex:2]
      stringByAppendingPathComponent:[hstr substringFromIndex:2]];

  if (type == PDImage_Tiny)
    path = [path stringByAppendingString:@"_tiny.jpg"];
  else if (type == PDImage_Small)
    path = [path stringByAppendingString:@"_small.jpg"];
  else /* if (type == PDImage_Medium) */
    path = [path stringByAppendingString:@"_medium.jpg"];

  dispatch_once_f(&cache_path_once, NULL, cache_path_init);

  return [cache_path stringByAppendingPathComponent:path];
}

static BOOL
valid_cache_image(NSString *filePath, PDImageHash *hash, NSInteger type)
{
  return file_newer_than(cache_path_for_type(hash, type), filePath);
}

@implementation PDImage

@synthesize path = _path;

static NSOperationQueue *_wideQueue;
static NSOperationQueue *_narrowQueue;

- (NSOperationQueue *)wideQueue
{
  if (_wideQueue == nil)
    {
      _wideQueue = [[NSOperationQueue alloc] init];
      [_wideQueue setName:@"PDImage.wideQueue"];
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
      [_narrowQueue setName:@"PDImage.narrowQueue"];
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
	  [delegate addBackgroundActivity:@"PDImage"];
	else
	  [delegate removeBackgroundActivity:@"PDImage"];
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

  [_explicitProperties release];
  [_implicitProperties release];

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

- (id)imagePropertyForKey:(NSString *)key
{
  if (_implicitProperties == nil)
    {
      CGImageSourceRef src = create_image_source_from_path(_path);

      if (src != NULL)
	{
	  _implicitProperties = copy_image_properties(src);
	  CFRelease(src);
	}
    }

  id value = [_explicitProperties objectForKey:key];

  if (value == nil)
    value = [_implicitProperties objectForKey:key];

  return value;
}

- (void)setImageProperty:(id)obj forKey:(NSString *)key
{
  if (_explicitProperties == nil)
    _explicitProperties = [[NSMutableDictionary alloc] init];

  /* FIXME: persist this? */

  [_explicitProperties setObject:obj forKey:key];
}

- (CGSize)pixelSize
{
  CGFloat pw = [[self imagePropertyForKey:PDImage_PixelWidth] doubleValue];
  CGFloat ph = [[self imagePropertyForKey:PDImage_PixelHeight] doubleValue];

  return CGSizeMake(pw, ph);
}

- (unsigned int)orientation
{
  return [[self imagePropertyForKey:PDImage_Orientation] unsignedIntValue];
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

      NSString *tiny_path = cache_path_for_type(hash, PDImage_Tiny);

      if (file_newer_than(tiny_path, path))
	{
	  _donePrefetch = YES;
	  return;
	}

      _prefetchOp = [NSBlockOperation blockOperationWithBlock:^{

	CGImageSourceRef src = create_image_source_from_path(path);
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

	    CGImageRef im = copy_scaled_image(src_im, CGSizeMake(dw, dh), srgb);

	    if (im != NULL)
	      {
		NSString *cachePath = cache_path_for_type(hash, type);
		write_image_to_path(im, cachePath, CACHE_QUALITY);
		CGImageRelease(src_im);
		src_im = im;
	      }
	  };

	cache_image(PDImage_Medium, PDImage_MediumSize);
	cache_image(PDImage_Small, PDImage_SmallSize);
	cache_image(PDImage_Tiny, PDImage_TinySize);

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
setHostedImage(PDImage *self, id<PDImageHost> obj, CGImageRef im)
{
  dispatch_queue_t queue;

  if ([obj respondsToSelector:@selector(imageHostQueue)])
    queue = [obj imageHostQueue];
  else
    queue = dispatch_get_main_queue();

  dispatch_async(queue, ^{
    [obj image:self setHostedImage:im];
    CGImageRelease(im);
    [CATransaction flush];
  });
}

- (void)addImageHost:(id<PDImageHost>)obj
{
  assert([_imageHosts objectForKey:obj] == nil);

  PDImageHash *hash = [self hash];
  NSString *path = [self path];

  NSSize imageSize = [self pixelSize];
  if (imageSize.width == 0 || imageSize.height == 0)
    return;

  NSDictionary *opts = [obj imageHostOptions];
  BOOL thumb = [[opts objectForKey:PDImageHost_Thumbnail] boolValue];
  NSSize size = [[opts objectForKey:PDImageHost_Size] sizeValue];

  if (size.width == 0 || size.width > imageSize.width
      || size.height == 0 || size.height > imageSize.height)
    size = imageSize;

  CGFloat max_size = fmax(size.width, size.height);

  NSInteger type;
  CGFloat type_size;
  if (max_size < PDImage_TinySize)
    type = PDImage_Tiny, type_size = PDImage_TinySize;
  else if (max_size < PDImage_SmallSize)
    type = PDImage_Small, type_size = PDImage_SmallSize;
  else
    type = PDImage_Medium, type_size = PDImage_MediumSize;

  BOOL cache_is_valid = valid_cache_image(path, hash, type);

  NSMutableArray *ops = [NSMutableArray array];

  NSOperationQueuePriority next_pri = NSOperationQueuePriorityHigh;

  /* If the proxy (tiny/small/medium) cache hasn't been built yet,
     display the embedded image thumbnail until it's ready. */

  if (thumb && !cache_is_valid)
    {
      NSOperation *thumb_op = [NSBlockOperation blockOperationWithBlock:^{
	CGImageSourceRef src = create_image_source_from_path(path);
	if (src != NULL)
	  {
	    CGImageRef im = create_cropped_thumbnail_image(src);
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
	NSString *cachedPath = cache_path_for_type(hash, type);
	CGImageSourceRef src = create_image_source_from_path(cachedPath);
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

      id space = [opts objectForKey:PDImageHost_ColorSpace];

      NSOperation *full_op = [NSBlockOperation blockOperationWithBlock:^{
	NSString *src_path = (max_size > type_size || !cache_is_valid
			      ? path : cache_path_for_type(hash, type));

	CGImageSourceRef src = create_image_source_from_path(src_path);
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

	    CGImageRef dst_im = copy_scaled_image(src_im, size,
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

- (void)removeImageHost:(id<PDImageHost>)obj
{
  NSArray *ops = [_imageHosts objectForKey:obj];
  if (ops == nil)
    return;

  for (NSOperation *op in ops)
    [op cancel];

  [_imageHosts removeObjectForKey:obj];
}

- (void)updateImageHost:(id<PDImageHost>)obj
{
  /* FIXME: not ideal, but ok for now. (Actually, it's quite bad. E.g.
     when zooming in above 100% we load the full-size image again for
     no reason.) */

  [self removeImageHost:obj];
  [self addImageHost:obj];
}

@end
