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

#import "PDAppDelegate.h"
#import "PDFileCatalog.h"
#import "PDFileManager.h"
#import "PDImage.h"

#import <AppKit/AppKit.h>

#import <stdlib.h>
#import <sys/stat.h>
#import <utime.h>

#define CATALOG_FILE "catalog.json"
#define CACHE_BITS 6
#define CACHE_SEP '$'

#define METADATA_EXTENSION "phod"

#define ERROR_DOMAIN @"org.unfactored.PDImageLibrary"

NSString *const PDImageLibraryDirectoryDidChange = @"PDImageLibraryDirectoryDidChangeDidChange";

@interface PDImageLibrary ()
- (id)initWithDictionary:(NSDictionary *)dict;
- (BOOL)pathEqualToPath:(NSString *)path;
- (NSString *)cachePath;
- (void)validateCaches;
- (NSOperationQueue *)IOQueue;
- (void)waitForImportsToComplete;
@end

@implementation PDImageLibrary

@synthesize name = _name;
@synthesize libraryId = _libraryId;
@synthesize transient = _transient;

static NSMutableArray *_allLibraries;

static NSString *
cache_root(void)
{
  NSArray *paths = (NSSearchPathForDirectoriesInDomains
		    (NSCachesDirectory, NSUserDomainMask, YES));

  return [[[paths lastObject] stringByAppendingPathComponent:
	   [[NSBundle mainBundle] bundleIdentifier]]
	  stringByAppendingPathComponent:@"library"];
}

