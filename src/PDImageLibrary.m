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

#import "PDImageLibrary.h"

#import "PDImage.h"

#import <stdlib.h>

#define CATALOG_FILE "catalog.json"
#define CATALOG_VER_KEY "///version"
#define METADATA_EXTENSION "phod"
#define CACHE_BITS 6
#define CACHE_SEP '$'

@implementation PDImageLibrary

@synthesize path = _path;
@synthesize name = _name;
@synthesize libraryId = _libraryId;

static NSMutableArray *_allLibraries;

static void
add_library(PDImageLibrary *lib)
{
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    _allLibraries = [[NSMutableArray alloc] init];
  });

  [_allLibraries addObject:lib];
}

static NSString *
cache_root(void)
{
  NSArray *paths = (NSSearchPathForDirectoriesInDomains
		    (NSCachesDirectory, NSUserDomainMask, YES));

  return [[[paths lastObject] stringByAppendingPathComponent:
	   [[NSBundle mainBundle] bundleIdentifier]]
	  stringByAppendingPathComponent:@"library"];
}

+ (void)removeInvalidLibraries
{
  /* For now, simply remove any libraries that don't have catalogs. By
     definition they're useless to us. (E.g. transient libraries for
     SD cards that were left around after an app crash.) */

  assert(_allLibraries == nil);

  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir = cache_root();

  for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil])
    {
      NSString *path = [dir stringByAppendingPathComponent:file];

      NSString *catalog_path
        = [path stringByAppendingPathComponent:@CATALOG_FILE];

      if (![fm fileExistsAtPath:catalog_path])
	{
	  NSLog(@"PDImageLibrary: orphan library: %@", file);
	  [fm removeItemAtPath:path error:nil];
	}
    }
}

+ (NSArray *)allLibraries
{
  if (_allLibraries == nil)
    return [NSArray array];
  else
    return _allLibraries;
}

+ (PDImageLibrary *)libraryWithPath:(NSString *)path
{
  if (_allLibraries == nil)
    return nil;

  path = [path stringByStandardizingPath];

  for (PDImageLibrary *lib in _allLibraries)
    {
      if ([[lib path] isEqual:path])
	return lib;
    }

  return nil;
}

+ (PDImageLibrary *)libraryWithId:(uint32_t)lid
{
  if (_allLibraries == nil)
    return nil;

  for (PDImageLibrary *lib in _allLibraries)
    {
      if ([lib libraryId] == lid)
	return lib;
    }

  return nil;
}

- (void)dealloc
{
  [_name release];
  [_path release];
  [_cachePath release];
  [_catalog0 release];
  [_catalog1 release];
  [super dealloc];
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [[path stringByStandardizingPath] copy];
  _name = [[path lastPathComponent] copy];

again:
  _libraryId = arc4random();
  for (PDImageLibrary *lib in _allLibraries)
    {
      if (_libraryId == [lib libraryId])
	goto again;
    }

  _catalog1 = [[NSMutableDictionary alloc] init];
  _catalogDirty = YES;

  add_library(self);

  return self;
}

- (id)initWithPropertyList:(id)obj
{
  self = [super init];
  if (self == nil)
    return nil;

  if (![obj isKindOfClass:[NSDictionary class]])
    {
      [self release];
      return nil;
    }

  _path = [[[obj objectForKey:@"path"] stringByExpandingTildeInPath] copy];
  _name = [[obj objectForKey:@"name"] copy];
  _libraryId = [[obj objectForKey:@"libraryId"] unsignedIntValue];
  _lastFileId = [[obj objectForKey:@"lastFileId"] unsignedIntValue];

  if (_libraryId == 0)
    {
    again:
      _libraryId = arc4random();
      if (_libraryId == 0)
	goto again;
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if (_libraryId == [lib libraryId])
	    goto again;
	}
    }
  else
    {
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if (_libraryId == [lib libraryId])
	    {
	      [self release];
	      return [lib retain];
	    }
	}
    }

  NSString *catalog_path
    = [[self cachePath] stringByAppendingPathComponent:@CATALOG_FILE];

  NSData *data = [[NSData alloc] initWithContentsOfFile:catalog_path];
  if (data != nil)
    {
      id obj = [NSJSONSerialization
		JSONObjectWithData:data options:0 error:nil];

      if ([obj isKindOfClass:[NSDictionary class]])
	_catalog0 = [obj mutableCopy];

      [data release];
    }

  _catalog1 = [[NSMutableDictionary alloc] init];
  _catalogDirty = YES;

  [self validateCaches];

  add_library(self);

  return self;
}

