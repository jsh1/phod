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

#import "PDUUIDManager.h"

CA_HIDDEN
@interface PDThumbnailOperation : NSOperation
{
  CGImageSourceRef _imageSource;
  CGSize _imageSize;
  CGSize _thumbnailSize;
  void (^_handler)(CGImageRef result);
}

- (id)initWithImageSource:(CGImageSourceRef)src imageSize:(CGSize)im_size
    thumbnailSize:(CGSize)thumb_size handler:(void(^)(CGImageRef))block;

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
  [_uuid release];

  if (_imageSource)
    CFRelease(_imageSource);
  if (_imageProperties)
    CFRelease(_imageProperties);

  [_thumbnails release];

  [super dealloc];
}

- (NSUUID *)UUID
{
  if (_uuid == nil)
    _uuid = [[PDUUIDManager sharedManager] UUIDOfFileAtPath:_path];

  return _uuid;
}

- (NSString *)title
{
  return [[_path lastPathComponent] stringByDeletingPathExtension];
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
      [opts release];
      [url release];
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

  op = [[PDThumbnailOperation alloc]
	initWithImageSource:[self imageSource]
	imageSize:CGSizeMake([[self imagePropertyForKey:
			       kCGImagePropertyPixelWidth] doubleValue],
			     [[self imagePropertyForKey:
			       kCGImagePropertyPixelHeight] doubleValue])
	thumbnailSize:[obj thumbnailSize]
	handler:^(CGImageRef im) {
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

- (id)initWithImageSource:(CGImageSourceRef)src imageSize:(CGSize)im_size
    thumbnailSize:(CGSize)thumb_size handler:(void(^)(CGImageRef))block
{
  self = [super init];
  if (self == nil)
    return nil;

  _imageSource = (CGImageSourceRef)CFRetain(src);
  _imageSize = im_size;
  _thumbnailSize = thumb_size;
  _handler = [block copy];

  return self;
}

- (void)dealloc
{
  if (_imageSource)
    CFRelease(_imageSource);
  [_handler release];

  [super dealloc];
}

- (void)main
{
  CGImageRef im;

  // FIXME: ignoring size for now..

  im = CGImageSourceCreateThumbnailAtIndex(_imageSource, 0, NULL);

  if (im == NULL)
    im = CGImageSourceCreateImageAtIndex(_imageSource, 0, NULL);

  /* Embedded JPEG thumbnails are often a fixed size and aspect ratio,
     so crop them to the original image's aspect ratio. */

  CGFloat im_w = CGImageGetWidth(im);
  CGFloat im_h = CGImageGetHeight(im);

  CGRect imR = CGRectMake(0, 0, im_w, im_h);

  if (_imageSize.width > _imageSize.height)
    {
      CGFloat h = im_w * (_imageSize.height / _imageSize.width);
      imR.origin.y = ceil((im_h - h) * (CGFloat).5);
      imR.size.height = im_h - (imR.origin.y * 2);
    }
  else
    {
      CGFloat w = im_h * (_imageSize.width / _imageSize.height);
      imR.origin.x = ceil((im_w - w) * (CGFloat).5);
      imR.size.width = im_w - (imR.origin.x * 2);
    }

  if (!CGRectEqualToRect(imR, CGRectMake(0, 0, im_w, im_h)))
    {
      CGImageRef im_copy = CGImageCreateWithImageInRect(im, imR);
      CGImageRelease(im);
      im = im_copy;
    }

  dispatch_async(dispatch_get_main_queue(), ^{
    _handler(im);
    CGImageRelease(im);
  });
}

@end
