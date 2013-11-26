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

#define N_ELEMENTS(x) (sizeof(x) / sizeof((x)[0]))

#define METADATA_EXTENSION "phod"

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

NSString *const PDImagePropertyDidChange = @"PDImagePropertyDidChange";

NSString * const PDImage_Name = @"Name";
NSString * const PDImage_ActiveType = @"ActiveType";
NSString * const PDImage_FileTypes = @"FileTypes";
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
NSString * const PDImage_Flagged = @"Flagged";

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

static NSString *
type_identifier_for_extension(NSString *ext)
{
  static NSDictionary *dict;

  if (dict == nil)
    {
      NSMutableDictionary *tem = [[NSMutableDictionary alloc] init];

      CFArrayRef types = CGImageSourceCopyTypeIdentifiers();

      for (NSString *type in (id)types)
	{
	  /* FIXME: remove this private API usage. Static table? */

	  extern CFArrayRef CGImageSourceCopyTypeExtensions(CFStringRef);

	  CFArrayRef exts = CGImageSourceCopyTypeExtensions((CFStringRef)type);

	  if (exts != NULL)
	    {
	      for (NSString *ext in (id)exts)
		[tem setObject:type forKey:ext];

	      CFRelease(exts);
	    }
	}

      CFRelease(types);

      dict = [tem copy];
      [tem release];
    }

  return [dict objectForKey:[ext lowercaseString]];
}

static NSSet *
raw_extensions(void)
{
  static NSSet *set;

  if (set == nil)
    {
      set = [[NSSet alloc] initWithObjects:
	     @"arw", @"cr2", @"crw", @"dng", @"fff", @"3fr", @"tif",
	     @"tiff", @"raw", @"nef", @"nrw", @"sr2", @"srf", @"srw",
	     @"erf", @"mrw", @"rw2", @"rwz", @"orf", nil];
    }

  return set;
}

/* 'ext' must be lowercase. */

static NSString *
filename_with_extension(NSString *path, NSSet *filenames,
			NSString *stem, NSString *ext)
{
  NSString *lower = [stem stringByAppendingPathExtension:ext];
  if ([filenames containsObject:lower])
    return [path stringByAppendingPathComponent:lower];

  NSString *upper = [stem stringByAppendingPathExtension:
		     [ext uppercaseString]];
  if ([filenames containsObject:upper])
    return [path stringByAppendingPathComponent:upper];

  return nil;
}

static NSString *
filename_with_extension_in_set(NSString *path, NSSet *filenames,
			       NSString *stem, NSSet *exts)
{
  for (NSString *ext in exts)
    {
      NSString *ret = filename_with_extension(path, filenames, stem, ext);
      if (ret != nil)
	return ret;
    }

  return nil;
}

@implementation PDImage

@synthesize libraryPath = _libraryPath;
@synthesize libraryDirectory = _libraryDirectory;
@synthesize JSONPath = _JSONPath;

static NSOperationQueue *_wideQueue;
static NSOperationQueue *_narrowQueue;

+ (NSOperationQueue *)wideQueue
{
  if (_wideQueue == nil)
    {
      _wideQueue = [[NSOperationQueue alloc] init];
      [_wideQueue setName:@"PDImage.wideQueue"];
      [_wideQueue addObserver:(id)self
       forKeyPath:@"operationCount" options:0 context:NULL];
    }

  return _wideQueue;
}

+ (NSOperationQueue *)narrowQueue
{
  if (_narrowQueue == nil)
    {
      _narrowQueue = [[NSOperationQueue alloc] init];
      [_narrowQueue setName:@"PDImage.narrowQueue"];
      [_narrowQueue setMaxConcurrentOperationCount:1];
      [_narrowQueue addObserver:(id)self
       forKeyPath:@"operationCount" options:0 context:NULL];
    }

  return _narrowQueue;
}