- (id)propertyList
{
  return @{
    @"path": [_path stringByAbbreviatingWithTildeInPath],
    @"name": _name,
    @"libraryId": @(_libraryId),
    @"lastFileId": @(_lastFileId)
  };
}

- (void)synchronize
{
  if (_catalogDirty)
    {
      NSString *path = [[self cachePath]
			stringByAppendingPathComponent:@CATALOG_FILE];

      NSData *data = [NSJSONSerialization
		      dataWithJSONObject:_catalog1 options:0 error:nil];

      if ([data writeToFile:path atomically:YES])
	_catalogDirty = NO;
      else
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (void)remove
{
  [self emptyCaches];

  NSInteger idx = [_allLibraries indexOfObjectIdenticalTo:self];
  if (idx != NSNotFound)
    [_allLibraries removeObjectAtIndex:idx];
}

static unsigned int
convert_hexdigit(int c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  else if (c >= 'A' && c <= 'F')
    return 10 + c - 'A';
  else if (c >= 'a' && c <= 'f')
    return 10 + c - 'a';
  else
    return 0;
}

- (void)validateCaches
{
  /* This runs immediately after loading the catalog and before we pull
     anything out of the cache. It scans the cache directory hierarchy
     for any files that don't exist in the catalog and deletes them.

     This is to handle the case where the app crashed after finding new
     files (adding their results to the cache) but before writing out
     the updated catalog and library state. In this case we'll reuse
     image ids and musn't find data for those ids already in the cache.

     Note that this doesn't immediately remove items from the cache
     that exist in the catalog but not in the library itself. Due to
     how we double-buffer catalog dictionaries to remove unused file
     ids, any missing files will be removed when -validateCaches is
     called the next time the app is launched.

     (Or we could choose a point after all libraries have been scanned
     to release _catalog0 then call -validateCaches.) */

  @autoreleasepool
    {
      NSString *dir = [self cachePath];
      NSFileManager *fm = [NSFileManager defaultManager];

      NSMutableIndexSet *catalog = [NSMutableIndexSet indexSet];

      for (NSString *key in _catalog0)
	[catalog addIndex:[[_catalog0 objectForKey:key] unsignedIntValue]];
      for (NSString *key in _catalog1)
	[catalog addIndex:[[_catalog1 objectForKey:key] unsignedIntValue]];

      unsigned int i;
      for (i = 0; i < (1U << CACHE_BITS); i++)
	{
	  NSString *path = [dir stringByAppendingPathComponent:
			    [NSString stringWithFormat:@"%02x", i]];
	  if (![fm fileExistsAtPath:path])
	    continue;

	  for (NSString *file in [fm contentsOfDirectoryAtPath:path error:nil])
	    {
	      const char *str = [file UTF8String];
	      const char *end = strchr(str, CACHE_SEP);

	      BOOL delete = NO;
	      if (end != NULL)
		{
		  uint32_t fid = 0;
		  for (; str != end; str++)
		    fid = fid * 16 + convert_hexdigit(*str);
		  fid = (fid << CACHE_BITS) | i;
		  if (![catalog containsIndex:fid])
		    delete = YES;
		}
	      else
		delete = YES;

	      if (delete)
		{
		  NSLog(@"PDImageLibrary: orphan cache entry: %02x/%@",
			i, file);
		  [fm removeItemAtPath:
		   [path stringByAppendingPathComponent:file] error:nil];
		}
	    }
	}
    }
}

- (void)emptyCaches
{
  if (_cachePath != nil)
    {
      [[NSFileManager defaultManager] removeItemAtPath:_cachePath error:nil];
      [_cachePath release];
      _cachePath = nil;
    }
}

- (NSString *)cachePath
{
  if (_cachePath == nil)
    {
      _cachePath = [[cache_root() stringByAppendingPathComponent:
		     [NSString stringWithFormat:@"%08x", _libraryId]] copy];

      NSFileManager *fm = [NSFileManager defaultManager];

      if (![fm fileExistsAtPath:_cachePath])
	{
	  [fm createDirectoryAtPath:_cachePath
	   withIntermediateDirectories:YES attributes:nil error:nil];
	}
    }

  return _cachePath;
}

- (NSString *)cachePathForFileId:(uint32_t)file_id base:(NSString *)str
{
  NSString *base = [NSString stringWithFormat:@"%02x/%x%c%@",
		    file_id & ((1U << CACHE_BITS) - 1),
		    file_id >> CACHE_BITS, CACHE_SEP, str];

  return [[self cachePath] stringByAppendingPathComponent:base];
}

- (uint32_t)fileIdOfRelativePath:(NSString *)rel_path
{
  NSNumber *obj = [_catalog1 objectForKey:rel_path];

  if (obj == nil)
    {
      obj = [_catalog0 objectForKey:rel_path];

      /* We place the deserialized dictionary in _catalog0, and the
	 current dictionary in _catalog1. We know that all extant files
	 will have their ids queried at least once when the library is
	 scanned on startup, so by moving entries from the old to new
	 dictionaries we effectively remove stale entries from the
	 current version. */

      if (obj != nil)
	{
	  [_catalog1 setObject:obj forKey:rel_path];
	  [_catalog0 removeObjectForKey:rel_path];
	  _catalogDirty = YES;
	}
    }

  if (obj != nil)
    return [obj unsignedIntValue];

  uint32_t fid = ++_lastFileId;

  [_catalog1 setObject:[NSNumber numberWithUnsignedInt:fid] forKey:rel_path];
  _catalogDirty = YES;

  return fid;
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

static NSSet *
jpeg_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    set = [[NSSet alloc] initWithObjects:@"jpg", @"jpeg", @"jpe", nil];
  });

  return set;
}

