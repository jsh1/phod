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
#import "PDFoundationExtensions.h"
#import "PDImageLibrary.h"
#import "PDImageProperty.h"
#import "PDImageUUID.h"
#import "PDWindowController.h"

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

const CFStringRef PDTypeRAWImage = CFSTR("public.camera-raw-image");
const CFStringRef PDTypePhodMetadata = CFSTR("org.unfactored.phod-metadata");

NSString *const PDImagePropertyDidChange = @"PDImagePropertyDidChange";

NSString * const PDImageHost_Size = @"Size";
NSString * const PDImageHost_Thumbnail = @"Thumbnail";
NSString * const PDImageHost_ColorSpace = @"ColorSpace";
NSString * const PDImageHost_NoPreview = @"NoPreview";

static time_t
file_mtime(NSString *path)
{
  struct stat st;

  if (stat([path fileSystemRepresentation], &st) == 0)
    return st.st_mtime;
  else
    return 0;
}

static CGImageSourceRef
create_image_source_from_path(NSString *path)
{
  NSURL *url = [NSURL fileURLWithPath:path];
  return CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
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

  NSURL *url = [NSURL fileURLWithPath:path];
  CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
    (__bridge CFURLRef)url, kUTTypeJPEG, 1, NULL);

  if (dest != NULL)
    {
      NSDictionary *opts = @{
	(__bridge id)kCGImageDestinationLossyCompressionQuality: @(quality)
      };

      CGImageDestinationAddImage(dest, im, (CFDictionaryRef)opts);
      CGImageDestinationFinalize(dest);
      CFRelease(dest);
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

@implementation PDImage
{
  PDImageLibrary *_library;
  NSString *_libraryDirectory;		/* relative to _libraryRoot */

  NSString *_jsonFile;			/* may be nil */
  BOOL _pendingJSONWrite;

  NSMutableDictionary *_properties;
  NSDictionary *_implicitProperties;	/* from the image file(s) */

  NSMapTable *_imageHosts;

  BOOL _donePrefetch;
  NSOperation *_prefetchOp;

  int _rating;
  BOOL _deleted;
  BOOL _hidden;
  BOOL _removed;
}

@synthesize library = _library;
@synthesize libraryDirectory = _libraryDirectory;
@synthesize removed = _removed;
@synthesize date = _date;
@synthesize UUID = _uuid;

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
	NSInteger count = (_wideQueue.operationCount
			   + _narrowQueue.operationCount);
	PDAppDelegate *delegate = (id)[NSApp delegate];
	if (count != 0)
	  [delegate addBackgroundActivity:self];
	else
	  [delegate removeBackgroundActivity:self];
      });
    }
}

static NSString *
library_file_path(PDImage *self, NSString *file)
{
  return [self->_libraryDirectory stringByAppendingPathComponent:file];
}

static NSString *
metadata_file(NSString *image_file)
{
  return [[image_file stringByDeletingPathExtension]
	  stringByAppendingPathExtension:@METADATA_EXTENSION];
}

static NSString *
file_type_conforming_to(NSDictionary *file_types, CFStringRef type)
{
  for (NSString *key in file_types)
    {
      if (UTTypeConformsTo((__bridge CFStringRef)key, type))
	return key;
    }

  return nil;
}

static NSString *
file_conforming_to(NSDictionary *file_types, CFStringRef type)
{
  for (NSString *key in file_types)
    {
      if (UTTypeConformsTo((__bridge CFStringRef)key, type))
	return file_types[key];
    }

  return nil;
}

/* Originally I did the usual thing and deferred all I/O until it's
   actually needed to implement a method. But that tends to lead to
   non-deterministic blocking later. It's better to do all I/O up front
   assuming that whatever's loading the image library will do so
   ahead-of-time / asynchronously. */

