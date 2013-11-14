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

#import "PDImageView.h"

#import "PDAppKitExtensions.h"
#import "PDColor.h"
#import "PDImageLayer.h"
#import "PDImageViewController.h"
#import "PDLibraryImage.h"
#import "PDWindowController.h"

#define IMAGE_MARGIN 10

@implementation PDImageView

- (void)dealloc
{
  [_libraryImage release];

  [super dealloc];
}

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  _imageScale = 1;

  return self;
}

- (PDLibraryImage *)libraryImage
{
  return _libraryImage;
}

- (void)setLibraryImage:(PDLibraryImage *)image
{
  if (_libraryImage != image)
    {
      [_libraryImage release];
      _libraryImage = [image retain];

      [self setNeedsDisplay:YES];
    }
}

- (CGFloat)imageScale
{
  return _imageScale;
}

- (void)setImageScale:(CGFloat)x
{
  if (_imageScale != x)
    {
      _imageScale = x;

      [self setNeedsDisplay:YES];
    }
}

- (CGFloat)scaleToFitScale
{
  if (_libraryImage == nil)
    return 1;

  CGSize pixelSize = [_libraryImage orientedPixelSize];

  NSRect bounds = [[self superview] bounds];

  CGFloat sx = (bounds.size.width - IMAGE_MARGIN*2) / pixelSize.width;
  CGFloat sy = (bounds.size.height - IMAGE_MARGIN*2) / pixelSize.height;

  return sx < sy ? sx : sy;
}

- (void)setImageScale:(CGFloat)scale preserveOrigin:(BOOL)flag
{
  if (!flag)
    {
      [self setImageScale:scale];
      return;
    }

  CGFloat x = (_imageOrigin.x / _imageScale) * scale;
  CGFloat y = (_imageOrigin.y / _imageScale) * scale;

  // FIXME: center around cursor or view center?

  [self setImageScale:scale];

  _imageOrigin = CGPointMake(x, y);
}

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (CGSize)scaledImageSize
{
  if (_libraryImage != nil)
    {
      CGSize pixelSize = [_libraryImage orientedPixelSize];

      CGFloat width = ceil(pixelSize.width * _imageScale);
      CGFloat height = ceil(pixelSize.height * _imageScale);

      return CGSizeMake(width, height);
    }
  else
    return CGSizeZero;
}

- (void)updateLayer
{
  CALayer *layer = [self layer];

  [layer setBackgroundColor:[[PDColor imageGridBackgroundColor] CGColor]];

  if (_clipLayer == nil)
    {
      _clipLayer = [CALayer layer];
      [_clipLayer setMasksToBounds:YES];
      [_clipLayer setDelegate:_controller];
      [layer addSublayer:_clipLayer];

      _imageLayer = [PDImageLayer layer];
      [_imageLayer setDelegate:_controller];
      [_clipLayer addSublayer:_imageLayer];
    }

  if (_libraryImage != nil)
    {
      CGSize scaledSize = [self scaledImageSize];

      NSRect bounds = [self bounds];

      CGRect clipR;
      CGPoint origin = _imageOrigin;

      if (scaledSize.width <= bounds.size.width - IMAGE_MARGIN*2)
	{
	  clipR.origin.x = bounds.origin.x;
	  clipR.size.width = scaledSize.width;
	  clipR.origin.x += floor((bounds.size.width
				   - scaledSize.width) * (CGFloat).5);
	  origin.x = 0;
	}
      else
	{
	  clipR.origin.x = IMAGE_MARGIN;
	  clipR.size.width = bounds.size.width - IMAGE_MARGIN*2;
	  if (_imageOrigin.x < 0)
	    origin.x = 0;
	  else if (_imageOrigin.x > scaledSize.width - bounds.size.width)
	    origin.x = scaledSize.width - bounds.size.width;
	  else
	    origin.x = _imageOrigin.x;
	}

      if (scaledSize.height <= bounds.size.height - IMAGE_MARGIN*2)
	{
	  clipR.origin.y = bounds.origin.y;
	  clipR.size.height = scaledSize.height;
	  clipR.origin.y += floor((bounds.size.height
				   - scaledSize.height) * (CGFloat).5);
	  origin.y = 0;
	}
      else
	{
	  clipR.origin.y = IMAGE_MARGIN;
	  clipR.size.height = bounds.size.height - IMAGE_MARGIN*2;
	  if (_imageOrigin.y < 0)
	    origin.y = 0;
	  else if (_imageOrigin.y > scaledSize.height - bounds.size.height)
	    origin.y = scaledSize.height - bounds.size.height;
	  else
	    origin.y = _imageOrigin.y;
	}

      [_clipLayer setFrame:clipR];

      [_imageLayer setBounds:
       CGRectMake(0, 0, scaledSize.width, scaledSize.height)];
      [_imageLayer setPosition:
       CGPointMake(-origin.x + scaledSize.width * (CGFloat).5,
		   -origin.y + scaledSize.height * (CGFloat).5)];

      [_imageLayer setLibraryImage:_libraryImage];
      [_clipLayer setHidden:NO];
    }
  else
    {
      [_imageLayer setLibraryImage:nil];
      [_clipLayer setHidden:YES];
    }

  [self setPreparedContentRect:[self visibleRect]];
}

- (BOOL)isFlipped
{
  return YES;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
  [self setNeedsDisplay:YES];
  [super resizeSubviewsWithOldSize:oldSize];
}

- (void)mouseDown:(NSEvent *)e
{
  switch ([e clickCount])
    {
    case 2:
      [[_controller controller] setContentMode:PDContentMode_List];
      break;
    }
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)keyDown:(NSEvent *)e
{
  NSString *chars = [e charactersIgnoringModifiers];

  if ([chars length] == 1)
    {
      switch ([chars characterAtIndex:0])
	{
	case NSLeftArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionRight:-1
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  return;

	case NSRightArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionRight:1
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  return;

#if 0
	case NSUpArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionDown:-1
	   rows:_rows columns:_columns
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  return;

	case NSDownArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionDown:1
	   rows:_rows columns:_columns
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  return;
#endif
	}
    }

  [super keyDown:e];
}

@end
