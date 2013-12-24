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

@protocol PDFileManagerDelegate;

@interface PDFileManager : NSObject

+ (PDFileManager *)fileManagerWithPath:(NSString *)path;
+ (PDFileManager *)fileManagerWithPropertyListRepresentation:(id)obj;

/* May return a non-null plist-compatible object that can be passed
   to fileManagerWithPropertyListRepresentation: to reinstantiate the
   file manager. */

- (id)propertyListRepresentation;

- (BOOL)isEqualToPath:(NSString *)path;
- (BOOL)isEqualToPropertyListRepresentation:(id)obj;

@property(nonatomic, weak) id<PDFileManagerDelegate> delegate;

/* Some kind of default name for the location. E.g. last path component. */

- (NSString *)name;

/* String describing this file manager. Used in error reporting. */

- (NSString *)localizedDescription;

/* An icon representing the referenced location, or nil. */

- (NSImage *)iconImage;

/* Will be called by -dealloc. Can be called at any time once no more
   file operations will be performed. */

- (void)invalidate;

/* Unmount the file system if possible. */

- (void)unmount;

/* Constructs an absolute URL referencing the named file. This operation
   may fail, e.g. when direct file access is not supported. */

- (NSURL *)fileURLWithPath:(NSString *)path;

/* Operations for reading file attributes. */

- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)dirp;
- (time_t)mtimeOfFileAtPath:(NSString *)path;
- (size_t)sizeOfFileAtPath:(NSString *)path;

/* Operations for reading file content. */

- (NSData *)contentsOfFileAtPath:(NSString *)path;
- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path;
- (CGImageSourceRef)copyImageSourceAtPath:(NSString *)path;

/* Operations for writing file content. */

- (BOOL)writeData:(NSData *)data toFile:(NSString *)path
    options:(NSDataWritingOptions)options error:(NSError **)err;
- (BOOL)createDirectoryAtPath:(NSString *)path
    withIntermediateDirectories:(BOOL)flag attributes:(NSDictionary *)dict
    error:(NSError **)err;

/* Operations for moving, copying and deleting files. */

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)err;
- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)err;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err;

@end

@protocol PDFileManagerDelegate <NSObject>
@optional

/* FIXME add methods here. E.g. mount/unmount notifications? */

@end