static NSSet *
jpeg_and_raw_extensions(void)
{
  static NSSet *set;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    set = [[raw_extensions()
	    setByAddingObjectsFromSet:jpeg_extensions()] copy];
  });

  return set;
}

/* 'ext' must be lowercase. */

static NSString *
filename_with_ext(NSSet *filenames, NSString *stem, NSString *ext)
{
  NSString *lower = [stem stringByAppendingPathExtension:ext];
  if ([filenames containsObject:lower])
    return lower;

  NSString *upper = [stem stringByAppendingPathExtension:
		     [ext uppercaseString]];
  if ([filenames containsObject:upper])
    return upper;

  return nil;
}

static NSString *
filename_with_ext_in_set(NSSet *filenames, NSString *stem, NSSet *exts)
{
  for (NSString *ext in exts)
    {
      NSString *ret = filename_with_ext(filenames, stem, ext);
      if (ret != nil)
	return ret;
    }

  return nil;
}

- (void)loadImagesInSubdirectory:(NSString *)dir
    recursively:(BOOL)flag handler:(void (^)(PDImage *))block
{
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [_path stringByAppendingPathComponent:dir];

  NSArray *files = [fm contentsOfDirectoryAtPath:dir_path error:nil];
  NSMutableSet *unused_files = [[NSMutableSet alloc] initWithArray:files];

  /* Two passes so we can read .phod files first. These may reference
     JPEG / RAW files, and if so we don't want to add those images
     separately. */

  for (int pass = 0; pass < 2; pass++)
    {
      for (NSString *file in files)
	{
	  @autoreleasepool
	    {
	      if ([file characterAtIndex:0] == '.')
		continue;
	      if (![unused_files containsObject:file])
		continue;

	      NSString *path = [dir_path stringByAppendingPathComponent:file];
	      BOOL is_dir = NO;
	      if (![fm fileExistsAtPath:path isDirectory:&is_dir])
		continue;
	      if (is_dir)
		{
		  if (flag && pass == 0)
		    {
		      [self loadImagesInSubdirectory:
		       [dir stringByAppendingPathComponent:file]
		       recursively:YES handler:block];
		    }
		  continue;
		}

	      NSString *ext = [[file pathExtension] lowercaseString];

	      if (pass == 0 && ![ext isEqualToString:@METADATA_EXTENSION])
		continue;
	      if (pass == 1 && ![jpeg_and_raw_extensions() containsObject:ext])
		continue;

	      NSString *stem = [file stringByDeletingPathExtension];

	      NSString *json_file = filename_with_ext(unused_files,
						stem, @METADATA_EXTENSION);
	      NSString *jpeg_file
	        = filename_with_ext_in_set(unused_files, stem,
						jpeg_extensions());
	      NSString *raw_file
	        = filename_with_ext_in_set(unused_files, stem,
						raw_extensions());

	      PDImage *image = [[PDImage alloc] initWithLibrary:self
				directory:dir JSONFile:json_file
				JPEGFile:jpeg_file RAWFile:raw_file];

	      if (image != nil)
		{
		  block(image);

		  json_file = [image JSONFile];
		  if (json_file != nil)
		    [unused_files removeObject:json_file];

		  jpeg_file = [image JPEGFile];
		  if (jpeg_file != nil)
		    [unused_files removeObject:jpeg_file];

		  raw_file = [image RAWFile];
		  if (raw_file != nil)
		    [unused_files removeObject:raw_file];

		  [image release];
		}
	    }
	}
    }

  [unused_files release];
}

@end
