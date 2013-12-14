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
#import "PDImageLibrary.h"
#import "PDImageProperty.h"

#import <QuartzCore/CATransaction.h>

#import <sys/stat.h>

#define METADATA_EXTENSION "phod"

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

@interface PDImage ()
- (void)loadImageProperties;
@end

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
cache_path_for_type(PDImageLibrary *lib, uint32_t file_id, NSInteger type)
{
  NSString *name;
  if (type == PDImage_Tiny)
    name = @"t.jpg";
  else if (type == PDImage_Small)
    name = @"s.jpg";
  else /* if (type == PDImage_Medium) */
    name = @"m.jpg";

  return [lib cachePathForFileId:file_id base:name];
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

@implementation PDImage

@synthesize library = _library;
@synthesize libraryDirectory = _libraryDirectory;
@synthesize JSONFile = _jsonFile;
@synthesize JPEGFile = _jpegFile;
@synthesize RAWFile = _rawFile;

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

static NSString *
library_file_path(PDImage *self, NSString *file)
{
  return [self->_libraryDirectory stringByAppendingPathComponent:file];
}

static NSString *
file_path(PDImage *self, NSString *file)
{
  return [[self->_library path] stringByAppendingPathComponent:
	  library_file_path(self, file)];
}

/* Originally I did the usual thing and deferred all I/O until it's
   actually needed to implement a method. But that tends to lead to
   non-deterministic blocking later. It's better to do all I/O up front
   assuming that whatever's loading the image library will do so
   ahead-of-time / asynchronously. */

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
    JSONFile:(NSString *)json_file JPEGFile:(NSString *)jpeg_file
    RAWFile:(NSString *)raw_file
{
  self = [super init];
  if (self == nil)
    return nil;

  _properties = [[NSMutableDictionary alloc] init];

  _library = [lib retain];
  _libraryDirectory = [dir copy];
  _jsonFile = [json_file copy];

  if (_jsonFile != nil)
    {
      NSString *json_path = file_path(self, _jsonFile);
      NSData *data = [[NSData alloc] initWithContentsOfFile:json_path];

      if (data != nil)
	{
	  NSDictionary *dict = [NSJSONSerialization
				JSONObjectWithData:data options:0 error:nil];
	  if (dict != nil)
	    {
	      NSDictionary *props = [dict objectForKey:@"Properties"];
	      if (props != nil)
		[_properties addEntriesFromDictionary:props];

	      _jpegFile = [[dict objectForKey:@"JPEGFile"] copy];
	      _rawFile = [[dict objectForKey:@"RAWFile"] copy];
	    }

	  [data release];
	}
    }

  if (_jpegFile == nil)
    _jpegFile = [jpeg_file copy];
  if (_rawFile == nil)
    _rawFile = [raw_file copy];

  if (_jpegFile != nil)
    _jpegType = [@"public.jpeg" copy];
  if (_rawFile != nil)
    _rawType = [type_identifier_for_extension([_rawFile pathExtension]) copy];

  if (_jpegType == nil && _rawType == nil)
    {
      [self release];
      return nil;
    }

  if ([_properties objectForKey:PDImage_ActiveType] == nil)
    {
      [_properties setObject:_jpegType ? _jpegType : _rawType
       forKey:PDImage_ActiveType];
    }

  if ([_properties objectForKey:PDImage_FileTypes] == nil)
    {
      id objects[2];
      size_t count = 0;
      if (_jpegType != nil)
	objects[count++] = _jpegType;
      if (_rawType != nil)
	objects[count++] = _rawType;

      [_properties setObject:[NSArray arrayWithObjects:objects count:count]
       forKey:PDImage_FileTypes];
    }

  if ([_properties objectForKey:PDImage_Name] == nil)
    {
      NSString *name = [_jpegFile != nil ? _jpegFile : _rawFile
			stringByDeletingPathExtension];
      [_properties setObject:name forKey:PDImage_Name];
    }

  [self loadImageProperties];

  _imageHosts = [[NSMapTable strongToStrongObjectsMapTable] retain];

  return self;
}

- (void)dealloc
{
  [_library release];
  [_libraryDirectory release];
  [_jsonFile release];
  [_jpegType release];
  [_jpegFile release];
  [_rawType release];
  [_rawFile release];

  [_properties release];
  [_implicitProperties release];

  assert([_imageHosts count] == 0);
  [_imageHosts release];

  [_prefetchOp cancel];
  [_prefetchOp release];

  [_date release];

  [super dealloc];
}

- (void)writeJSONFile
{
  if (!_pendingJSONWrite)
    {
      if (_jsonFile == nil)
	{
	  _jsonFile = [[[[self imageFile] stringByDeletingPathExtension]
			stringByAppendingPathExtension:@METADATA_EXTENSION]
		       copy];
	}

      dispatch_time_t then
        = dispatch_time(DISPATCH_TIME_NOW, 2LL * NSEC_PER_SEC);

      dispatch_after(then, dispatch_get_main_queue(), ^{

	/* Copying mutable data out of self, as op runs asynchronously.

	   FIXME: what else should be added to this dictionary? */

	NSMutableDictionary *dict = [NSMutableDictionary dictionary];

	[dict setObject:[NSDictionary dictionaryWithDictionary:_properties]
	 forKey:@"Properties"];

	if (_jpegFile != nil)
	  [dict setObject:_jpegFile forKey:@"JPEGFile"];
	if (_rawFile != nil)
	  [dict setObject:_rawFile forKey:@"RAWFile"];

	NSString *path = file_path(self, _jsonFile);

	NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
	  NSData *data = [NSJSONSerialization dataWithJSONObject:dict
			  options:NSJSONWritingPrettyPrinted error:nil];
	  [data writeToFile:path atomically:YES];
	}];

	[[PDImage writeQueue] addOperation:op];
	_pendingJSONWrite = NO;
      });

      _pendingJSONWrite = YES;
    }
}

