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

#import "PDThumbnailLayer.h"

#import "PDColor.h"
#import "PDImage.h"
#import "PDImageLayer.h"
#import "PDImageRatingLayer.h"

#import <QuartzCore/QuartzCore.h>

#define TITLE_SPACING 4
#define MIN_RATING_HEIGHT 17
#define SELECTION_INSET -3
#define SELECTION_WIDTH 1
#define SELECTION_RADIUS 3
#define PRIMARY_SELECTION_INSET -5
#define PRIMARY_SELECTION_WIDTH 3
#define PRIMARY_SELECTION_RADIUS 4

CA_HIDDEN
@interface PDThumbnailTitleLayer : CATextLayer
@end

CA_HIDDEN
@interface PDThumbnailSelectionLayer : CALayer
@end

@implementation PDThumbnailLayer

@synthesize image = _image;
@synthesize selected = _selected;
@synthesize primary = _primary;
@synthesize displaysMetadata = _displaysMetadata;

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"shadowOpacity"])
    return @.6;
  else if ([key isEqualToString:@"shadowOffset"])
    return [NSValue valueWithSize:CGSizeMake(0, 3)];
  else if ([key isEqualToString:@"shadowRadius"])
    return @2;
  else if ([key isEqualToString:@"shadowPathIsBounds"])
    return @YES;
  else
    return [super defaultValueForKey:key];
}

- (id)init
{
  self = [super init];
  if (self != nil)
    _displaysMetadata = YES;
  return self;
}

- (id)initWithLayer:(PDThumbnailLayer *)src
{
  self = [super initWithLayer:src];
  if (self != nil)
    {
      _image = src->_image;
      _selected = src->_selected;
      _primary = src->_primary;
      _displaysMetadata = src->_displaysMetadata;
    }
  return self;
}

- (void)setSelected:(BOOL)flag
{
  if (_selected != flag)
    {
      _selected = flag;
      [self setNeedsLayout];
    }
}

- (void)setPrimary:(BOOL)flag
{
  if (_primary != flag)
    {
      _primary = flag;
      [self setNeedsLayout];
    }
}

- (void)setDisplaysMetadata:(BOOL)flag
{
  if (_displaysMetadata != flag)
    {
      _displaysMetadata = flag;
      [self setNeedsLayout];
    }
}

- (void)invalidate
{
  for (CALayer *sublayer in self.sublayers)
    {
      if ([sublayer isKindOfClass:[PDImageLayer class]])
	[(PDImageLayer *)sublayer invalidate];
    }
}

- (void)dealloc
{
  [self invalidate];
}

- (void)setImage:(PDImage *)im
{
  if (_image != im)
    {
      _image = im;
      [self setNeedsLayout];
    }
}

- (void)layoutSublayers
{
  if (_image == nil)
    return;

  PDImageLayer *image_layer = nil;
  PDThumbnailTitleLayer *title_layer = nil;
  PDImageRatingLayer *rating_layer = nil;
  PDThumbnailSelectionLayer *selection_layer = nil;

  for (CALayer *sublayer in self.sublayers)
    {
      if ([sublayer isKindOfClass:[PDImageLayer class]])
	image_layer = (PDImageLayer *)sublayer;
      else if ([sublayer isKindOfClass:[PDThumbnailTitleLayer class]])
	title_layer = (PDThumbnailTitleLayer *)sublayer;
      else if ([sublayer isKindOfClass:[PDImageRatingLayer class]])
	rating_layer = (PDImageRatingLayer *)sublayer;
      else if ([sublayer isKindOfClass:[PDThumbnailSelectionLayer class]])
	selection_layer = (PDThumbnailSelectionLayer *)sublayer;
    }

  if (image_layer == nil)
    {
      image_layer = [PDImageLayer layer];
      image_layer.thumbnail = YES;
      image_layer.delegate = self.delegate;
      [self addSublayer:image_layer];
    }

  CGRect bounds = self.bounds;

  image_layer.image = _image;
  image_layer.frame = bounds;
  image_layer.contentsScale = self.contentsScale;

  if (_displaysMetadata)
    {
      if (title_layer == nil)
	{
	  title_layer = [PDThumbnailTitleLayer layer];
	  title_layer.delegate = self.delegate;
	  [self addSublayer:title_layer];
	}

      NSString *title = [_image title];
      if (title.length == 0)
	title = [_image name];
      title_layer.string = title;
      title_layer.position =CGPointMake(bounds.origin.x, bounds.origin.y
					+ bounds.size.height + TITLE_SPACING);
      title_layer.contentsScale = self.contentsScale;

      CGSize title_size = [title_layer preferredFrameSize];
      title_size.width = MIN(title_size.width, bounds.size.width);
      title_layer.bounds =
        CGRectMake(0, 0, title_size.width, title_size.height);

      int rating = _image.rating;
      BOOL flagged = _image.flagged;
      BOOL hidden = _image.hidden;

      if ((rating != 0 || flagged || hidden) && rating_layer == nil)
	{
	  rating_layer = [PDImageRatingLayer layer];
	  rating_layer.delegate = self.delegate;
	  [self addSublayer:rating_layer];
	}

      rating_layer.rating = rating;
      rating_layer.flagged = flagged;
      rating_layer.hiddenState = hidden;
      rating_layer.contentsScale = self.contentsScale;

      rating_layer.position = CGPointMake(bounds.origin.x, bounds.origin.y
					  + bounds.size.height);
      CGSize rating_size = [rating_layer preferredFrameSize];
      rating_size.width = MIN(rating_size.width, bounds.size.width);
      rating_size.height = MAX(rating_size.height, MIN_RATING_HEIGHT);
      rating_layer.bounds =
        CGRectMake(0, 0, rating_size.width, rating_size.height);
    }
  else
    {
      [title_layer removeFromSuperlayer];
      title_layer = nil;

      [rating_layer removeFromSuperlayer];
      rating_layer = nil;
    }

  if (_selected)
    {
      CGFloat inset = _primary ? PRIMARY_SELECTION_INSET : SELECTION_INSET;
      CGFloat radius = _primary ? PRIMARY_SELECTION_RADIUS : SELECTION_RADIUS;
      CGFloat width = _primary ? PRIMARY_SELECTION_WIDTH : SELECTION_WIDTH;

      CGRect selR = image_layer.frame;
      if (title_layer != nil)
	selR = CGRectUnion(selR, title_layer.frame);

      if (selection_layer == nil)
	{
	  selection_layer = [PDThumbnailSelectionLayer layer];
	  selection_layer.delegate = self.delegate;
	  [self addSublayer:selection_layer];
	}

      selection_layer.frame = CGRectInset(selR, inset, inset);
      selection_layer.cornerRadius = radius;
      selection_layer.borderWidth = width;
      selection_layer.hidden = NO;
    }
  else
    [selection_layer removeFromSuperlayer];
}

@end

@implementation PDThumbnailTitleLayer

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"font"])
    return [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
  else if ([key isEqualToString:@"fontSize"])
    return @([NSFont smallSystemFontSize]);
  else if ([key isEqualToString:@"truncationMode"])
    return @"start";
  else if ([key isEqualToString:@"anchorPoint"])
    return [NSValue valueWithPoint:CGPointZero];
  else
    return [super defaultValueForKey:key];
}

@end

@implementation PDThumbnailSelectionLayer

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"borderColor"])
    return (id) [[PDColor whiteColor] CGColor];
  else
    return [super defaultValueForKey:key];
}

@end
