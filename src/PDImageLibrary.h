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

#import <Foundation/Foundation.h>

@class PDFileCatalog, PDImage, NSImage;

extern NSString *const PDImageLibraryDirectoryDidChange;

@interface PDImageLibrary : NSObject
{
  NSString *_name;
  NSString *_path;
  NSString *_cachePath;
  uint32_t _libraryId;
  PDFileCatalog *_catalog;
  BOOL _transient;
  NSMutableArray *_activeImports;
}

+ (void)removeInvalidLibraries;

+ (NSArray *)allLibraries;

+ (PDImageLibrary *)libraryWithId:(uint32_t)lid;

/* Creates a new library if no existing library is found. */

+ (PDImageLibrary *)libraryWithPath:(NSString *)path;
+ (PDImageLibrary *)libraryWithPath:(NSString *)path onlyIfExists:(BOOL)flag;

+ (PDImageLibrary *)libraryWithPropertyList:(id)obj;

- (id)propertyList;

- (void)invalidate;

@property(nonatomic, readonly) uint32_t libraryId;

@property(nonatomic, copy) NSString *name;
@property(nonatomic, readonly) NSImage *iconImage;

@property(nonatomic, getter=isTransient) BOOL transient;

@property(nonatomic, readonly) NSString *cachePath;

/* 'rel_path' is relative to the root of the library. */

- (uint32_t)uniqueIdOfFile:(NSString *)rel_path;

- (NSString *)cachePathForFileId:(uint32_t)file_id base:(NSString *)str;

/* Synchronize catalog to disk. */

- (void)synchronize;

/* Blow away all cached data. */

- (void)emptyCaches;

/* Wait for any async image imports to complete. */

- (void)waitForImportsToComplete;

/* Unmount if possible. */

- (void)unmount;

/* Low-level file operations, all paths are relative to the root of the
   library. */

- (NSData *)contentsOfFileAtPath:(NSString *)path;
- (CGImageSourceRef)copyImageSourceWithFile:(NSString *)path;
- (BOOL)writeData:(NSData *)data toFile:(NSString *)path
    error:(NSError **)err;
- (NSArray *)contentsOfDirectory:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)dirp;
- (time_t)mtimeOfFileAtPath:(NSString *)path;
- (size_t)sizeOfFileAtPath:(NSString *)path;

/* More low-level operations. Note these don't automatically invoke the
   -didFoo methods. */

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)error;
- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)error;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err;

/* Constructs an absolute URL referencing the named library file. This
   operation may fail, e.g. for non-file libraries. */

- (NSURL *)fileURLWithPath:(NSString *)path;

/* High-level file primitives. */

- (void)foreachSubdirectoryOfDirectory:(NSString *)dir
    handler:(void (^)(NSString *dir_name))block;
- (void)loadImagesInSubdirectory:(NSString *)dir
    recursively:(BOOL)flag handler:(void (^)(PDImage *))block;

/* Even higher-level operations. These will present any errors direct
   to the UI, and trigger any other updates required (i.e. the ones
   below). */

- (void)copyImages:(NSArray *)images toDirectory:(NSString *)dir;
- (void)moveImages:(NSArray *)images toDirectory:(NSString *)dir;
- (void)renameDirectory:(NSString *)old_dir to:(NSString *)new_dir;

/* Notifications to the library that files under its path have been
   moved externally. */

- (void)didRenameDirectory:(NSString *)oldName to:(NSString *)newName;
- (void)didRenameFile:(NSString *)oldName to:(NSString *)newName;
- (void)didRemoveFileWithRelativePath:(NSString *)rel_path;

- (void)importImages:(NSArray *)images toDirectory:(NSString *)dir
    fileTypes:(NSSet *)types preferredType:(NSString *)type
    filenameMap:(NSString *(^)(PDImage *src, NSString *name))f
    properties:(NSDictionary *)dict deleteSourceImages:(BOOL)flag;

@end
