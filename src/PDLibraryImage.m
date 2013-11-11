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

#import "PDLibraryImage.h"

CA_HIDDEN
@interface PDThumbnailOperation : NSOperation
{
  CGImageSourceRef _imageSource;
  CGSize _size;
  void (^_handler)(CGImageRef result);
}

@property(nonatomic) CGImageSourceRef imageSource;
@property(nonatomic) CGSize size;
@property(nonatomic, copy) void (^handler)(CGImageRef result);

@end

@implementation PDLibraryImage

static NSOperationQueue *_imageQueue;

@synthesize path = _path;

+ (NSOperationQueue *)imageQueue
{
  if (_imageQueue == nil)
    {
      _imageQueue = [[NSOperationQueue alloc] init];
      [_imageQueue setName:@"PDLibraryImage"];
    }

  return _imageQueue;
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];
  _thumbnails = [[NSMapTable strongToStrongObjectsMapTable] retain];

  return self;
}

- (void)dealloc
{
  [_path release];

  if (_imageSource)
    CFRelease(_imageSource);
  if (_imageProperties)
    CFRelease(_imageProperties);

  [_thumbnails release];

  [super dealloc];
}

- (CGImageSourceRef)imageSource
{
  if (_imageSource == NULL)
    {
      NSURL *url = [[NSURL alloc] initFileURLWithPath:_path];
      NSDictionary *opts = [[NSDictionary alloc] initWithObjectsAndKeys:
			    (id)kCFBooleanFalse, kCGImageSourceShouldCache,
			    nil];
      _imageSource = CGImageSourceCreateWithURL((CFURLRef)url,
						(CFDictionaryRef)opts);
    }

  return _imageSource;
}

- (id)imagePropertyForKey:(CFStringRef)key
{
  if (_imageProperties == NULL)
    {
      CGImageSourceRef src = [self imageSource];
      if (src != NULL)
	_imageProperties = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    }

  if (_imageProperties != NULL)
    return (id) CFDictionaryGetValue(_imageProperties, key);
  else
    return nil;
}

- (void)addThumbnail:(id<PDLibraryImageThumbnail>)obj
{
  PDThumbnailOperation *op;

  assert([_thumbnails objectForKey:obj] == nil);

  op = [[PDThumbnailOperation alloc] init];
  [op setImageSource:[self imageSource]];
  [op setSize:[obj thumbnailSize]];
  [op setHandler:^(CGImageRef im) {
    [obj setThumbnailImage:im];
    [_thumbnails setObject:[NSNull null] forKey:obj];
  }];

  [[[self class] imageQueue] addOperation:op];
  [_thumbnails setObject:op forKey:obj];

  [op release];
}

- (void)removeThumbnail:(id<PDLibraryImageThumbnail>)obj
{
  PDThumbnailOperation *op;

  op = [_thumbnails objectForKey:obj];
  if (op == nil)
    return;

  if ([op isKindOfClass:[PDThumbnailOperation class]])
    [op cancel];

  [_thumbnails removeObjectForKey:obj];
}

- (void)updateThumbnail:(id<PDLibraryImageThumbnail>)obj
{
  // FIXME: not ideal, but ok for now

  [self removeThumbnail:obj];
  [self addThumbnail:obj];
}

@end

@implementation PDThumbnailOperation

@synthesize imageSource = _imageSource;
@synthesize size = _size;
@synthesize handler = _handler;

- (void)main
{
  CGImageRef src_im;

  src_im = CGImageSourceCreateThumbnailAtIndex(_imageSource, 0, NULL);

  if (src_im == NULL)
    src_im = CGImageSourceCreateImageAtIndex(_imageSource, 0, NULL);

  dispatch_async(dispatch_get_main_queue(), ^{
    _handler(src_im);
    CGImageRelease(src_im);
  });
}

@end