+ (NSOperationQueue *)writeQueue
{
  static NSOperationQueue *_writeQueue;

  if (_writeQueue == nil)
    {
      _writeQueue = [[NSOperationQueue alloc] init];
      [_writeQueue setName:@"PDImage.writeQueue"];
      [_writeQueue setMaxConcurrentOperationCount:1];
    }

  return _writeQueue;
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

- (id)initWithLibrary:(NSString *)libraryPath directory:(NSString *)dir
    name:(NSString *)name JSONPath:(NSString *)json_path
    JPEGPath:(NSString *)jpeg_path RAWPath:(NSString *)raw_path
{
  self = [super init];
  if (self == nil)
    return nil;

  _properties = [[NSMutableDictionary alloc] init];

  _libraryPath = [libraryPath copy];
  _libraryDirectory = [dir copy];

  _JSONPath = [json_path copy];
  _JPEGPath = [jpeg_path copy];
  _RAWPath = [raw_path copy];

  _pendingJSONRead = _JSONPath != nil;

  [_properties setObject:name forKey:PDImage_Name];

  /* This needs to be set even when NO, to prevent trying to
     load the implicit properties to find the ActiveType key. */

  NSString *jpeg_type = _JPEGPath != nil ? @"public.jpeg" : nil;
  NSString *raw_type = _RAWPath != nil
	? type_identifier_for_extension([_RAWPath pathExtension]) : nil;

  [_properties setObject:jpeg_type ? jpeg_type : raw_type
   forKey:PDImage_ActiveType];

  [_properties setObject:
   [NSArray arrayWithObjects:jpeg_type != nil ? jpeg_type : raw_type,
    raw_type != nil ? raw_type : jpeg_type, nil] forKey:PDImage_FileTypes];

  _imageHosts = [[NSMapTable strongToStrongObjectsMapTable] retain];

  return self;
}

+ (NSArray *)imagesInLibrary:(NSString *)libraryPath
    directory:(NSString *)dir filter:(BOOL (^)(NSString *name))block
{
  NSMutableArray *array = [[NSMutableArray alloc] init];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [libraryPath stringByAppendingPathComponent:dir];

  NSSet *filenames = [[NSSet alloc] initWithArray:
		      [fm contentsOfDirectoryAtPath:dir_path error:nil]];

  NSMutableSet *stems = [[NSMutableSet alloc] init];

  for (NSString *file in filenames)
    {
      if ([file characterAtIndex:0] == '.')
	continue;

      NSString *path = [dir_path stringByAppendingPathComponent:file];
      BOOL is_dir = NO;
      if (![fm fileExistsAtPath:path isDirectory:&is_dir] || is_dir)
	continue;

      NSString *ext = [[file pathExtension] lowercaseString];

      if (![ext isEqualToString:@METADATA_EXTENSION]
	  && ![ext isEqualToString:@"jpg"]
	  && ![ext isEqualToString:@"jpeg"]
	  && ![raw_extensions() containsObject:ext])
	{
	  continue;
	}

      NSString *stem = [file stringByDeletingPathExtension];
      if ([stems containsObject:stem])
	continue;

      [stems addObject:stem];

      if (block != nil && !block(stem))
	continue;

      NSString *json_path
	= filename_with_extension(dir_path, filenames,
				  stem, @METADATA_EXTENSION);
      NSString *jpeg_path
	= filename_with_extension(dir_path, filenames, stem, @"jpg");
      if (jpeg_path == nil)
	{
	  jpeg_path = filename_with_extension(dir_path, filenames,
					      stem, @"jpeg");
	}
      NSString *raw_path
	= filename_with_extension_in_set(dir_path, filenames,
					 stem, raw_extensions());

      PDImage *image = [[self alloc] initWithLibrary:libraryPath
			directory:dir name:stem JSONPath:json_path
			JPEGPath:jpeg_path RAWPath:raw_path];
      if (image != nil)
	{
	  [array addObject:image];
	  [image release];
	}
    }

  NSArray *result = [NSArray arrayWithArray:array];

  [stems release];
  [filenames release];
  [array release];

  return result;
}

- (void)dealloc
{
  [_libraryPath release];
  [_libraryDirectory release];
  [_JSONPath release];
  [_JPEGPath release];
  [_JPEGHash release];
  [_RAWPath release];
  [_RAWHash release];

  [_properties release];
  [_implicitProperties release];

  assert([_imageHosts count] == 0);
  [_imageHosts release];

  [_prefetchOp cancel];
  [_prefetchOp release];

  [super dealloc];
}

- (void)readJSONFile
{
  if (_pendingJSONRead)
    {
      assert (_JSONPath != nil);

      NSData *data = [[NSData alloc] initWithContentsOfFile:_JSONPath];

      if (data != nil)
	{
	  NSDictionary *dict = [NSJSONSerialization
				JSONObjectWithData:data options:0 error:nil];
	  if (dict != nil)
	    {
	      NSDictionary *props = [dict objectForKey:@"Properties"];
	      if (props != nil)
		[_properties addEntriesFromDictionary:props];
	    }
	  [data release];
	}

      _pendingJSONRead = NO;
    }
}

- (void)prefetchJSONFile
{
  if (_pendingJSONRead)
    {
      assert (_JSONPath != nil);

      NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
	if (_pendingJSONRead)
	  {
	    NSLog(@"prefetching JSON %@", _JSONPath);
	    NSData *data = [[NSData alloc] initWithContentsOfFile:_JSONPath];
	    if (data != nil)
	      {
		NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:
				      data options:0 error:nil];
		if (dict != nil)
		  {
		    dispatch_async(dispatch_get_main_queue(), ^{
		      if (_pendingJSONRead)
			{
			  NSDictionary *props
			    = [dict objectForKey:@"Properties"];
			  if (props != nil)
			    [_properties addEntriesFromDictionary:props];
			  _pendingJSONRead = NO;
			}
		    });
		  }
		[data release];
	      }
	  }
      }];

      [op setQueuePriority:NSOperationQueuePriorityLow];
      [[PDImage wideQueue] addOperation:op];
    }
}