static NSString *
catalog_path(PDImageLibrary *self)
{
  return [[self cachePath] stringByAppendingPathComponent:@CATALOG_FILE];
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

+ (PDImageLibrary *)findLibraryWithPath:(NSString *)path
{
  if (_allLibraries == nil)
    return nil;

  for (PDImageLibrary *lib in _allLibraries)
    {
      if ([lib pathEqualToPath:path])
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

+ (PDImageLibrary *)libraryWithPath:(NSString *)path
{
  return [self libraryWithPath:path onlyIfExists:NO];
}

+ (PDImageLibrary *)libraryWithPath:(NSString *)path onlyIfExists:(BOOL)flag
{
  if (_allLibraries != nil)
    {
      for (PDImageLibrary *lib in _allLibraries)
	{
	  if ([lib pathEqualToPath:path])
	    return lib;
	}
    }

  if (flag)
    return nil;

  PDFileManager *manager = [PDFileManager fileManagerWithPath:path];
  if (manager == nil)
    return nil;

  NSDictionary *dict = @{@"fileManager": manager};

  return [[[self alloc] initWithDictionary:dict] autorelease];
}

+ (PDImageLibrary *)libraryWithPropertyListRepresentation:(id)obj
{
  if (![obj isKindOfClass:[NSDictionary class]])
    return nil;

  id manager = [obj objectForKey:@"fileManager"];
  if (manager != nil)
    {
      if (_allLibraries != nil)
	{
	  for (PDImageLibrary *lib in _allLibraries)
	    {
	      if ([lib->_manager isEqualToPropertyListRepresentation:manager])
		return lib;
	    }
	}
    }

  return [[[self alloc] initWithDictionary:obj] autorelease];
}

- (id)initWithDictionary:(NSDictionary *)dict
{
  self = [super init];
  if (self == nil)
    return nil;

  id manager = [dict objectForKey:@"fileManager"];
  if (![manager isKindOfClass:[PDFileManager class]])
    {
      manager = [PDFileManager
		 fileManagerWithPropertyListRepresentation:manager];
      if (![manager isKindOfClass:[PDFileManager class]])
	{
	  [self release];
	  return nil;
	}
    }

  _manager = [manager retain];

  _name = [[dict objectForKey:@"name"] copy];
  if (_name == nil)
    _name = [[_manager name] copy];

  _libraryId = [[dict objectForKey:@"libraryId"] unsignedIntValue];

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

  _catalog = [[PDFileCatalog alloc] initWithContentsOfFile:catalog_path(self)];

  [self validateCaches];

  if (_allLibraries == nil)
    _allLibraries = [[NSMutableArray alloc] init];

  [_allLibraries addObject:self];

  return self;
}

- (id)propertyListRepresentation
{
  id manager = [_manager propertyListRepresentation];
  if (manager == nil)
    return nil;

  return @{
    @"fileManager": manager,
    @"name": _name,
    @"libraryId": @(_libraryId),
  };
}

- (BOOL)pathEqualToPath:(NSString *)path
{
  return [_manager isEqualToPath:path];
}

- (void)invalidate
{
  [self waitForImportsToComplete];

  [_catalog invalidate];
  [_catalog release];
  _catalog = nil;

  [_ioQueue removeObserver:self forKeyPath:@"operationCount"];
  [_ioQueue waitUntilAllOperationsAreFinished];
  [_ioQueue release];
  _ioQueue = nil;

  [_manager invalidate];
  [_manager release];
  _manager = nil;

  [(PDAppDelegate *)[NSApp delegate] removeBackgroundActivity:self];

  NSInteger idx = [_allLibraries indexOfObjectIdenticalTo:self];
  if (idx != NSNotFound)
    [_allLibraries removeObjectAtIndex:idx];
}

- (void)dealloc
{
  [self invalidate];

  [_name release];
  [_manager release];
  [_cachePath release];
  [_catalog release];
  [_ioQueue release];
  [_activeImports release];

  [super dealloc];
}

- (NSImage *)iconImage
{
  return [_manager iconImage];
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

- (uint32_t)uniqueIdOfFile:(NSString *)path
{
  return [_catalog fileIdForPath:path];
}

- (void)synchronize
{
  [_catalog synchronizeWithContentsOfFile:catalog_path(self)];
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

      NSIndexSet *catalogIds = [_catalog allFileIds];

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
		  if (![catalogIds containsIndex:fid])
		    delete = YES;
		}
	      else
		delete = YES;

	      if (delete)
		{
		  NSLog(@"PDImageLibrary: cache orphan: %02x/%@", i, file);
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

      [_catalog release];
      _catalog = [[PDFileCatalog alloc] init];
    }
}

- (void)unmount
{
  [self waitForImportsToComplete];

  [_manager unmount];
}

- (NSURL *)fileURLWithPath:(NSString *)path
{
  return [_manager fileURLWithPath:path];
}

- (void)didRenameDirectory:(NSString *)oldName to:(NSString *)newName
{
  [_catalog renameDirectory:oldName to:newName];
}

- (void)didRenameFile:(NSString *)oldName to:(NSString *)newName
{
  [_catalog renameFile:oldName to:newName];
}

- (void)didRemoveFileWithPath:(NSString *)path
{
  [_catalog removeFileWithPath:path];
}

- (NSOperationQueue *)IOQueue
{
  if (_ioQueue == nil)
    {
      _ioQueue = [[NSOperationQueue alloc] init];
      [_ioQueue setName:@"PDImageLibrary.IOQueue"];
      [_ioQueue setMaxConcurrentOperationCount:1];
      [_ioQueue addObserver:(id)self
       forKeyPath:@"operationCount" options:0 context:NULL];
    }

  return _ioQueue;
}

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)obj
    change:(NSDictionary *)dict context:(void *)ctx
{
  if ([path isEqualToString:@"operationCount"])
    {
      dispatch_async(dispatch_get_main_queue(), ^
	{
	  NSInteger count = [_ioQueue operationCount];
	  PDAppDelegate *delegate = [NSApp delegate];
	  if (count != 0)
	    [delegate addBackgroundActivity:self];
	  else
	    [delegate removeBackgroundActivity:self];
	});
    }
}

- (void)_addImportOperation:(NSOperation *)op
{
  if (_activeImports == nil)
    _activeImports = [[NSMutableArray alloc] init];

  [_activeImports addObject:op];
}

- (void)_reclaimImportBlocks
{
  NSInteger i = 0, count = [_activeImports count];

  while (i < count)
    {
      NSOperation *op = [_activeImports objectAtIndex:i];
      if ([op isFinished])
	{
	  [_activeImports removeObjectAtIndex:i];
	  count--;
	}
      else
	i++;
    }
}

- (void)waitForImportsToComplete
{
  for (NSOperation *op in _activeImports)
    {
      [op waitUntilFinished];
    }

  [_activeImports removeAllObjects];
}

@end


@implementation PDImageLibrary (ImageOperations)

static NSString *
find_unique_path(PDImageLibrary *self, NSString *path)
{
  NSString *ext = [path pathExtension];
  NSString *rest = [path stringByDeletingPathExtension];

  for (int i = 0;; i++)
    {
      NSString *tem;
      if (i == 0)
	tem = path;
      else
	tem = [NSString stringWithFormat:@"%@-%d.%@", rest, i, ext];
      if (![self fileExistsAtPath:tem])
	return tem;
    }

  /* not reached. */
}

/* Paths are relative to each library. */

static BOOL
copy_item_atomically(PDImageLibrary *self, NSString *dst_path,
		     PDImageLibrary *src_lib, NSString *src_path,
		     NSError **err)
{
  /* Put a ".tmp-" in front of the file name to hide it until we move
     it into place. */

  NSString *tmp_path = [[dst_path stringByDeletingLastPathComponent]
    stringByAppendingPathComponent:[@".tmp-" stringByAppendingString:
				    [dst_path lastPathComponent]]];
  if ([self fileExistsAtPath:tmp_path])
    tmp_path = find_unique_path(self, tmp_path);

  NSURL *tmp_url = [self fileURLWithPath:tmp_path];
  NSURL *src_url = [src_lib fileURLWithPath:src_path];

  if (tmp_url != nil && src_url != nil)
    {
      /* Direct file system access is possible. Copy directly from source
	 to dest. */

      if (![[NSFileManager defaultManager]
	    copyItemAtURL:src_url toURL:tmp_url error:err])
	{
	  return NO;
	}

      /* Bump the mtime of the written file, -copyItemAtURL: doesn't,
	 and we need to invalidate anything in the proxy cache that may
	 have the same name. */

      time_t now = time(NULL);
      struct utimbuf times = {.actime = now, .modtime = now};
      utime([[tmp_url path] fileSystemRepresentation], &times);
    }
  else
    {
      /* Can't copy between libraries. Read to data object and write. */

      @autoreleasepool
	{
	  NSData *data = [src_lib contentsOfFileAtPath:src_path];
	  if (data == nil)
	    return NO;

	  if (![self writeData:data toFile:tmp_path options:0 error:err])
	    return NO;
	}
    }

  if (![self moveItemAtPath:tmp_path toPath:dst_path error:err])
    {
      [self removeItemAtPath:dst_path error:nil];
      return NO;
    }

  return YES;
}

- (void)loadImagesInSubdirectory:(NSString *)dir
    recursively:(BOOL)flag handler:(void (^)(PDImage *))block
{
  @autoreleasepool
    {
      /* Build table of file-name-minus-extension -> [extensions...] */

      NSMutableDictionary *groups = [NSMutableDictionary dictionary];

      for (NSString *file in [self contentsOfDirectoryAtPath:dir])
	{
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  NSString *dir_file = [dir stringByAppendingPathComponent:file];
	  BOOL is_dir = NO;
	  if (![self fileExistsAtPath:dir_file isDirectory:&is_dir])
	    continue;
	  if (is_dir)
	    {
	      if (flag)
		{
		  [self loadImagesInSubdirectory:dir_file recursively:YES
		   handler:block];
		}
	      continue;
	    }

	  NSString *stem = [file stringByDeletingPathExtension];
	  NSString *ext = [file pathExtension];

	  NSMutableArray *exts = [groups objectForKey:stem];
	  if (exts != nil)
	    [exts addObject:ext];
	  else
	    {
	      exts = [NSMutableArray arrayWithObject:ext];
	      [groups setObject:exts forKey:stem];
	    }
	}

      /* Scan each group of files to build one image if possible. */

      for (NSString *stem in groups)
	{
	  PDImage *image = nil;
	  NSMutableDictionary *image_types = nil;

	  for (NSString *ext in [groups objectForKey:stem])
	    {
	      CFStringRef type = UTTypeCreatePreferredIdentifierForTag(
						kUTTagClassFilenameExtension,
						(CFStringRef)ext, NULL);
	      if (type == NULL)
		continue;

	      if (UTTypeConformsTo(type, PDTypePhodMetadata))
		{
		  NSString *file = [stem stringByAppendingPathExtension:ext];
		  image = [[PDImage alloc] initWithLibrary:self directory:dir
			   JSONFile:file];
		}
	      else if (UTTypeConformsTo(type, kUTTypeImage))
		{
		  if (image_types == nil)
		    image_types = [NSMutableDictionary dictionary];
		  NSString *file = [stem stringByAppendingPathExtension:ext];
		  [image_types setObject:file forKey:(id)type];
		}

	      CFRelease(type);

	      if (image != nil)
		break;
	    }

	  if (image == nil && [image_types count] != 0)
	    {
	      image = [[PDImage alloc] initWithLibrary:self directory:dir
		       properties:@{PDImage_FileTypes: image_types}];
	    }

	  if (image != nil)
	    {
	      block(image);
	      [image release];
	    }
	}
    }
}

- (void)copyImages:(NSArray *)images toDirectory:(NSString *)dir
{
  NSError *err = nil;

  for (PDImage *image in images)
    {
      if (![image copyToDirectory:dir resetUUID:YES error:&err])
	break;

      /* FIXME: pass UUIDs of changed image(s)? */

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageLibraryDirectoryDidChange
       object:self userInfo:@{@"libraryDirectory": dir}];
    }

  if (err != nil)
    {
      NSAlert *alert = [NSAlert alertWithError:err];
      [alert runModal];
    }
}

- (void)moveImages:(NSArray *)images toDirectory:(NSString *)dir
{
  NSError *err = nil;

  for (PDImage *image in images)
    {
      PDImageLibrary *src_lib = [image library];

      if (src_lib == self)
	{
	  NSString *src_dir = [image libraryDirectory];

	  if ([src_dir isEqualToString:dir])
	    continue;

	  if (![image moveToDirectory:dir error:&err])
	    break;

	  if ([image isDeleted])
	    [image setDeleted:NO];

	  /* FIXME: pass UUIDs of changed image(s)? */

	  [[NSNotificationCenter defaultCenter]
	   postNotificationName:PDImageLibraryDirectoryDidChange
	   object:src_lib userInfo:@{@"libraryDirectory": src_dir}];

	  [[NSNotificationCenter defaultCenter]
	   postNotificationName:PDImageLibraryDirectoryDidChange
	   object:self userInfo:@{@"libraryDirectory": dir}];
	}
      else
	{
	  NSDictionary *file_types
	    = [image imagePropertyForKey:PDImage_FileTypes];
	  NSString *active_type
	    = [image imagePropertyForKey:PDImage_ActiveType];
	  NSSet *all_types = [NSSet setWithArray:[file_types allKeys]];

	  [self importImages:@[image] toDirectory:dir fileTypes:all_types
	   preferredType:active_type filenameMap:NULL properties:nil
	   deleteSourceImages:YES];
	}
    }

  if (err != nil)
    {
      NSAlert *alert = [NSAlert alertWithError:err];
      [alert runModal];
    }
}

- (void)renameDirectory:(NSString *)old_dir to:(NSString *)new_dir
{
  NSError *err = nil;

  BOOL is_dir = NO;
  if (![self fileExistsAtPath:old_dir isDirectory:&is_dir] || !is_dir)
    {
      NSString *str = [NSString stringWithFormat:
		       @"Can't rename directory %@ to %@, the source"
		       " directory doesn't exist.", old_dir, new_dir];
      err = [NSError errorWithDomain:ERROR_DOMAIN code:1
	     userInfo:@{NSLocalizedDescriptionKey: str}];
      goto error;
    }

  if ([self fileExistsAtPath:new_dir])
    {
      NSString *str = [NSString stringWithFormat:
		       @"Can't rename directory %@ to %@, the destination"
		       " name is already in use.", old_dir, new_dir];
      err = [NSError errorWithDomain:ERROR_DOMAIN code:1
	     userInfo:@{NSLocalizedDescriptionKey: str}];
      goto error;
    }

  if ([self moveItemAtPath:old_dir toPath:new_dir error:&err])
    {
      [self didRenameDirectory:old_dir to:new_dir];
      return;
    }

error:
  if (err != nil)
    {
      NSAlert *alert = [NSAlert alertWithError:err];
      [alert runModal];
    }
}

- (void)importImages:(NSArray *)images toDirectory:(NSString *)dir
    fileTypes:(NSSet *)types preferredType:(NSString *)active_type
    filenameMap:(NSString *(^)(PDImage *src, NSString *name))f
    properties:(NSDictionary *)dict deleteSourceImages:(BOOL)delete_sources
{
  if ([images count] == 0)
    return;

  BOOL new_dir = NO;

  /* FIXME: check that dir_path is under our root-directory? */

  BOOL is_dir = NO;
  if (![self fileExistsAtPath:dir isDirectory:&is_dir])
    {
      new_dir = YES;
      if (![self createDirectoryAtPath:dir withIntermediateDirectories:YES
	   attributes:nil error:nil])
	return;
    }
  else if (!is_dir)
    return;

  __block BOOL pending_notification = NO;

  NSDictionary *notification_info = @{@"libraryDirectory": dir};

  /* Called on main thread. */

  void (^post_notification)() = ^
    {
      if (!pending_notification)
	{
	  pending_notification = YES;

	  dispatch_time_t t
	    = dispatch_time(DISPATCH_TIME_NOW, 1LL * NSEC_PER_SEC);

	  dispatch_after(t, dispatch_get_main_queue(), ^
	    {
	      pending_notification = NO;

	      [[NSNotificationCenter defaultCenter]
	       postNotificationName:PDImageLibraryDirectoryDidChange
	       object:self userInfo:notification_info];
	    });
	}
    };

  __block NSError *error = nil;

  void (^set_error)(NSError *err) = ^(NSError *err)
    {
      dispatch_async(dispatch_get_main_queue(), ^
	{
	  [error release];
	  error = [err copy];
	});
    };

  NSMutableSet *all_libraries = [NSMutableSet set];
  [all_libraries addObject:self];
  for (PDImage *src_im in images)
    [all_libraries addObject:[src_im library]];

  NSMutableArray *dest_files = [NSMutableArray array];

  /* Final NSOperation that depends on all copy/write ops. It moves
     work synchronously back to the main thread and cleans up, presents
     any errors etc. */

  NSOperation *final_op = [NSBlockOperation blockOperationWithBlock:^
    {
      dispatch_sync(dispatch_get_main_queue(), ^
	{
	  if (error == nil)
	    {
	      if (delete_sources)
		{
		  for (PDImage *src_im in images)
		    [src_im remove];
		}
	    }
	  else
	    {
	      if (new_dir)
		[self removeItemAtPath:dir error:nil];
	      else
		{
		  for (NSString *file in dest_files)
		    [self removeItemAtPath:file error:nil];
		}

	      post_notification();

	      NSAlert *alert = [NSAlert alertWithError:error];
	      [alert runModal];
	      [error release];
	    }

	  for (PDImageLibrary *lib in all_libraries)
	    [lib _reclaimImportBlocks];
	});
    }];

  NSOperationQueue *io_queue = [self IOQueue];

  for (PDImage *src_im in images)
    {
      NSString *name = [[src_im imageFile] stringByDeletingPathExtension];
      if (f != NULL)
	name = f(src_im, name);
      if (name == nil)
	continue;

      NSDictionary *src_types = [src_im imagePropertyForKey:PDImage_FileTypes];

      NSMutableDictionary *dst_types = [NSMutableDictionary dictionary];
      NSMutableArray *dst_paths = [NSMutableArray array];

      NSOperation *main_op = nil;
      NSMutableArray *all_ops = [NSMutableArray array];

      for (NSString *src_type in src_types)
	{
	  NSString *src_path = nil;

	  for (NSString *req_type in types)
	    {
	      if (UTTypeConformsTo((CFStringRef)src_type,
				   (CFStringRef)req_type))
		{
		  NSString *src_dir = [src_im libraryDirectory];
		  NSString *src_file = [src_types objectForKey:src_type];
		  src_path = [src_dir stringByAppendingPathComponent:src_file];
		  break;
		}
	    }

	  if (src_path != nil)
	    {
	      NSString *dst_file = [name stringByAppendingPathExtension:
				    [src_path pathExtension]];
	      NSString *dst_path = [dir
				    stringByAppendingPathComponent:dst_file];
                             
	      /* FIXME: if file already exists at destination path,
		check if it's the same file and merge the two? */

	      if ([self fileExistsAtPath:dst_path])
		{
		  dst_path = find_unique_path(self, dst_path);
		  dst_file = [dst_path lastPathComponent];
		}

	      [dst_types setObject:dst_file forKey:src_type];
	      [dst_paths addObject:dst_path];

	      PDImageLibrary *src_lib = [src_im library];

	      NSOperation *op = [NSBlockOperation blockOperationWithBlock:^
		{
		  if (error != nil)
		    return;
		  NSError *err = nil;
		  if (copy_item_atomically(self, dst_path,
					   src_lib, src_path, &err))
		    {
		      dispatch_async(dispatch_get_main_queue(), ^
			{
			  [dest_files addObject:dst_path];
			});
		    }
		  else if (err != nil)
		    set_error(err);
		}];

	      [all_ops addObject:op];

	      if (main_op == nil
		  || UTTypeConformsTo((CFStringRef)src_type,
				      (CFStringRef)active_type))
		{
		  main_op = op;
		}
	    }
	}

      if ([dst_types count] != 0)
	{
	  NSMutableDictionary *dst_props = [NSMutableDictionary dictionary];

	  static NSSet *ignored_keys;
	  static dispatch_once_t once;

	  dispatch_once(&once, ^
	    {
	      ignored_keys = [[NSSet alloc] initWithObjects:PDImage_Name,
			      PDImage_FileTypes, PDImage_ActiveType, nil];
	    });

	  NSDictionary *src_props = [src_im explicitProperties];
	  for (NSString *key in src_props)
	    {
	      if (![ignored_keys containsObject:key])
		[dst_props setObject:[src_props objectForKey:key] forKey:key];
	    }

	  if (dict != nil)
	    [dst_props addEntriesFromDictionary:dict];

	  [dst_props setObject:name forKey:PDImage_Name];

	  [dst_props setObject:dst_types forKey:PDImage_FileTypes];

	  NSString *dst_active = active_type;
	  if ([dst_types objectForKey:dst_active] == nil)
	    {
	      for (NSString *key in dst_types)
		{
		  dst_active = key;
		  break;
		}
	    }

	  [dst_props setObject:dst_active forKey:PDImage_ActiveType];

	  NSMutableDictionary *json_dict = [NSMutableDictionary dictionary];

	  [json_dict setObject:dst_props forKey:@"Properties"];

	  NSString *json_path = [dir stringByAppendingPathComponent:
				 [name stringByAppendingPathExtension:
				  @METADATA_EXTENSION]];

	  if ([self fileExistsAtPath:json_path])
	    json_path = find_unique_path(self, json_path);

	  NSOperation *json_op = [NSBlockOperation blockOperationWithBlock:^
	    {
	      if (error != nil)
		return;
	      NSData *data = [NSJSONSerialization dataWithJSONObject:json_dict
			      options:0 error:nil];
	      NSError *err = nil;
	      if ([self writeData:data toFile:json_path
		   options:NSDataWritingAtomic error:&err])
		{
		  dispatch_async(dispatch_get_main_queue(), ^
		    {
		      [dest_files addObject:json_path];
		      post_notification();
		    });
		}
	      else if (err != nil)
		set_error(err);
	    }];

	  for (NSOperation *op in all_ops)
	    {
	      if (op != main_op)
		[op setQueuePriority:NSOperationQueuePriorityLow];
	      [io_queue addOperation:op];
	      [final_op addDependency:op];
	    }

	  [json_op setQueuePriority:NSOperationQueuePriorityHigh];
	  if (main_op != nil)
	    [json_op addDependency:main_op];
	  [io_queue addOperation:json_op];
	  [final_op addDependency:json_op];
	}
    }

  /* Add the sentinel operation to the list of active imports of all
     libraries either a source or destination for the set of files
     being copied. This will prevent them being destroyed or unmounted
     (by us) until the copies have completed asynchronously. */

  for (PDImageLibrary *lib in all_libraries)
    [lib _addImportOperation:final_op];

  [io_queue addOperation:final_op];

  if (new_dir)
    {
      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageLibraryDirectoryDidChange
       object:self userInfo:notification_info];
    }
}

