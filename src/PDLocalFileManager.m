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

#import "PDLocalFileManager.h"

#import <AppKit/AppKit.h>

#import <sys/stat.h>

#define ERROR_DOMAIN @"org.unfactored.PDFileManager"

@implementation PDLocalFileManager
{
  NSString *_path;
  NSFileManager *_manager;
  id<PDFileManagerDelegate> _delegate;
}

@synthesize delegate = _delegate;

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [[path stringByStandardizingPath] copy];
  _manager = [[NSFileManager defaultManager] retain];

  return self;
}

- (id)initWithPropertyListRepresentation:(id)obj
{
  NSString *path = [obj objectForKey:@"PDLocalFileManager.path"];
  if (path != nil)
    {
      path = [path stringByExpandingTildeInPath];
      return [self initWithPath:path];
    }

  [[super init] release];
  return nil;
}

- (id)propertyListRepresentation
{
  NSString *path = [_path stringByAbbreviatingWithTildeInPath];
  return @{@"PDLocalFileManager.path": path};
}

- (BOOL)isEqualToPath:(NSString *)path
{
  return [_path isEqualToString:[path stringByStandardizingPath]];
}

- (BOOL)isEqualToPropertyListRepresentation:(id)obj
{
  NSString *path = [obj objectForKey:@"PDLocalFileManager.path"];

  if (path != nil)
    return [self isEqualToPath:[path stringByExpandingTildeInPath]];
  else
    return NO;
}

- (void)invalidate
{
}

- (void)dealloc
{
  [self invalidate];
  [_path release];
  [_manager release];
  [super dealloc];
}

- (NSString *)name
{
  return [_path lastPathComponent];
}

- (NSString *)localizedDescription
{
  /* This will return file://path or something, which seems ok. */

  return [[NSURL fileURLWithPath:_path] absoluteString];
}

- (NSImage *)iconImage
{
  return [[NSWorkspace sharedWorkspace] iconForFile:_path];
}

- (void)unmount
{
  [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:_path];
}

static NSString *
absolute_path(PDLocalFileManager *self, NSString *path)
{
  return [self->_path stringByAppendingPathComponent:path];
}

- (NSURL *)fileURLWithPath:(NSString *)path
{
  return [NSURL fileURLWithPath:absolute_path(self, path)];
}

- (BOOL)fileExistsAtPath:(NSString *)path
{
  return [_manager fileExistsAtPath:absolute_path(self, path)];
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)dirp
{
  return [_manager fileExistsAtPath:
	  absolute_path(self, path) isDirectory:dirp];
}

- (time_t)mtimeOfFileAtPath:(NSString *)path
{
  struct stat st;
  if (stat([absolute_path(self, path) fileSystemRepresentation], &st) == 0)
    return st.st_mtime;
  else
    return 0;
}

- (size_t)sizeOfFileAtPath:(NSString *)path
{
  struct stat st;
  if (stat([absolute_path(self, path) fileSystemRepresentation], &st) == 0)
    return st.st_size;
  else
    return 0;
}

- (NSData *)contentsOfFileAtPath:(NSString *)path
{
  return [NSData dataWithContentsOfFile:absolute_path(self, path)];
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path
{
  return [_manager contentsOfDirectoryAtPath:
	  absolute_path(self, path) error:nil];
}

- (CGImageSourceRef)copyImageSourceAtPath:(NSString *)path
{
  NSURL *url = [NSURL fileURLWithPath:absolute_path(self, path)];
  return CGImageSourceCreateWithURL((CFURLRef)url, NULL);
}

- (BOOL)writeData:(NSData *)data toFile:(NSString *)path
    options:(NSDataWritingOptions)options error:(NSError **)err
{
  return [data writeToFile:absolute_path(self, path)
	  options:options error:err];
}

- (BOOL)createDirectoryAtPath:(NSString *)path
    withIntermediateDirectories:(BOOL)flag attributes:(NSDictionary *)dict
    error:(NSError **)err
{
  return [_manager createDirectoryAtPath:absolute_path(self, path)
	  withIntermediateDirectories:flag attributes:dict error:err];
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)err
{
  return [_manager copyItemAtPath:absolute_path(self, srcPath)
	  toPath:absolute_path(self, dstPath) error:err];
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)err
{
  return [_manager moveItemAtPath:absolute_path(self, srcPath)
	  toPath:absolute_path(self, dstPath) error:err];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
  return [_manager removeItemAtPath:absolute_path(self, path) error:err];
}

@end