- (void)writeJSONFile
{
  if (!_pendingJSONWrite)
    {
      [self readJSONFile];

      if (_JSONPath == nil)
	{
	  _JSONPath = [[[_libraryPath stringByAppendingPathComponent:
			 _libraryDirectory] stringByAppendingPathComponent:
			[[self name] stringByAppendingPathExtension:
			 @METADATA_EXTENSION]] copy];
	}

      dispatch_time_t then
        = dispatch_time(DISPATCH_TIME_NOW, 2LL * NSEC_PER_SEC);

      dispatch_after(then, dispatch_get_main_queue(), ^{

	/* Copying data out of self, as operation runs asynchronously.

	   FIXME: what else should be added to this dictionary? */

	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
			      [_properties copy], @"Properties",
			      nil];
	NSString *path = [_JSONPath copy];

	NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
	  NSData *data = [NSJSONSerialization dataWithJSONObject:dict
			  options:NSJSONWritingPrettyPrinted error:nil];
	  [data writeToFile:path atomically:YES];
	}];

	[path release];

	[[PDImage writeQueue] addOperation:op];
	_pendingJSONWrite = NO;
      });

      _pendingJSONWrite = YES;
    }
}

- (NSString *)lastLibraryPathComponent
{
  NSString *str = [_libraryDirectory lastPathComponent];
  if ([str length] == 0)
    str = [_libraryPath lastPathComponent];
  return str;
}

- (NSString *)imagePath
{
  return [self usesRAW] ? _RAWPath : _JPEGPath;
}

- (PDImageHash *)imageHash
{
  BOOL uses_raw = [self usesRAW];

  PDImageHash **hash_ptr = uses_raw ? &_RAWHash : &_JPEGHash;

  if (*hash_ptr == nil)
    {
      *hash_ptr = [[PDImageHash fileHash:
		    uses_raw ? _RAWPath : _JPEGPath] retain];
    }

  return *hash_ptr;
}