@end


@implementation PDImageLibrary (FileOperations)

- (BOOL)fileExistsAtPath:(NSString *)path
{
  return [_manager fileExistsAtPath:path];
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)dirp
{
  return [_manager fileExistsAtPath:path isDirectory:dirp];
}

- (time_t)mtimeOfFileAtPath:(NSString *)path
{
  return [_manager mtimeOfFileAtPath:path];
}

- (size_t)sizeOfFileAtPath:(NSString *)path
{
  return [_manager sizeOfFileAtPath:path];
}

- (NSData *)contentsOfFileAtPath:(NSString *)path
{
  return [_manager contentsOfFileAtPath:path];
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path
{
  return [_manager contentsOfDirectoryAtPath:path];
}

- (CGImageSourceRef)copyImageSourceAtPath:(NSString *)path
{
  return [_manager copyImageSourceAtPath:path];
}

- (BOOL)writeData:(NSData *)data toFile:(NSString *)path
    options:(NSDataWritingOptions)options error:(NSError **)err
{
  return [_manager writeData:data toFile:path options:options error:err];
}

- (BOOL)createDirectoryAtPath:(NSString *)path
    withIntermediateDirectories:(BOOL)flag attributes:(NSDictionary *)dict
    error:(NSError **)err
{
  return [_manager createDirectoryAtPath:path
	  withIntermediateDirectories:flag attributes:dict error:err];
}

- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst
    error:(NSError **)err
{
  return [_manager copyItemAtPath:src toPath:dst error:err];
}

- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst
    error:(NSError **)err
{
  return [_manager moveItemAtPath:src toPath:dst error:err];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
  return [_manager removeItemAtPath:path error:err];
}

- (void)foreachSubdirectoryOfDirectory:(NSString *)dir
    handler:(void (^)(NSString *dir_name))block
{
  for (NSString *file in [self contentsOfDirectoryAtPath:dir])
    {
      if ([file characterAtIndex:0] == '.')
	continue;

      BOOL is_dir = NO;
      NSString *dir_file = [dir stringByAppendingPathComponent:file];
      if (![self fileExistsAtPath:dir_file isDirectory:&is_dir] || !is_dir)
	continue;

      block(file);
    }
}

@end
