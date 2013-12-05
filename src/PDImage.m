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
#import "PDImageProperty.h"

#import <QuartzCore/CATransaction.h>

#import <sys/stat.h>

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

static size_t
file_size(NSString *path)
{
  struct stat st;

  if (stat([path fileSystemRepresentation], &st) == 0)
    return st.st_size;
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

  static NSString *cache_path;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    NSArray *paths = (NSSearchPathForDirectoriesInDomains
		      (NSCachesDirectory, NSUserDomainMask, YES));
    cache_path = [[[[paths lastObject] stringByAppendingPathComponent:
		    [[NSBundle mainBundle] bundleIdentifier]]
		   stringByAppendingPathComponent:@CACHE_DIR]
		  copy];
  });

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
  static dispatch_once_t once;

  dispatch_once(&once, ^{
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
  });

  return [dict objectForKey:[ext lowercaseString]];
}

static NSSet *
raw_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    set = [[NSSet alloc] initWithObjects:
	   @"arw", @"cr2", @"crw", @"dng", @"fff", @"3fr", @"tif",
	   @"tiff", @"raw", @"nef", @"nrw", @"sr2", @"srf", @"srw",
	   @"erf", @"mrw", @"rw2", @"rwz", @"orf", nil];
  });

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

/* Originally I did the usual thing and deferred all I/O until it's
   actually needed to implement a method. But that tends to lead to
   non-deterministic blocking later. It's better to do all I/O up front
   assuming that whatever's loading the image library will do so
   ahead-of-time / asynchronously. */

- (id)initWithLibrary:(NSString *)libraryPath directory:(NSString *)dir
    name:(NSString *)name JSONPath:(NSString *)json_path
    JPEGPath:(NSString *)jpeg_path RAWPath:(NSString *)raw_path
{
  self = [super init];
  if (self == nil)
    return nil;

  _properties = [[NSMutableDictionary alloc] init];

  [_properties setObject:name forKey:PDImage_Name];

  _libraryPath = [libraryPath copy];
  _libraryDirectory = [dir copy];

  _JSONPath = [json_path copy];
  _JPEGPath = [jpeg_path copy];
  _RAWPath = [raw_path copy];

  if (_JSONPath != nil)
    {
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
    }

  /* This needs to be set even when NO, to prevent trying to
     load the implicit properties to find the ActiveType key. */

  NSString *jpeg_type = _JPEGPath != nil ? @"public.jpeg" : nil;
  NSString *raw_type = _RAWPath != nil
	? type_identifier_for_extension([_RAWPath pathExtension]) : nil;

  if (jpeg_type != nil || raw_type != nil)
    {
      if ([_properties objectForKey:PDImage_ActiveType] == nil)
	{
	  [_properties setObject:jpeg_type ? jpeg_type : raw_type
	   forKey:PDImage_ActiveType];
	}

      if ([_properties objectForKey:PDImage_FileTypes] == nil)
	{
	  id objects[2];
	  size_t count = 0;
	  if (jpeg_type != nil)
	    objects[count++] = jpeg_type;
	  if (raw_type != nil)
	    objects[count++] = raw_type;

	  [_properties setObject:[NSArray arrayWithObjects:objects count:count]
	   forKey:PDImage_FileTypes];
	}
    }

  /* FIXME: if we switch from JPEG to RAW or vice versa, should we
     invalidate and reload these properties? */

  CGImageSourceRef src = create_image_source_from_path([self imagePath]);

  if (src != NULL)
    {
      _implicitProperties = PDImageSourceCopyProperties(src);
      CFRelease(src);
    }

  _imageHosts = [[NSMapTable strongToStrongObjectsMapTable] retain];

  return self;
}

+ (void)loadImagesInLibrary:(NSString *)libraryPath directory:(NSString *)dir
    handler:(void (^)(PDImage *))block;
{
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [libraryPath stringByAppendingPathComponent:dir];

  NSSet *filenames = [[NSSet alloc] initWithArray:
		      [fm contentsOfDirectoryAtPath:dir_path error:nil]];

  NSMutableSet *stems = [[NSMutableSet alloc] init];

  for (NSString *file in filenames)
    {
      @autoreleasepool
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
	      block(image);
	      [image release];
	    }
	}
    }

  [stems release];
  [filenames release];
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

  [_date release];

  [super dealloc];
}

- (void)didLoadJSONDictionary:(NSDictionary *)dict
{
  NSDictionary *props = [dict objectForKey:@"Properties"];

  if (props != nil)
    [_properties addEntriesFromDictionary:props];
}