- (id)_finishInit
{
  /* This function must ensure that FileTypes and ActiveType properties
     are initialized, to avoid infinite recursion in -imageFileId, etc. */

  NSDictionary *file_types = _properties[PDImage_FileTypes];
  NSString *active_type = _properties[PDImage_ActiveType];

  if (file_types.count == 0)
    return nil;

  if (active_type == nil || file_types[active_type] == nil)
    {
      active_type = file_type_conforming_to(file_types, kUTTypeImage);
      if (active_type != nil)
	_properties[PDImage_ActiveType] = active_type;
      else
	return nil;
    }

  NSString *uuid_str = _properties[PDImage_UUID];
  if (uuid_str != nil)
    _uuid = [[NSUUID alloc] initWithUUIDString:uuid_str];

  _deleted = [_properties[PDImage_Deleted] boolValue];
  _hidden = [_properties[PDImage_Hidden] boolValue];
  _rating = [_properties[PDImage_Rating] intValue];

  if ([_properties[PDImage_Name] length] == 0)
    {
      NSString *name = nil;
      for (NSString *key in file_types)
	{
	  name = [file_types[key] stringByDeletingPathExtension];
	  break;
	}
      if (name.length != 0)
	_properties[PDImage_Name] = name;
    }

  [self loadImageProperties];

  _imageHosts = [NSMapTable strongToStrongObjectsMapTable];

  return self;
}

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
    JSONFile:(NSString *)json_file
{
  self = [super init];
  if (self == nil)
    return nil;

  _library = lib;
  _libraryDirectory = [dir copy];

  _jsonFile = [json_file copy];

  _properties = [[NSMutableDictionary alloc] init];

  @autoreleasepool
    {
      NSData *data = [_library contentsOfFileAtPath:
		      library_file_path(self, _jsonFile)];
      if (data != nil)
	{
	  NSDictionary *dict = [NSJSONSerialization
				JSONObjectWithData:data options:0 error:nil];
	  if (dict != nil)
	    {
	      NSDictionary *props = dict[@"Properties"];
	      if (props != nil)
		[_properties addEntriesFromDictionary:props];
	    }
	}
    }

  return [self _finishInit];
}

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
    properties:(NSDictionary *)dict
{
  self = [super init];
  if (self == nil)
    return nil;

  _library = lib;
  _libraryDirectory = [dir copy];

  _properties = [[NSMutableDictionary alloc] init];

  if (dict != nil)
    [_properties addEntriesFromDictionary:dict];

  return [self _finishInit];
}

- (void)dealloc
{
  [_prefetchOp cancel];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"@<PDImage %p: %@>", self, self.name];
}

- (void)writeJSONFile
{
  if (!_removed && !_pendingJSONWrite)
    {
      dispatch_time_t then
        = dispatch_time(DISPATCH_TIME_NOW, 2LL * NSEC_PER_SEC);

      dispatch_after(then, dispatch_get_main_queue(), ^{
	if (!_removed)
	  {
	    if (_jsonFile == nil)
	      _jsonFile = [metadata_file(self.imageFile) copy];

	    /* Copying mutable data out of self, as op runs asynchronously.

	       FIXME: what else should be added to this dictionary? */

	    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

	    /* We're writing the file, it may as well have a UUID.. */

	    if (_uuid == nil)
	      {
		_uuid = [[NSUUID alloc] init];
		[_properties setObject:_uuid.UUIDString forKey:PDImage_UUID];
	      }

	    dict[@"Properties"] =
	      [NSDictionary dictionaryWithDictionary:_properties];

	    NSString *rel_path = library_file_path(self, _jsonFile);

	    NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
	      NSData *data = [NSJSONSerialization dataWithJSONObject:dict
			      options:0 error:nil];
	      [_library writeData:data toFile:rel_path
	       options:NSDataWritingAtomic error:nil];
	    }];

	    [[PDImage writeQueue] addOperation:op];
	  }

	_pendingJSONWrite = NO;
      });

      _pendingJSONWrite = YES;
    }
}

- (NSString *)imageFile
{
  NSDictionary *file_types = self[PDImage_FileTypes];
  NSString *active_type = self[PDImage_ActiveType];

  return file_conforming_to(file_types, (__bridge CFStringRef)active_type);
}

- (NSString *)imageLibraryPath
{
  return library_file_path(self, self.imageFile);
}

- (uint32_t)imageFileId
{
  return [_library uniqueIdOfFile:self.imageLibraryPath];
}