- (id)imagePropertyForKey:(NSString *)key
{
  if (_pendingJSONRead)
    [self readJSONFile];

  id value = [_properties objectForKey:key];

  if (value == nil)
    {
      if (_implicitProperties == nil)
	{
	  /* FIXME: if we switch from JPEG to RAW or vice versa, should
	     we invalidate and reload these properties? */

	  CGImageSourceRef src
	    = create_image_source_from_path([self imagePath]);

	  if (src != NULL)
	    {
	      _implicitProperties = copy_image_properties(src);
	      CFRelease(src);
	    }
	}

      value = [_implicitProperties objectForKey:key];
    }

  if ([value isKindOfClass:[NSNull class]])
    value = nil;

  return value;
}

- (void)prefetchImageProperties
{
  if (_implicitProperties == nil)
    {
      NSString *path = [self imagePath];

      NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
	if (_implicitProperties == nil)
	  {
	    NSLog(@"prefetching image properties %@", path);
	    CGImageSourceRef src = create_image_source_from_path(path);
	    if (src != NULL)
	      {
		NSDictionary *dict = copy_image_properties(src);
		if (dict != nil)
		  {
		    dispatch_async(dispatch_get_main_queue(), ^{
		      if (_implicitProperties == nil)
			_implicitProperties = [dict retain];
		    });
		    [dict release];
		  }
		CFRelease(src);
	      }
	  }
      }];

      [op setQueuePriority:NSOperationQueuePriorityLow];
      [[PDImage wideQueue] addOperation:op];
    }
}

- (void)prefetchMetadata
{
  [self prefetchJSONFile];
  [self prefetchImageProperties];
}

- (void)setImageProperty:(id)obj forKey:(NSString *)key
{
  if (obj == nil)
    obj = [NSNull null];

  if (_pendingJSONRead)
    [self readJSONFile];

  id oldValue = [_properties objectForKey:key];

  if (![oldValue isEqual:obj])
    {
      [_properties setObject:obj forKey:key];

      [self writeJSONFile];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImagePropertyDidChange object:self
       userInfo:[NSDictionary dictionaryWithObject:key forKey:@"key"]];
    }
}

+ (NSString *)localizedNameOfImageProperty:(NSString *)key
{
  return [[NSBundle mainBundle] localizedStringForKey:key
	  value:key table:@"image-properties"];
}

typedef enum
{
  type_unknown,
  type_bool,
  type_bytes,
  type_contrast,
  type_date,
  type_direction,
  type_duration,
  type_exposure_bias,
  type_exposure_mode,
  type_exposure_program,
  type_focus_mode,
  type_flash_compensation,
  type_flash_mode,
  type_fstop,
  type_image_stabilization_mode,
  type_iso_speed,
  type_latitude,
  type_light_source,
  type_longitude,
  type_metering_mode,
  type_metres,
  type_millimetres,
  type_orientation,
  type_pixels,
  type_rating,
  type_saturation,
  type_scene_capture_type,
  type_scene_type,
  type_sharpness,
  type_string,
  type_string_array,
  type_white_balance,
} property_type;

typedef struct {
  const char *name;
  property_type type;
} type_pair;

static const type_pair type_map[] =
{
  {"ActiveType", type_string},
  {"Altitude", type_metres},
  {"CameraMake", type_string},
  {"CameraModel", type_string},
  {"CameraSoftware", type_string},
  {"Caption", type_string},
  {"ColorModel", type_string},
  {"Contrast", type_contrast},
  {"Copyright", type_string},
  {"DigitizedDate", type_date},
  {"Direction", type_direction},
  {"DirectionRef", type_string},
  {"ExposureBias", type_exposure_bias},
  {"ExposureLength", type_duration},
  {"ExposureMode", type_exposure_mode},
  {"ExposureProgram", type_exposure_program},
  {"FNumber", type_fstop},
  {"FileSize", type_bytes},
  {"FileTypes", type_string_array},
  {"Flagged", type_bool},
  {"Flash", type_flash_mode},
  {"FlashCompensation", type_flash_compensation},
  {"FocalLength", type_millimetres},
  {"FocalLength35mm", type_millimetres},
  {"FocusMode", type_focus_mode},
  {"ISOSpeed", type_iso_speed},
  {"ImageStabilization", type_image_stabilization_mode},
  {"Keywords", type_string_array},
  {"Latitude", type_latitude},
  {"LightSource", type_light_source},
  {"Longitude", type_longitude},
  {"MaxAperture", type_fstop},		/* fixme: "APEX" aperture? */
  {"MeteringMode", type_metering_mode},
  {"Name", type_string},
  {"Orientation", type_orientation},
  {"OriginalDate", type_date},
  {"PixelHeight", type_pixels},
  {"PixelWidth", type_pixels},
  {"ProfileName", type_string},
  {"Rating", type_rating},
  {"Saturation", type_saturation},
  {"SceneCaptureType", type_scene_capture_type},
  {"SceneType", type_scene_type},
  {"Sharpness", type_sharpness},
  {"Title", type_string},
  {"WhiteBalance", type_white_balance},
};