- (NSString *)JPEGPath
{
  if (_jpegFile != nil)
    return file_path(self, _jpegFile);
  else
    return nil;
}

- (NSString *)RAWPath
{
  if (_rawFile != nil)
    return file_path(self, _rawFile);
  else
    return nil;
}

- (NSString *)lastLibraryPathComponent
{
  NSString *str = [_libraryDirectory lastPathComponent];
  if ([str length] == 0)
    str = [[_library path] lastPathComponent];
  return str;
}

- (NSString *)imageFile
{
  return [self usesRAW] ? _rawFile : _jpegFile;
}

- (NSString *)imagePath
{
  return file_path(self, [self imageFile]);
}

- (uint32_t)imageId
{
  BOOL uses_raw = [self usesRAW];

  uint32_t *id_ptr = uses_raw ? &_rawId : &_jpegId;

  if (*id_ptr == 0)
    {
      *id_ptr = [_library fileIdOfRelativePath:
		 library_file_path(self, uses_raw ? _rawFile : _jpegFile)];
    }

  return *id_ptr;
}

- (id)imagePropertyForKey:(NSString *)key
{
  id value = [_properties objectForKey:key];

  if (value == nil)
    {
      if (_implicitProperties == nil)
	[self loadImageProperties];

      value = [_implicitProperties objectForKey:key];
    }

  if (value == nil)
    {
      /* A few specially coded properties. */

      if ([key isEqualToString:PDImage_Date])
	{
	  value = [NSNumber numberWithUnsignedLong:
		   [[self date] timeIntervalSince1970]];
	}
      else if ([key isEqualToString:PDImage_FileName])
	{
	  value = [self imageFile];
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

      if (_donePrefetch && [key isEqualToString:PDImage_ActiveType])
	{
	  [self stopPrefetching];
	  [_prefetchOp release];
	  _prefetchOp = nil;
	  _donePrefetch = NO;

	  [_implicitProperties release];
	  _implicitProperties = nil;
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

- (NSDictionary *)explicitProperties
{
  return _properties;
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
	      NSString *s1 = [obj1 imageFile];
	      NSString *s2 = [obj2 imageFile];
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
      id value = [self imagePropertyForKey:PDImage_OriginalDate];
      if (value == nil)
	value = [self imagePropertyForKey:PDImage_DigitizedDate];
      time_t t = (value != nil
		  ? [value unsignedLongValue]
		  : file_mtime([self imagePath]));
      _date = [[NSDate alloc] initWithTimeIntervalSince1970:t];
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
  if (_rawType == nil)
    return NO;

  return [[self imagePropertyForKey:PDImage_ActiveType]
	  isEqualToString:_rawType];
}

- (void)setUsesRAW:(BOOL)flag
{
  if (flag && _rawType != nil)
    [self setImageProperty:_rawType forKey:PDImage_ActiveType];
  else if (!flag && _jpegType != nil)
    [self setImageProperty:_jpegType forKey:PDImage_ActiveType];
}

- (BOOL)supportsUsesRAW:(BOOL)flag
{
  if (flag)
    return _rawType != nil;
  else
    return _jpegType != nil;
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

- (void)loadImageProperties
{
  /* Translated image properties are written into the library's cache.
     Using JSON serialization, it's about 1/2 the size of
     NSKeyedArchiver and faster to load. (Speed is important, we load
     properties on startup as they're usually needed to sort the list
     of displayed images, which can be the entire library.) */

  NSString *cache_path
    = [_library cachePathForFileId:[self imageId] base:@"p.json"];

  NSString *image_path = [self imagePath];

  if (file_newer_than(cache_path, image_path))
    {
      NSData *data = [[NSData alloc] initWithContentsOfFile:cache_path];

      if (data != nil)
	{
	  id obj = [NSJSONSerialization
		    JSONObjectWithData:data options:0 error:nil];

	  if (obj != nil)
	    _implicitProperties = [obj copy];

	  [data release];
	}
    }

  if (_implicitProperties == nil)
    {
      CGImageSourceRef src = create_image_source_from_path(image_path);

      if (src != NULL)
	{
	  _implicitProperties = PDImageSourceCopyProperties(src);
	  CFRelease(src);
	}

      if (_implicitProperties != nil)
	{
	  id obj = _implicitProperties;
	  NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
	    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
			    options:0 error:nil];
	    [data writeToFile:cache_path atomically:YES];
	  }];

	  [[PDImage writeQueue] addOperation:op];
	}
    }
}

- (void)startPrefetching
{
  if (_prefetchOp == nil && !_donePrefetch)
    {
      /* Prevent the block retaining self. */

      PDImageLibrary *lib = [self library];
      uint32_t file_id = [self imageId];
      NSString *image_path = [self imagePath];

      NSString *tiny_path = cache_path_for_type(lib, file_id, PDImage_Tiny);

      if (file_newer_than(tiny_path, image_path))
	{
	  _donePrefetch = YES;
	  return;
	}

      _prefetchOp = [NSBlockOperation blockOperationWithBlock:^{

	CGImageSourceRef src = create_image_source_from_path(image_path);
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
		NSString *cache_path = cache_path_for_type(lib, file_id, type);
		write_image_to_path(im, cache_path, CACHE_QUALITY);
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

  PDImageLibrary *lib = [self library];
  uint32_t file_id = [self imageId];
  NSString *image_path = [self imagePath];

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

  NSString *type_path = cache_path_for_type(lib, file_id, type);

  BOOL cache_is_valid = file_newer_than(type_path, image_path);

  NSMutableArray *ops = [NSMutableArray array];

  NSOperationQueuePriority next_pri = NSOperationQueuePriorityHigh;

  /* If the proxy (tiny/small/medium) cache hasn't been built yet,
     display the embedded image thumbnail until it's ready. */

  if (thumb && !cache_is_valid)
    {
      NSOperation *thumb_op = [NSBlockOperation blockOperationWithBlock:^{
	CGImageSourceRef src = create_image_source_from_path(image_path);
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
	CGImageSourceRef src = create_image_source_from_path(type_path);
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

  if ([ops count] == 0 || (!thumb && max_size != type_size))
    {
      /* Using 'id' so the block retains it, actually CGColorSpaceRef. */

      id space = [opts objectForKey:PDImageHost_ColorSpace];

      NSOperation *full_op = [NSBlockOperation blockOperationWithBlock:^{
	NSString *src_path = (max_size > type_size || !cache_is_valid
			      ? image_path : type_path);

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