- (id)imagePropertyForKey:(NSString *)key
{
  id value = _properties[key];

  if (value == nil)
    {
      if (_implicitProperties == nil)
	[self loadImageProperties];

      value = _implicitProperties[key];
    }

  if (value == nil)
    {
      /* A few specially coded properties. */

      if ([key isEqualToString:PDImage_Date])
	{
	  value = @([self.date timeIntervalSince1970]);
	}
      else if ([key isEqualToString:PDImage_FileName])
	{
	  value = self.imageFile;
	}
      else if ([key isEqualToString:PDImage_FilePath])
	{
	  value = [_library fileURLWithPath:self.imageLibraryPath];
	}
      else if ([key isEqualToString:PDImage_FileDate])
	{
	  value = @([_library mtimeOfFileAtPath:self.imageLibraryPath]);
	}
      else if ([key isEqualToString:PDImage_FileSize])
	{
	  value = @([_library sizeOfFileAtPath:self.imageLibraryPath]);
	}
      else if ([key isEqualToString:PDImage_Rejected])
	{
	  value = self[PDImage_Rating];
	  if (value != nil)
	    value = @([value intValue] < 0);
	}
    }

  if ([value isKindOfClass:[NSNull class]])
    value = nil;

  return value;
}

- (void)setImageProperty:(id)value forKey:(NSString *)key
{
  if (value == nil)
    value = [NSNull null];

  id oldValue = _properties[key];

  if (![oldValue isEqual:value])
    {
      _properties[key] = value;

      [self writeJSONFile];

      if ([key isEqualToString:PDImage_Deleted])
	_deleted = [value boolValue];
      else if ([key isEqualToString:PDImage_Hidden])
	_hidden = [value boolValue];
      else if ([key isEqualToString:PDImage_Rating])
	_rating = [value intValue];
      else if (([key isEqualToString:PDImage_OriginalDate]
	      || [key isEqualToString:PDImage_DigitizedDate]))
	_date = nil;
      else if ([key isEqualToString:PDImage_ActiveType]
	       || [key isEqualToString:PDImage_FileTypes])
	{
	  _implicitProperties = nil;

	  if (_donePrefetch)
	    {
	      [self stopPrefetching];
	      _prefetchOp = nil;
	      _donePrefetch = NO;
	    }
	}
      else if ([key isEqualToString:PDImage_UUID])
	{
	  _uuid = nil;
	  if (value != nil)
	    _uuid = [[NSUUID alloc] initWithUUIDString:value];
	}

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImagePropertyDidChange object:self
       userInfo:[NSDictionary dictionaryWithObject:key forKey:@"key"]];
    }
}

