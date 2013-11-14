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
@interface PDImageHostOperation : NSOperation
{
  id<PDLibraryImageHost> _imageHost;
  NSDictionary *_options;

  CGImageSourceRef _imageSource;
  NSDictionary *_imageProperties;
}

- (id)initWithImageHost:(id<PDLibraryImageHost>)host
    imageSource:(CGImageSourceRef)src imageProperties:(NSDictionary *)props;

@end

NSString * const PDLibraryImageHost_Size = @"size";
NSString * const PDLibraryImageHost_Thumbnail = @"thumbnail";

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
  _imageHosts = [[NSMapTable strongToStrongObjectsMapTable] retain];

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

  [_imageHosts release];

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

- (NSDictionary *)imageProperties
{
  if (_imageProperties == NULL)
    {
      CGImageSourceRef src = [self imageSource];

      if (src != NULL)
	_imageProperties = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    }

  return (NSDictionary *)_imageProperties;
}

- (id)imagePropertyForKey:(CFStringRef)key
{
  return [[self imageProperties] objectForKey:(NSString *)key];
}

- (CGSize)pixelSize
{
  NSDictionary *dict = [self imageProperties];

  CGFloat pw = [[dict objectForKey:
		 (id)kCGImagePropertyPixelWidth] doubleValue];
  CGFloat ph = [[dict objectForKey:
		 (id)kCGImagePropertyPixelHeight] doubleValue];

  return CGSizeMake(pw, ph);
}

- (unsigned int)orientation
{
  return [[self imagePropertyForKey:
	   kCGImagePropertyOrientation] unsignedIntValue];
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

- (void)addImageHost:(id<PDLibraryImageHost>)obj
{
  PDImageHostOperation *op;

  assert([_imageHosts objectForKey:obj] == nil);

  op = [[PDImageHostOperation alloc]
	initWithImageHost:obj imageSource:[self imageSource]
	imageProperties:[self imageProperties]];

  [[[self class] imageQueue] addOperation:op];
  [_imageHosts setObject:op forKey:obj];

  [op release];
}

- (void)removeImageHost:(id<PDLibraryImageHost>)obj
{
  PDImageHostOperation *op;

  op = [_imageHosts objectForKey:obj];
  if (op == nil)
    return;

  [op cancel];

  [_imageHosts removeObjectForKey:obj];
}

- (void)updateImageHost:(id<PDLibraryImageHost>)obj
{
  // FIXME: not ideal, but ok for now

  [self removeImageHost:obj];
  [self addImageHost:obj];
}

@end

@implementation PDImageHostOperation

- (id)initWithImageHost:(id<PDLibraryImageHost>)host
    imageSource:(CGImageSourceRef)src imageProperties:(NSDictionary *)props;
{
  self = [super init];
  if (self == nil)
    return nil;

  _imageHost = [host retain];
  _options = [[host imageHostOptions] copy];

  _imageSource = (CGImageSourceRef)CFRetain(src);
  _imageProperties = [props copy];

  return self;
}

- (void)dealloc
{
  [_imageHost release];
  [_options release];
  if (_imageSource)
    CFRelease(_imageSource);
  [_imageProperties release];

  [super dealloc];
}

- (void)main
{
  CGImageRef im = NULL;

  // FIXME: ignoring size for now..

  if ([[_options objectForKey:PDLibraryImageHost_Thumbnail] boolValue])
    im = CGImageSourceCreateThumbnailAtIndex(_imageSource, 0, NULL);

  if (im == NULL)
    im = CGImageSourceCreateImageAtIndex(_imageSource, 0, NULL);

  /* Embedded JPEG thumbnails are often a fixed size and aspect ratio,
     so crop them to the original image's aspect ratio. */

  CGFloat pixelWidth = [[_imageProperties objectForKey:
			 (id)kCGImagePropertyPixelWidth] doubleValue];
  CGFloat pixelHeight = [[_imageProperties objectForKey:
			  (id)kCGImagePropertyPixelHeight] doubleValue];

  CGFloat im_w = CGImageGetWidth(im);
  CGFloat im_h = CGImageGetHeight(im);

  CGRect imR = CGRectMake(0, 0, im_w, im_h);

  if (pixelWidth > pixelHeight)
    {
      CGFloat h = im_w * (pixelHeight / pixelWidth);
      imR.origin.y = ceil((im_h - h) * (CGFloat).5);
      imR.size.height = im_h - (imR.origin.y * 2);
    }
  else
    {
      CGFloat w = im_h * (pixelWidth / pixelHeight);
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
    [_imageHost setHostedImage:im];
    CGImageRelease(im);
  });
}

@end
