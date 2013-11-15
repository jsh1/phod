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
#import "PDImageLayer.h"
#import "PDLibraryImage.h"

#import <QuartzCore/QuartzCore.h>

#define TITLE_SPACING 4
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
@interface PDThumbnailSelectionLayer : CATextLayer
@end

enum
{
  IMAGE_SUBLAYER,
  TITLE_SUBLAYER,
  SELECTION_SUBLAYER,
};

@implementation PDThumbnailLayer

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"backgroundColor"])
    return (id)[[NSColor darkGrayColor] CGColor];
  else if ([key isEqualToString:@"shadowOpacity"])
    return [NSNumber numberWithDouble:.6];
  else if ([key isEqualToString:@"shadowOffset"])
    return [NSValue valueWithSize:NSMakeSize(0, 3)];
  else if ([key isEqualToString:@"shadowRadius"])
    return [NSNumber numberWithFloat:2];
  else if ([key isEqualToString:@"shadowPathIsBounds"])
    return [NSNumber numberWithBool:YES];
  else
    return [super defaultValueForKey:key];
}

- (id)initWithLayer:(PDThumbnailLayer *)src
{
  self = [super initWithLayer:src];
  if (self == nil)
    return nil;

  _libraryImage = [src->_libraryImage retain];

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

- (BOOL)isSelected
{
  return _selected;
}

- (void)setPrimary:(BOOL)flag
{
  if (_primary != flag)
    {
      _primary = flag;
      [self setNeedsLayout];
    }
}

- (BOOL)isPrimary
{
  return _primary;
}

- (void)invalidate
{
  [[[self sublayers] objectAtIndex:IMAGE_SUBLAYER] invalidate];
}

- (void)dealloc
{
  [self invalidate];

  [_libraryImage release];

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
      [_libraryImage release];
      _libraryImage = [im retain];

      [self setNeedsLayout];
    }
}

- (void)layoutSublayers
{
  if (_libraryImage == nil)
    return;

  if ([[self sublayers] count] == 0)
    {
      id delegate = [self delegate];

      PDImageLayer *image_layer = [PDImageLayer layer];
      [image_layer setThumbnail:YES];
      [image_layer setDelegate:delegate];
      [self addSublayer:image_layer];

      CALayer *title_layer = [PDThumbnailTitleLayer layer];
      [title_layer setDelegate:delegate];
      [self addSublayer:title_layer];

      CALayer *selection_layer = [PDThumbnailSelectionLayer layer];
      [selection_layer setDelegate:delegate];
      [self addSublayer:selection_layer];
    }

  NSArray *sublayers = [self sublayers];
  PDImageLayer *image_layer = (id)[sublayers objectAtIndex:IMAGE_SUBLAYER];
  CATextLayer *title_layer = [sublayers objectAtIndex:TITLE_SUBLAYER];
  CALayer *selection_layer = [sublayers objectAtIndex:SELECTION_SUBLAYER];

  CGRect bounds = [self bounds];

  [image_layer setLibraryImage:_libraryImage];
  [image_layer setFrame:bounds];

  [title_layer setString:[_libraryImage title]];
  [title_layer setPosition:CGPointMake(bounds.origin.x, bounds.origin.y
				       + bounds.size.height + TITLE_SPACING)];

  CGSize text_size = [title_layer preferredFrameSize];
  text_size.width = MIN(text_size.width, bounds.size.width);
  [title_layer setBounds:CGRectMake(0, 0, text_size.width, text_size.height)];

  if (_selected)
    {
      CGFloat inset = _primary ? PRIMARY_SELECTION_INSET : SELECTION_INSET;
      CGFloat radius = _primary ? PRIMARY_SELECTION_RADIUS : SELECTION_RADIUS;
      CGFloat width = _primary ? PRIMARY_SELECTION_WIDTH : SELECTION_WIDTH;

      CGRect selR = CGRectUnion([image_layer frame], [title_layer frame]);
      [selection_layer setFrame:CGRectInset(selR, inset, inset)];
      [selection_layer setCornerRadius:radius];
      [selection_layer setBorderWidth:width];
      [selection_layer setHidden:NO];
    }
  else
    [selection_layer setHidden:YES];
}

@end

@implementation PDThumbnailTitleLayer

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"font"])
    return [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
  else if ([key isEqualToString:@"fontSize"])
    return [NSNumber numberWithDouble:[NSFont smallSystemFontSize]];
  else if ([key isEqualToString:@"truncationMode"])
    return @"start";
  else if ([key isEqualToString:@"anchorPoint"])
    return [NSValue valueWithPoint:NSZeroPoint];
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
