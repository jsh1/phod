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

@class PDImage;

@interface PDImageLibrary : NSObject
{
  NSString *_name;
  NSString *_path;
  NSString *_cachePath;
  uint32_t _libraryId;
  uint32_t _lastFileId;
  NSMutableDictionary *_catalog;
}

+ (NSArray *)allLibraries;

+ (PDImageLibrary *)libraryWithPath:(NSString *)path;
+ (PDImageLibrary *)libraryWithId:(uint32_t)lid;

- (id)initWithPath:(NSString *)path;

- (id)initWithPropertyList:(id)obj;
- (id)propertyList;

- (void)synchronize;

- (void)remove;

- (void)validateCaches;
- (void)emptyCaches;

@property(nonatomic, copy) NSString *name;

@property(nonatomic, readonly) NSString *path;

@property(nonatomic, readonly) NSString *cachePath;

- (NSString *)cachePathForFileId:(uint32_t)file_id base:(NSString *)str;

@property(nonatomic, readonly) uint32_t libraryId;

- (uint32_t)fileIdOfPath:(NSString *)path;

- (void)loadImagesInSubdirectory:(NSString *)path
    handler:(void (^)(PDImage *))block;

@end