- (id)objectForKeyedSubscript:(NSString *)key
{
  return [self imagePropertyForKey:key];
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key
{
  [self setImageProperty:obj forKey:key];
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
  id value = self[key];
  if (value == nil)
    return nil;

  return PDImageLocalizedPropertyValue(key, value, self);
}

- (void)setLocalizedImageProperty:(NSString *)str forKey:(NSString *)key
{
  id value = PDImageUnlocalizedPropertyValue(key, str, self);
  if (value == nil)
    return;

  self[key] = value;
}

- (id)expressionValues
{
  return PDImageExpressionValues(self);
}

- (NSDictionary *)explicitProperties
{
  return _properties;
}

+ (void)callWithImageComparator:(PDImageCompareKey)sort_key
    reversed:(BOOL)sort_flag block:(void (^)(NSComparator))block
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
	  NSString *key = nil;
	  switch (sort_key)
	    {
	    case PDImageCompare_FileName: {
	      NSString *s1 = [obj1 imageFile];
	      NSString *s2 = [obj2 imageFile];
	      ret = [s1 compare:s2];
	      goto got_ret; }

	    case PDImageCompare_FileDate: {
	      time_t t1 = [[obj1 library]
			   mtimeOfFileAtPath:[obj1 imageLibraryPath]];
	      time_t t2 = [[obj2 library]
			   mtimeOfFileAtPath:[obj2 imageLibraryPath]];
	      ret = (t1 < t2 ? NSOrderedAscending
		     : t1 > t2 ? NSOrderedDescending : NSOrderedSame);
	      goto got_ret; }

	    case PDImageCompare_FileSize: {
	      size_t s1 = [[obj1 library]
			   sizeOfFileAtPath:[obj1 imageLibraryPath]];
	      size_t s2 = [[obj2 library]
			   sizeOfFileAtPath:[obj2 imageLibraryPath]];
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
		obj1 = @(size1.width * size1.height);
	      if (size2.width != 0 && size2.height != 0)
		obj2 = @(size2.width * size2.height);
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
	      obj1 = obj1[key];
	      obj2 = obj2[key];
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
      return sort_flag ? -ret : ret;
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
      id value = self[PDImage_OriginalDate];
      if (value == nil)
	value = self[PDImage_DigitizedDate];
      time_t t = (value != nil
		  ? [value unsignedLongValue]
		  : [_library mtimeOfFileAtPath:self.imageLibraryPath]);
      _date = [[NSDate alloc] initWithTimeIntervalSince1970:t];
    }

  return _date;
}

- (NSUUID *)UUID
{
  if (_uuid == nil)
    {
      _uuid = [[NSUUID alloc] init];
      _properties[PDImage_UUID] = [_uuid UUIDString];
      [self writeJSONFile];
    }

  return _uuid;
}

- (NSUUID *)UUIDIfDefined
{
  return _uuid;
}

- (NSString *)name
{
  return self[PDImage_Name];
}

- (void)setName:(NSString *)str
{
  self[PDImage_Name] = str;
}

- (NSString *)title
{
  return self[PDImage_Title];
}

- (void)setTitle:(NSString *)str
{
  self[PDImage_Title] = str;
}

- (NSString *)caption
{
  return self[PDImage_Caption];
}

- (void)setCaption:(NSString *)str
{
  self[PDImage_Caption] = str;
}

- (BOOL)isHidden
{
  return _hidden;
}

- (void)setHidden:(BOOL)flag
{
  self[PDImage_Hidden] = @(flag);
}

- (BOOL)isDeleted
{
  return _deleted;
}

- (void)setDeleted:(BOOL)flag
{
  self[PDImage_Deleted] = @(flag);
}

- (BOOL)isFlagged
{
  return [self[PDImage_Flagged] boolValue];
}

- (void)setFlagged:(BOOL)flag
{
  self[PDImage_Flagged] = @(flag);
}

- (int)rating
{
  return _rating;
}

- (void)setRating:(int)x
{
  self[PDImage_Rating] = @(x);
}

- (BOOL)usesRAW
{
  NSString *active_type = self[PDImage_ActiveType];
  
  return UTTypeConformsTo((__bridge CFStringRef)active_type, PDTypeRAWImage);
}

- (void)setUsesRAW:(BOOL)flag
{
  NSDictionary *file_types = self[PDImage_FileTypes];

  for (NSString *type in file_types)
    {
      bool raw_type = UTTypeConformsTo((__bridge CFStringRef)type,
				       PDTypeRAWImage);
      if ((bool)flag == raw_type)
	{
	  self[PDImage_ActiveType] = type;
	  break;
	}
    }
}

- (BOOL)supportsUsesRAW:(BOOL)flag
{
  NSDictionary *file_types = self[PDImage_FileTypes];

  for (NSString *type in file_types)
    {
      bool raw_type = UTTypeConformsTo((__bridge CFStringRef)type,
				       PDTypeRAWImage);
      if ((bool)flag == raw_type)
	return YES;
    }

  return NO;
}

- (CGSize)pixelSize
{
  CGFloat pw = [self[PDImage_PixelWidth] doubleValue];
  CGFloat ph = [self[PDImage_PixelHeight] doubleValue];

  return CGSizeMake(pw, ph);
}

- (unsigned int)orientation
{
  return [self[PDImage_Orientation] unsignedIntValue];
}

- (void)setOrientation:(unsigned int)x
{
  self[PDImage_Orientation] = @(x);
}

- (CGSize)orientedPixelSize
{
  CGSize pixelSize = self.pixelSize;
  unsigned int orientation = self.orientation;

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
    = [_library cachePathForFileId:self.imageFileId base:@"p.json"];

  NSString *image_rel_path = self.imageLibraryPath;

  if (file_mtime(cache_path) > [_library mtimeOfFileAtPath:image_rel_path])
    {
      NSData *data = [[NSData alloc] initWithContentsOfFile:cache_path];
      if (data != nil)
	{
	  id obj = [NSJSONSerialization
		    JSONObjectWithData:data options:0 error:nil];
	  if (obj != nil)
	    _implicitProperties = [obj copy];
	}
    }

  if (_implicitProperties == nil)
    {
      CGImageSourceRef src = [_library copyImageSourceAtPath:image_rel_path];

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

- (BOOL)removeFiles:(NSError **)err
{
  /* In case JSON file is being written. */

  [[PDImage writeQueue] waitUntilAllOperationsAreFinished];

  NSDictionary *file_types = self[PDImage_FileTypes];
  for (NSString *type in file_types)
    {
      NSString *file = file_types[type];
      NSString *rel_path = library_file_path(self, file);

      if (![_library removeItemAtPath:rel_path error:err])
	return NO;

      [_library didRemoveFileWithPath:rel_path];
    }

  if (_jsonFile != nil)
    {
      NSString *rel_path = library_file_path(self, _jsonFile);
      if (![_library removeItemAtPath:rel_path error:err])
	return NO;

      _jsonFile = nil;
    }

  _properties[PDImage_FileTypes] = @{};
  [_properties removeObjectForKey:PDImage_ActiveType];

  _removed = YES;

  return YES;
}

static NSString *
find_unique_path(PDImageLibrary *lib, NSString *path)
{
  if (path == nil)
    return nil;

  if (![lib fileExistsAtPath:path])
    return path;

  NSString *ext = [path pathExtension];
  NSString *rest = [path stringByDeletingPathExtension];

  for (int i = 1;; i++)
    {
      NSString *tem = [NSString stringWithFormat:@"%@-%d.%@", rest, i, ext];
      if (![lib fileExistsAtPath:tem])
	return tem;
    }

  /* not reached. */
}

/* Used when moving/copying files. */

- (BOOL)writeJSONToLibraryPath:(NSString *)path UUID:(NSUUID *)uuid
    error:(NSError **)err
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  NSMutableDictionary *props
    = [NSMutableDictionary dictionaryWithDictionary:_properties];

  [props setObject:uuid.UUIDString forKey:PDImage_UUID];

  dict[@"Properties"] = props;

  NSData *data = [NSJSONSerialization dataWithJSONObject:dict
		  options:0 error:nil];

  return [_library writeData:data toFile:path
	  options:NSDataWritingAtomic error:err];
}

- (BOOL)moveToDirectory:(NSString *)dir error:(NSError **)err
{
  /* In case JSON file is being written. */

  [[PDImage writeQueue] waitUntilAllOperationsAreFinished];

  NSString *old_json_path = nil, *new_json_path = nil;

  NSDictionary *file_types = self[PDImage_FileTypes];

  NSMutableDictionary *old_paths = [NSMutableDictionary dictionary];
  NSMutableDictionary *new_paths = [NSMutableDictionary dictionary];
  NSMutableArray *moved = [NSMutableArray array];

  if (_jsonFile != nil)
    old_json_path = library_file_path(self, _jsonFile);

  for (NSString *type in file_types)
    {
      NSString *file = file_types[type];
      NSString *path = library_file_path(self, file);
      old_paths[type] = path;
    }

  NSString *old_dir = _libraryDirectory;
  _libraryDirectory = [dir copy];

  if (_jsonFile != nil)
    new_json_path = library_file_path(self, _jsonFile);
  else
    new_json_path = library_file_path(self, metadata_file(self.imageFile));

  new_json_path = find_unique_path(_library, new_json_path);

  for (NSString *type in file_types)
    {
      NSString *file = file_types[type];
      NSString *path
	= find_unique_path(_library, library_file_path(self, file));
      new_paths[type] = path;
    }

  NSUUID *uuid = _uuid ? _uuid : [NSUUID UUID];

  BOOL success = YES;
  BOOL wrote_json = NO;

  /* Write new JSON file first.. */

  if ([self writeJSONToLibraryPath:new_json_path UUID:uuid error:err])
    wrote_json = YES;
  else
    success = NO;

  /* ..then move image files.. */

  for (NSString *type in file_types)
    {
      NSString *old_path = old_paths[type];
      NSString *new_path = new_paths[type];

      if (success && [_library fileExistsAtPath:old_path])
	{
	  if ([_library moveItemAtPath:old_path toPath:new_path error:err])
	    [moved addObject:type];
	  else
	    success = NO;
	}
    }

  /* ..then remove old JSON file. */

  if (success && _jsonFile != nil
      && [_library fileExistsAtPath:old_json_path])
    {
      if (![_library removeItemAtPath:old_json_path error:err])
	success = NO;
    }

  /* Attempt to recover if an error occurred. */

  if (!success)
    {
      for (NSString *type in moved)
	{
	  NSString *old_path = old_paths[type];
	  NSString *new_path = new_paths[type];
	  
	  [_library moveItemAtPath:new_path toPath:old_path error:nil];
	}

      if (wrote_json)
	[_library removeItemAtPath:new_json_path error:nil];

      _libraryDirectory = old_dir;
      return NO;
    }

  /* Success: update image instance and its library. */

  if (uuid != _uuid)
    {
      _uuid = [uuid copy];
      _properties[PDImage_UUID] = [_uuid UUIDString];
    }

  for (NSString *type in file_types)
    {
      NSString *old_path = old_paths[type];
      NSString *new_path = new_paths[type];
      
      [_library didRenameFile:old_path to:new_path];
    }

  /* (JSON file is not in library catalog.) */

  return YES;
}

- (BOOL)copyToDirectory:(NSString *)path resetUUID:(BOOL)flag
   error:(NSError **)err
{
  /* In case JSON file is being written. */

  [[PDImage writeQueue] waitUntilAllOperationsAreFinished];

  NSString *json_path = nil;

  NSDictionary *file_types = self[PDImage_FileTypes];

  NSMutableDictionary *old_paths = [NSMutableDictionary dictionary];
  NSMutableDictionary *new_paths = [NSMutableDictionary dictionary];
  NSMutableArray *copied = [NSMutableArray array];

  for (NSString *type in file_types)
    {
      NSString *file = file_types[type];
      NSString *path = library_file_path(self, file);
      old_paths[type] = path;
    }

  if (_jsonFile != nil)
    json_path = [path stringByAppendingPathComponent:_jsonFile];
  else
    json_path = library_file_path(self, metadata_file(self.imageFile));

  json_path = find_unique_path(_library, json_path);

  for (NSString *type in file_types)
    {
      NSString *file = file_types[type];
      NSString *path
	= find_unique_path(_library, library_file_path(self, file));
      new_paths[type] = path;
    }

  NSUUID *uuid = _uuid;
  if (uuid == nil || flag)
    uuid = [NSUUID UUID];

  BOOL success = YES;

  /* Write new JSON file first.. */

  if (![self writeJSONToLibraryPath:json_path UUID:uuid error:err])
    {
      success = NO;
    }

  /* ..then copy image files. */

  for (NSString *type in file_types)
    {
      NSString *old_path = old_paths[type];
      NSString *new_path = new_paths[type];

      if (success && [_library fileExistsAtPath:old_path])
	{
	  if ([_library copyItemAtPath:old_path toPath:new_path error:err])
	    [copied addObject:type];
	  else
	    success = NO;
	}
    }

  /* Be atomic if failed. */

  if (!success)
    {
      for (NSString *type in copied)
	{
	  NSString *new_path = new_paths[type];
	  [_library removeItemAtPath:new_path error:nil];
	}

      return NO;
    }

  return YES;
}

- (void)startPrefetching
{
  if (_prefetchOp == nil && !_donePrefetch)
    {
      /* Prevent the block retaining self. */

      PDImageLibrary *lib = self.library;
      uint32_t file_id = self.imageFileId;
      NSString *image_rel_path = self.imageLibraryPath;
      NSString *tiny_path = cache_path_for_type(lib, file_id, PDImage_Tiny);

      if (file_mtime(tiny_path) > [lib mtimeOfFileAtPath:image_rel_path])
	{
	  _donePrefetch = YES;
	  return;
	}

      _prefetchOp = [NSBlockOperation blockOperationWithBlock:^
	{
	  if (_prefetchOp == nil) // cancelled?
	    return;

	  CGImageSourceRef src = [lib copyImageSourceAtPath:image_rel_path];
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

	      CGImageRef im
	        = copy_scaled_image(src_im, CGSizeMake(dw, dh), srgb);

	      if (im != NULL)
		{
		  NSString *cache_path
		    = cache_path_for_type(lib, file_id, type);
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

      _prefetchOp.queuePriority = NSOperationQueuePriorityLow;
      [[PDImage narrowQueue] addOperation:_prefetchOp];
    }
}

- (void)stopPrefetching
{
  if (_prefetchOp != nil
      && !(_prefetchOp.executing || _prefetchOp.finished)
      && _prefetchOp.dependencies.count == 0)
    {
      [_prefetchOp cancel];
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

  dispatch_async(queue, ^
    {
      [obj image:self setHostedImage:im];
      CGImageRelease(im);
      [CATransaction flush];
    });
}

- (void)addImageHost:(id<PDImageHost>)obj
{
  assert([_imageHosts objectForKey:obj] == nil);

  PDImageLibrary *lib = self.library;
  uint32_t file_id = self.imageFileId;
  NSString *image_rel_path = self.imageLibraryPath;

  CGSize imageSize = self.pixelSize;
  if (imageSize.width == 0 || imageSize.height == 0)
    return;

  NSDictionary *opts = [obj imageHostOptions];

  BOOL thumb = [opts[PDImageHost_Thumbnail] boolValue];

  /* Using 'id' so blocks retain it, actually CGColorSpaceRef. */

  id space = opts[PDImageHost_ColorSpace];

  BOOL no_preview = [opts[PDImageHost_NoPreview] boolValue];

  CGSize size = [opts[PDImageHost_Size] sizeValue];

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

  BOOL cache_is_valid = (file_mtime(type_path)
			 > [lib mtimeOfFileAtPath:image_rel_path]);

  NSMutableArray *ops = [NSMutableArray array];

  NSOperationQueuePriority next_pri = NSOperationQueuePriorityHigh;

  /* If the proxy (tiny/small/medium) cache hasn't been built yet,
     display the embedded image thumbnail until it's ready. */

  if (thumb && !cache_is_valid)
    {
      NSBlockOperation *thumb_op = [[NSBlockOperation alloc] init];
      __weak NSOperation *thumb_ref = thumb_op;

      [thumb_op addExecutionBlock:^
	{
	  if (thumb_ref.cancelled)
	    return;

	  CGImageSourceRef src = [lib copyImageSourceAtPath:image_rel_path];
	  if (src != NULL)
	    {
	      CGImageRef im = create_cropped_thumbnail_image(src);
	      CFRelease(src);
	      if (im != NULL)
		setHostedImage(self, obj, im);
	    }
	}];

      thumb_op.queuePriority = next_pri;
      next_pri = NSOperationQueuePriorityNormal;
      [ops addObject:thumb_op];
    }

  /* Then access the cached proxy that's larger than the requested size.

     FIXME: the prefetch op may be backed up behind a million other
     prefetch operations. Raising its priority at this point seems to
     have no effect. So just skip this stage if prefetch op has not
     completed yet..

     FIXME: but for thumbnails I'm running into a problem with updating
     CALayer contents from multiple threads.

     What's supposed to happen is CA's prepare_commit() does the
     expensive image conversion before taking the transaction lock,
     allowing other threads to continue unimpeded. But it appears that
     sometimes the conversion is happening in commit_layer(), while the
     lock is held. This is probably because the same layer tree is
     being modified from multiple threads, even though each layer isn't
     and the commits are interfering (I thought we'd made the contents
     property fully isolated in 10.9, but perhaps not..?)

     So the workaround for that is to skip this stage and go straight
     to the scaled proxy for thumbnail layers, so that the image has
     been decompressed and color matched by the time the layer sees it.
     But only if the prefetching has already completed -- we don't ever
     want to scale the full-size image down to thumbnail size. This will
     also look better than e.g. GL_LINEAR_MIPMAP_LINEAR. */

  bool need_scaled_op = true;

  if (thumb ? !cache_is_valid : (cache_is_valid && !no_preview))
    {
      NSBlockOperation *cache_op = [[NSBlockOperation alloc] init];
      __weak NSOperation *cache_ref = cache_op;

      [cache_op addExecutionBlock:^
	{
	  if (cache_ref.cancelled)
	    return;

	  CGImageSourceRef src = create_image_source_from_path(type_path);
	  if (src != NULL)
	    {
	      CGImageRef src_im
		= CGImageSourceCreateImageAtIndex(src, 0, NULL);

	      CFRelease(src);

	      CGImageRef dst_im = src_im;

	      if (thumb && src_im != NULL)
		{
		  dst_im = copy_scaled_image(src_im, size,
		    (__bridge CGColorSpaceRef)space);
		  CGImageRelease(src_im);
		}

	      if (dst_im != NULL)
		setHostedImage(self, obj, dst_im);
	    }
	}];

      /* Cached operation can't run until proxy cache is fully built for
	 this image. */

      [self startPrefetching];
      cache_op.queuePriority = next_pri;

      if (_prefetchOp)
	[cache_op addDependency:_prefetchOp];

      [ops addObject:cache_op];

      if (thumb || max_size == type_size)
	need_scaled_op = false;
    }

  /* Finally, if necessary, downsample from the proxy or the full
     image. I'm choosing to create yet another CGImageRef for the proxy
     if that's the one being used, rather than trying to reuse the one
     loaded above, ImageIO will probably cache it.

     FIXME: we should be tiling large images here. */

  if (need_scaled_op)
    {
      NSBlockOperation *full_op = [[NSBlockOperation alloc] init];
      NSOperation *full_ref = full_op;

      [full_op addExecutionBlock:^
	{
	  if (full_ref.cancelled)
	    return;

	  CGImageSourceRef src;
	  if (max_size > type_size || !cache_is_valid)
	    src = [lib copyImageSourceAtPath:image_rel_path];
	  else
	    src = create_image_source_from_path(type_path);

	  if (src != NULL)
	    {
	      CGImageRef src_im
	        = CGImageSourceCreateImageAtIndex(src, 0, NULL);
	      CFRelease(src);

	      /* Scale the image to required size, this has several
		 side-effects: (1) everything looks as good as
		 possible, (2) uses as little memory as possible, (3)
		 stops CA needing to decompress and color-match the
		 image before displaying it. */

	      CGImageRef dst_im = copy_scaled_image(src_im, size,
		(__bridge CGColorSpaceRef)space);

	      if (dst_im != NULL)
		CGImageRelease(src_im);
	      else
		dst_im = src_im;

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

// NSPasteboardWriting methods

- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pboard
{
  NSMutableArray *types = [NSMutableArray array];

  [types addObject:PDImageUUIDType];

  /* NSURL provides more than one type, currently "public.file-url" and
    "public.utf8-plain-text". */

  NSURL *image_url = [_library fileURLWithPath:self.imageLibraryPath];
  if (image_url != nil)
    {
      for (NSString *type in [image_url writableTypesForPasteboard:pboard])
	[types addObject:type];
    }

  for (NSString *type in self[PDImage_FileTypes])
    [types addObject:type];

  return types;
}

- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type
    pasteboard:(NSPasteboard *)pboard
{
  /* Only provide image data when asked for it, it's usually large. */

  if (self[PDImage_FileTypes][type] != nil)
    return NSPasteboardWritingPromised;
  else
    return 0;
}

- (id)pasteboardPropertyListForType:(NSString *)type
{
  if ([type isEqualToString:PDImageUUIDType])
    {
      return [[PDImageUUID imageUUIDWithUUID:self.UUID]
	      pasteboardPropertyListForType:type];
    }

  NSDictionary *file_types = self[PDImage_FileTypes];
  for (NSString *key in file_types)
    {
      if (UTTypeConformsTo((__bridge CFStringRef)key,
			   (__bridge CFStringRef)type))
	{
	  NSString *file = file_types[key];
	  return [_library contentsOfFileAtPath:
		  [_libraryDirectory stringByAppendingPathComponent:file]];
	}
    }

  NSURL *image_url = [_library fileURLWithPath:self.imageLibraryPath];
  if (image_url != nil)
    {
      id url_data = [image_url pasteboardPropertyListForType:type];
      if (url_data != nil)
	return url_data;
    }

  return nil;
}

@end