- (void)writeJSONFile
{
  if (!_pendingJSONWrite)
    {
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
			      [NSDictionary dictionaryWithDictionary:
			       _properties], @"Properties", nil];
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
  id value = [_properties objectForKey:key];

  if (value == nil)
    value = [_implicitProperties objectForKey:key];

  if (value == nil)
    {
      /* A few specially coded properties. */

      if ([key isEqualToString:PDImage_FileName])
	{
	  value = [[self imagePath] lastPathComponent];
	}
      else if ([key isEqualToString:PDImage_FilePath])
	{
	  value = [self imagePath];
	}
      else if ([key isEqualToString:PDImage_FileDate])
	{
	  value = [NSNumber numberWithUnsignedLong:
		   file_mtime([self imagePath])];
	}
      else if ([key isEqualToString:PDImage_FileSize])
	{
	  value = [NSNumber numberWithUnsignedLong:
		   file_size([self imagePath])];
	}
      else if ([key isEqualToString:PDImage_Rejected])
	{
	  value = [self imagePropertyForKey:PDImage_Rating];
	  if (value != nil)
	    value = [NSNumber numberWithBool:[value intValue] < 0];
	}
    }

  if ([value isKindOfClass:[NSNull class]])
    value = nil;

  return value;
}

- (void)installImagePropertiesDictionary:(NSDictionary *)dict
{
  if (_implicitProperties == nil)
    _implicitProperties = [dict copy];
}

- (void)setImageProperty:(id)obj forKey:(NSString *)key
{
  if (obj == nil)
    obj = [NSNull null];

  id oldValue = [_properties objectForKey:key];

  if (![oldValue isEqual:obj])
    {
      [_properties setObject:obj forKey:key];

      [self writeJSONFile];

      if (_date != nil
	  && ([key isEqualToString:PDImage_OriginalDate]
	      || [key isEqualToString:PDImage_DigitizedDate]))
	{
	  [_date release], _date = nil;
	}

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImagePropertyDidChange object:self
       userInfo:[NSDictionary dictionaryWithObject:key forKey:@"key"]];
    }
}

+ (BOOL)imagePropertyIsEditableInUI:(NSString *)key
{
  static NSSet *editable_keys;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    editable_keys = [[NSSet alloc] initWithObjects:PDImage_Name,
		     PDImage_Title, PDImage_Caption, PDImage_Keywords,
		     PDImage_Copyright, nil];
  });

  return [editable_keys containsObject:key];
}

+ (NSString *)localizedNameOfImageProperty:(NSString *)key
{
  return PDImageLocalizedNameOfProperty(key);
}

- (NSString *)localizedImagePropertyForKey:(NSString *)key
{
  id value = [self imagePropertyForKey:key];
  if (value == nil)
    return nil;

  return PDImageLocalizedPropertyValue(key, value, self);
}

- (void)setLocalizedImageProperty:(NSString *)str forKey:(NSString *)key
{
  id value = PDImageUnlocalizedPropertyValue(key, str, self);
  if (value == nil)
    return;

  [self setImageProperty:value forKey:key];
}

- (id)expressionValues
{
  return PDImageExpressionValues(self);
}

+ (void)callWithImageComparator:(PDImageCompareKey)key
    reversed:(BOOL)flag block:(void (^)(NSComparator))block
{
  block (^(id obj1, id obj2)
    {
      NSComparisonResult ret;
      if (obj1 == obj2)
	ret = NSOrderedSame;
      else if (obj1 == nil)
	ret = NSOrderedAscending;
      else if (obj2 == nil)
	ret = NSOrderedDescending;
      else
	{
	  switch ((enum PDImageCompareKey)key)
	    {
	      NSString *key;

	    case PDImageCompare_FileName: {
	      NSString *s1 = [[obj1 imagePath] lastPathComponent];
	      NSString *s2 = [[obj2 imagePath] lastPathComponent];
	      ret = [s1 compare:s2];
	      goto got_ret; }

	    case PDImageCompare_FileDate: {
	      time_t t1 = file_mtime([obj1 imagePath]);
	      time_t t2 = file_mtime([obj2 imagePath]);
	      ret = (t1 < t2 ? NSOrderedAscending
		     : t1 > t2 ? NSOrderedDescending : NSOrderedSame);
	      goto got_ret; }

	    case PDImageCompare_FileSize: {
	      size_t s1 = file_size([obj1 imagePath]);
	      size_t s2 = file_size([obj2 imagePath]);
	      ret = (s1 < s2 ? NSOrderedAscending
		     : s1 > s2 ? NSOrderedDescending : NSOrderedSame);
	      goto got_ret; }

	    case PDImageCompare_Date:
	      obj1 = [obj1 date];
	      obj2 = [obj2 date];
	      break;

	    case PDImageCompare_PixelSize: {
	      CGSize size1 = [obj1 pixelSize];
	      CGSize size2 = [obj2 pixelSize];
	      obj1 = obj2 = nil;
	      if (size1.width != 0 && size1.height != 0)
		obj1 = [NSNumber numberWithDouble:size1.width * size1.height];
	      if (size2.width != 0 && size2.height != 0)
		obj2 = [NSNumber numberWithDouble:size2.width * size2.height];
	      break; }

	    case PDImageCompare_Name:
	      key = PDImage_Name;
	      goto do_key;
	    case PDImageCompare_Keywords:
	      key = PDImage_Keywords;
	      goto do_key;
	    case PDImageCompare_Caption:
	      key = PDImage_Caption;
	      goto do_key;
	    case PDImageCompare_Rating:
	      key = PDImage_Rating;
	      goto do_key;
	    case PDImageCompare_Flagged:
	      key = PDImage_Flagged;
	      goto do_key;
	    case PDImageCompare_Orientation:
	      key = PDImage_Orientation;
	      goto do_key;
	    case PDImageCompare_Altitude:
	      key = PDImage_Altitude;
	      goto do_key;
	    case PDImageCompare_ExposureLength:
	      key = PDImage_ExposureLength;
	      goto do_key;
	    case PDImageCompare_FNumber:
	      key = PDImage_FNumber;
	      goto do_key;
	    case PDImageCompare_ISOSpeed:
	      key = PDImage_ISOSpeed;
	      /* fall through */
	    do_key:
	      obj1 = [obj1 imagePropertyForKey:key];
	      obj2 = [obj2 imagePropertyForKey:key];
	      break;
	    }

	  if (obj1 == obj2)
	    ret = NSOrderedSame;
	  else if (obj1 == nil)
	    ret = NSOrderedAscending;
	  else if (obj2 == nil)
	    ret = NSOrderedDescending;
	  else if ([obj1 respondsToSelector:@selector(compare:)])
	    ret = [obj1 compare:obj2];
	  else
	    ret = NSOrderedSame;
	}

    got_ret:
      return flag ? -ret : ret;
    });
}

