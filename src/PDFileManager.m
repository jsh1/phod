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

#import "PDFileManager.h"

#import "PDLocalFileManager.h"

#define ERROR_DOMAIN @"org.unfactored.PDFileManager"

@implementation PDFileManager

+ (PDFileManager *)fileManagerWithPath:(NSString *)path
{
  return [[PDLocalFileManager alloc] initWithPath:path];
}

+ (PDFileManager *)fileManagerWithPropertyListRepresentation:(id)obj
{
  PDFileManager *fm;

  fm = [[PDLocalFileManager alloc] initWithPropertyListRepresentation:obj];
  if (fm != nil)
    return fm;

  return nil;
}

- (id)propertyListRepresentation
{
  return nil;
}

- (BOOL)isEqualToPath:(NSString *)path
{
  return NO;
}

- (BOOL)isEqualToPropertyListRepresentation:(id)obj
{
  return NO;
}

- (id<PDFileManagerDelegate>)delegate
{
  return nil;
}

- (void)setDelegate:(id<PDFileManagerDelegate>)delegate
{
}

- (NSString *)name
{
  return @"Unknown";
}

- (NSString *)localizedDescription
{
  return @"Unknown";
}

- (NSImage *)iconImage
{
  return nil;
}

- (void)invalidate
{
}

- (void)unmount
{
}

- (NSURL *)fileURLWithPath:(NSString *)path
{
  return nil;
}

- (BOOL)fileExistsAtPath:(NSString *)path
{
  return NO;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)dirp
{
  return NO;
}

- (time_t)mtimeOfFileAtPath:(NSString *)path
{
  return 0;
}

- (size_t)sizeOfFileAtPath:(NSString *)path
{
  return 0;
}

- (NSData *)contentsOfFileAtPath:(NSString *)path
{
  return nil;
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path
{
  return nil;
}

- (CGImageSourceRef)copyImageSourceAtPath:(NSString *)path
{
  return NULL;
}

static BOOL
unsupported_operation(PDFileManager *self, SEL sel, NSError **err)
{
  if (err != NULL)
    {
      NSString *str = [NSString stringWithFormat:
		       @"File manager <%@> does not support operation %s",
		       [self localizedDescription], sel_getName(sel)];
      *err = [NSError errorWithDomain:ERROR_DOMAIN code:1
	      userInfo:@{NSLocalizedDescriptionKey: str}];
    }

  return NO;
}

- (BOOL)writeData:(NSData *)data toFile:(NSString *)path
    options:(NSDataWritingOptions)options error:(NSError **)err
{
  return unsupported_operation(self, _cmd, err);
}

- (BOOL)createDirectoryAtPath:(NSString *)path
    withIntermediateDirectories:(BOOL)flag attributes:(NSDictionary *)dict
    error:(NSError **)err
{
  return unsupported_operation(self, _cmd, err);
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)err
{
  return unsupported_operation(self, _cmd, err);
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
    error:(NSError **)err
{
  return unsupported_operation(self, _cmd, err);
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)err
{
  return unsupported_operation(self, _cmd, err);
}

@end