static inline property_type
lookup_property_type(const char *name)
{
  const type_pair *ptr
    = bsearch_b(name, type_map, N_ELEMENTS(type_map), sizeof(type_map[0]),
		^(const void *a, const void *b) {
		  return strcmp(a, *(const char **)b);
		});

  return ptr != NULL ? ptr->type : type_unknown;
}

static inline NSString *
array_lookup(id value, NSString **array, size_t nelts)
{
  size_t i = [value unsignedIntValue];
  return i < nelts ? array[i] : @"Unknown";
}

static NSString *
degrees_string(void)
{
  static NSString *deg;

  if (deg == nil)
    {
      unichar c = 0x00b0;		/* DEGREE SIGN */
      deg = [[NSString alloc] initWithCharacters:&c length:1];
    }

  return deg;
}

static NSString *
exif_flash_mode(unsigned int x)
{
  switch (x)
    {
    case 0x00:
      return @"Flash did not fire";
    case 0x01:
      return @"Flash fired";
    case 0x05:
      return @"Strobe return light not detected";
    case 0x07:
      return @"Strobe return light detected";
    case 0x09:
      return @"Flash fired, compulsory flash mode";
    case 0x0d:
      return @"Flash fired, compulsory flash mode, return light not detected";
    case 0x0f:
      return @"Flash fired, compulsory flash mode, return light detected";
    case 0x10:
      return @"Flash did not fire, compulsory flash mode";
    case 0x18:
      return @"Flash did not fire, auto mode";
    case 0x19:
      return @"Flash fired, auto mode";
    case 0x1d:
      return @"Flash fired, auto mode, return light not detected";
    case 0x1f:
      return @"Flash fired, auto mode, return light detected";
    case 0x20:
      return @"No flash function";
    case 0x41:
      return @"Flash fired, red-eye reduction mode";
    case 0x45:
      return @"Flash fired, red-eye reduction mode, return light not detected";
    case 0x47:
      return @"Flash fired, red-eye reduction mode, return light detected";
    case 0x49:
      return @"Flash fired, compulsory flash mode, red-eye reduction mode";
    case 0x4d:
      return @"Flash fired, compulsory flash mode, red-eye reduction mode, return light not detected";
    case 0x4f:
      return @"Flash fired, compulsory flash mode, red-eye reduction mode, return light detected";
    case 0x59:
      return @"Flash fired, auto mode, red-eye reduction mode";
    case 0x5d:
      return @"Flash fired, auto mode, return light not detected, red-eye reduction mode";
    case 0x5f:
      return @"Flash fired, auto mode, return light detected, red-eye reduction mode}";
    default:
      return @"Unknown flash mode.";
    }
}