+ (NSString *)imageCompareKeyString:(PDImageCompareKey)key
{
  switch (key)
    {
    case PDImageCompare_FileName:
      return @"FileName";
    case PDImageCompare_FileDate:
      return @"FileDate";
    case PDImageCompare_FileSize:
      return @"FileSize";
    case PDImageCompare_Name:
      return @"Name";
    case PDImageCompare_Date:
      return @"Date";
    case PDImageCompare_Keywords:
      return @"Keywords";
    case PDImageCompare_Caption:
      return @"Caption";
    case PDImageCompare_Rating:
      return @"Rating";
    case PDImageCompare_Flagged:
      return @"Flagged";
    case PDImageCompare_Orientation:
      return @"Orientation";
    case PDImageCompare_PixelSize:
      return @"PixelSize";
    case PDImageCompare_Altitude:
      return @"Altitude";
    case PDImageCompare_ExposureLength:
      return @"ExposureLength";
    case PDImageCompare_FNumber:
      return @"FNumber";
    case PDImageCompare_ISOSpeed:
      return @"ISOSpeed";
    }

  return @"";
}

+ (PDImageCompareKey)imageCompareKeyFromString:(NSString *)str
{
  if ([str isEqualToString:@"FileName"])
    return PDImageCompare_FileName;
  else if ([str isEqualToString:@"FileDate"])
    return PDImageCompare_FileDate;
  else if ([str isEqualToString:@"FileSize"])
    return PDImageCompare_FileSize;
  else if ([str isEqualToString:@"Name"])
    return PDImageCompare_Name;
  else if ([str isEqualToString:@"Date"])
    return PDImageCompare_Date;
  else if ([str isEqualToString:@"Keywords"])
    return PDImageCompare_Keywords;
  else if ([str isEqualToString:@"Caption"])
    return PDImageCompare_Caption;
  else if ([str isEqualToString:@"Rating"])
    return PDImageCompare_Rating;
  else if ([str isEqualToString:@"Flagged"])
    return PDImageCompare_Flagged;
  else if ([str isEqualToString:@"Orientation"])
    return PDImageCompare_Orientation;
  else if ([str isEqualToString:@"PixelSize"])
    return PDImageCompare_PixelSize;
  else if ([str isEqualToString:@"Altitude"])
    return PDImageCompare_Altitude;
  else if ([str isEqualToString:@"ExposureLength"])
    return PDImageCompare_ExposureLength;
  else if ([str isEqualToString:@"FNumber"])
    return PDImageCompare_FNumber;
  else if ([str isEqualToString:@"ISOSpeed"])
    return PDImageCompare_ISOSpeed;
  else
    return PDImageCompare_Date;
}

- (NSDate *)date
{
  if (_date == nil)
    {
      id date = nil;
      NSString *str = [self imagePropertyForKey:PDImage_OriginalDate];
      if (str == nil)
	str = [self imagePropertyForKey:PDImage_DigitizedDate];
      if (str != nil)
	date = PDImageParseEXIFDateString(str);
      if (date == nil)
	{
	  date = [NSDate dateWithTimeIntervalSince1970:
		  file_mtime([self imagePath])];
	}
      _date = [date copy];
    }

  return _date;
}

- (NSString *)name
{
  return [self imagePropertyForKey:PDImage_Name];
}

- (NSString *)title
{
  return [self imagePropertyForKey:PDImage_Title];
}

- (BOOL)isHidden
{
  return [[self imagePropertyForKey:PDImage_Hidden] boolValue];
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
