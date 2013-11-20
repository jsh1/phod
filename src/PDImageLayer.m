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

#import "PDImageLayer.h"

#import "PDLibraryImage.h"

#import <QuartzCore/QuartzCore.h>

CA_HIDDEN @interface PDImageLayerLayer : CALayer
@end

@implementation PDImageLayer

@synthesize thumbnail = _thumbnail;

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"backgroundColor"])
    return (id)[[NSColor darkGrayColor] CGColor];
  else
    return [super defaultValueForKey:key];
}

- (id)initWithLayer:(PDImageLayer *)src
{
  self = [super initWithLayer:src];
  if (self == nil)
    return nil;

  _libraryImage = [src->_libraryImage retain];
  _thumbnail = src->_thumbnail;
  _colorSpace = CGColorSpaceRetain(src->_colorSpace);

  return self;
}

- (void)invalidate
{
  if (_addedImageHost)
    {
      [_libraryImage removeImageHost:self];
      _addedImageHost = NO;
    }
}

- (void)removeContent
{
  [self invalidate];

  [self setSublayers:[NSArray array]];
}

- (void)dealloc
{
  [self invalidate];
  [_libraryImage release];
  CGColorSpaceRelease(_colorSpace);

  [super dealloc];
}

- (PDLibraryImage *)libraryImage
{
  return _libraryImage;
}

- (void)setLibraryImage:(PDLibraryImage *)im
{
  if (_libraryImage != im)
    {
      if (_addedImageHost)
	{
	  [_libraryImage removeImageHost:self];
	  _addedImageHost = NO;
	}

      /* to make -libraryImage:setHostedImage: synchronized. */

      [CATransaction lock];

      [_libraryImage release];
      _libraryImage = [im retain];

      [CATransaction unlock];

      [[[self sublayers] firstObject] setContents:nil];
      [self setNeedsLayout];
    }
}

- (CGColorSpaceRef)colorSpace
{
  return _colorSpace;
}

- (void)setColorSpace:(CGColorSpaceRef)space
{
  if (_colorSpace != space)
    {
      CGColorSpaceRelease(_colorSpace);
      _colorSpace = CGColorSpaceRetain(space);
    }
}

- (void)layoutSublayers
{
  if (_libraryImage == nil)
    return;

  CGRect bounds = [self bounds];
  CGFloat scale = [self contentsScale];

  CGSize size = CGSizeMake(ceil(bounds.size.width * scale),
			   ceil(bounds.size.height * scale));

  unsigned int orientation = [_libraryImage orientation];

  if (orientation > 4)
    {
      CGFloat t = size.width;
      size.width = size.height;
      size.height = t;
    }

  /* Use a nested layer to host the image so we can apply the
     orientation transform to it, without the owner of this layer
     needing to care. */

  CALayer *image_layer = [[self sublayers] firstObject];

  if (image_layer == nil)
    {
      image_layer = [PDImageLayerLayer layer];
      [image_layer setDelegate:[self delegate]];
      [self addSublayer:image_layer];
    }

  /* Don't call -addImageHost: etc until the image layer exists -- the
     images are supplied asynchronously via a concurrent queue. */

  if (!_addedImageHost)
    {
      _imageSize = size;
      [_libraryImage addImageHost:self];
      _addedImageHost = YES;
    }
  else if (!CGSizeEqualToSize(_imageSize, size))
    {
      _imageSize = size;
      [_libraryImage updateImageHost:self];
    }

  CGAffineTransform m;
  if (orientation >= 1 && orientation <= 8)
    {
      static const CGFloat mat[8*4] =
	{
	  1, 0, 0, 1,
	  -1, 0, 0, 1,
	  1, 0, 0, -1,
	  -1, 0, 0, -1,
	  0, 1, 1, 0,
	  0, 1, -1, 0,
	  0, -1, -1, 0,
	  0, -1, 1, 0
	};

      m.a = mat[(orientation-1)*4+0];
      m.b = mat[(orientation-1)*4+1];
      m.c = mat[(orientation-1)*4+2];
      m.d = mat[(orientation-1)*4+3];
      m.tx = m.ty = 0;
    }  
  else
    m = CGAffineTransformIdentity;

  [image_layer setAffineTransform:m];
  [image_layer setFrame:bounds];
}

- (NSDictionary *)imageHostOptions
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  [dict setObject:[NSValue valueWithSize:_imageSize]
   forKey:PDLibraryImageHost_Size];

  [dict setObject:[NSNumber numberWithBool:_thumbnail]
   forKey:PDLibraryImageHost_Thumbnail];

  if (_colorSpace != NULL)
    [dict setObject:(id)_colorSpace forKey:PDLibraryImageHost_ColorSpace];

  return dict;
}

- (dispatch_queue_t)imageHostQueue
{
  return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
}

- (void)libraryImage:(PDLibraryImage *)image setHostedImage:(CGImageRef)im
{
  /* Due to -imageHostQueue above, will be called on a background queue. */

  [CATransaction lock];

  if (_libraryImage == image)
    {
      CALayer *image_layer = [[self sublayers] firstObject];

      if (_thumbnail)
	{
	  CGFloat scaling = _imageSize.width / (CGFloat)CGImageGetWidth(im);

	  [image_layer setMinificationFilter:
	   scaling < .9 ? kCAFilterTrilinear : kCAFilterLinear];
	}

      [image_layer setContents:(id)im];
    }

  [CATransaction unlock];
}

@end

@implementation PDImageLayerLayer

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"magnificationFilter"])
    return kCAFilterNearest;
  else if ([key isEqualToString:@"minificationFilterBias"])
    return [NSNumber numberWithFloat:-.1];
  else if ([key isEqualToString:@"edgeAntialiasingMask"])
    return [NSNumber numberWithInt:0];
  else
    return [super defaultValueForKey:key];
}

@end