- (NSString *)localizedImagePropertyForKey:(NSString *)key
{
  static const NSString *contrast[] = {@"Normal", @"Low", @"High"};
  static const NSString *exposure_mode[] = {@"Auto Exposure",
    @"Manual Exposure", @"Auto Exposure Bracket"};
  static const NSString *white_balance[] = {@"Auto White Balance",
    @"Manual White Balance"};
  static const NSString *exposure_prog[] = {@"Unknown Program", @"Manual",
    @"Normal Program", @"Aperture Priority", @"Shutter Priority",
    @"Creative Program", @"Action Program", @"Portrait Mode",
    @"Landscape Mode", @"Bulb Mode"};
  static const NSString *metering_mode[] = {@"Unknown", @"Average",
    @"Center-Weighted Average", @"Spot", @"Multi-Spot", @"Pattern",
    @"Partial"};

  id value = [self imagePropertyForKey:key];
  if (value == nil)
    return nil;

  switch (lookup_property_type([key UTF8String]))
    {
      double x;
      const char *str;

    case type_bool:
      return [value boolValue] ? @"True" : @"False";

    case type_contrast:
      return array_lookup(value, contrast, N_ELEMENTS(contrast));
	
    case type_direction:
      str = ![[self imagePropertyForKey:PDImage_DirectionRef]
	      isEqual:@"T"] ? "Magnetic North" : "True North";
      return [NSString stringWithFormat:@"%g%@ %s",
	      [value doubleValue], degrees_string(), str];

    case type_exposure_bias:
      return [NSString stringWithFormat:@"%.2g ev", [value doubleValue]];

    case type_fstop:
      return [NSString stringWithFormat:@"f/%g", [value doubleValue]];

    case type_duration:
      if ([value doubleValue] < 1)
	return [NSString stringWithFormat:@"1/%g", 1/[value doubleValue]];
      else
	return [NSString stringWithFormat:@"%g", [value doubleValue]];

    case type_exposure_mode:
      return array_lookup(value, exposure_mode, N_ELEMENTS(exposure_mode));

    case type_exposure_program:
      return array_lookup(value, exposure_prog, N_ELEMENTS(exposure_prog));

    case type_flash_mode:
      return exif_flash_mode([value unsignedIntValue]);

    case type_iso_speed:
      return [NSString stringWithFormat:@"ISO %g", [value doubleValue]];

    case type_latitude:
      x = [value doubleValue];
      return [NSString stringWithFormat:@"%g%@ %s",
	      fabs(x), degrees_string(), x >= 0 ? "South" : "North"];

    case type_longitude:
      x = [value doubleValue];
      return [NSString stringWithFormat:@"%g%@ %s",
	      fabs(x), degrees_string(), x >= 0 ? "West" : "East"];

    case type_metering_mode:
      return array_lookup(value, metering_mode, N_ELEMENTS(metering_mode));

    case type_metres:
      return [NSString stringWithFormat:@"%gm", [value doubleValue]];

    case type_millimetres:
      return [NSString stringWithFormat:@"%gmm", [value doubleValue]];

    case type_white_balance:
      return array_lookup(value, white_balance, N_ELEMENTS(white_balance));

    case type_bytes:
    case type_date:
    case type_flash_compensation:
    case type_focus_mode:
    case type_image_stabilization_mode:
    case type_light_source:
    case type_orientation:
    case type_pixels:
    case type_rating:
    case type_saturation:
    case type_scene_capture_type:
    case type_scene_type:
    case type_sharpness:
    case type_string:
    case type_string_array:
      break;

    case type_unknown:
      break;
    }

  return [NSString stringWithFormat:@"%@", value];
}

- (NSString *)name
{
  return [self imagePropertyForKey:PDImage_Name];
}

- (NSString *)title
{
  NSString *str = [self imagePropertyForKey:PDImage_Title];
  if (str == nil)
    str = [self imagePropertyForKey:PDImage_Name];
  return str;
}

- (BOOL)usesRAW
{
  NSString *str = [self imagePropertyForKey:PDImage_ActiveType];
  if (str == nil || _RAWPath == nil)
    return NO;
  else
    return ![str isEqualToString:@"public.jpeg"];
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

      PDImageHash *hash = [self imageHash];
      NSString *path = [self imagePath];

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
      [[PDImage narrowQueue] addOperation:_prefetchOp];
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

  PDImageHash *hash = [self imageHash];
  NSString *path = [self imagePath];

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

  NSOperationQueue *q1 = [PDImage wideQueue];
  NSOperationQueue *q2 = [PDImage narrowQueue];
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
