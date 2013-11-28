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
	      _implicitProperties = PDImageSourceCopyProperties(src);
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
		NSDictionary *dict = PDImageSourceCopyProperties(src);
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
  return PDImageLocalizedNameOfProperty(key);
}

- (NSString *)localizedImagePropertyForKey:(NSString *)key
{
  id value = [self imagePropertyForKey:key];
  if (value == nil)
    return nil;

  return PDImageLocalizedPropertyValue(key, value, self);
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
