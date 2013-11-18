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

#import "PDImageGridView.h"

#import "PDAppKitExtensions.h"
#import "PDImageListViewController.h"
#import "PDLibraryImage.h"
#import "PDThumbnailLayer.h"
#import "PDWindowController.h"

#define GRID_MARGIN 20
#define GRID_SPACING 30
#define IMAGE_MIN_SIZE 80
#define IMAGE_MAX_SIZE 450
#define TITLE_HEIGHT 15
#define MAX_OUTSET 10

@implementation PDImageGridView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  _scale = .3;
  _primarySelection = -1;

  return self;
}

- (NSArray *)images
{
  return _images;
}

- (void)setImages:(NSArray *)array
{
  if (_images != array)
    {
      [_images release];
      _images = [array copy];

      [self setNeedsDisplay:YES];
    }
}

- (NSInteger)primarySelection
{
  return _primarySelection;
}

- (void)setPrimarySelection:(NSInteger)idx
{
  if (_primarySelection != idx)
    {
      _primarySelection = idx;

      [self setNeedsDisplay:YES];
    }
}

- (NSIndexSet *)selection
{
  return _selection;
}

- (void)setSelection:(NSIndexSet *)set
{
  if (_selection != set)
    {
      [_selection release];
      _selection = [set copy];

      [self setNeedsDisplay:YES];
    }
}

- (CGFloat)scale
{
  return _scale;
}

- (void)setScale:(CGFloat)x
{
  if (_scale != x)
    {
      _scale = x;

      [self setNeedsDisplay:YES];
    }
}

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (void)updateFrameSize
{
  NSRect frame = [self frame];

  CGFloat width = frame.size.width - GRID_MARGIN*2;
  CGFloat ideal = IMAGE_MIN_SIZE + _scale * (IMAGE_MAX_SIZE - IMAGE_MIN_SIZE);

  _columns = floor(width / ideal);
  _rows = ([_images count] + (_columns - 1)) / _columns;
  _size = floor((width - GRID_SPACING * (_columns - 1)) / _columns);

  CGFloat height = ceil(GRID_MARGIN*2 + _size * _rows
			+ GRID_SPACING * (_rows - 1) + TITLE_HEIGHT);

  if (height != frame.size.height)
    {
      [self setFrameSize:NSMakeSize(frame.size.width, height)];

      NSScrollView *scrollView = [self enclosingScrollView];
      if (height > [scrollView bounds].size.height)
	[scrollView flashScrollers];
    }
}

- (void)updateLayersForRect:(NSRect)rect
{
  NSRect bounds = NSInsetRect([self bounds], GRID_MARGIN, GRID_MARGIN);

  NSInteger y0 = floor((rect.origin.y - bounds.origin.y)
		       / (_size + GRID_SPACING));
  NSInteger y1 = ceil((rect.origin.y + rect.size.height - bounds.origin.y)
		      / (_size + GRID_SPACING));
  if (y0 < 0) y0 = 0;
  if (y1 < 0) y1 = 0;

  NSInteger count = [_images count];

  CALayer *layer = [self layer];
  NSMutableArray *old_sublayers = [[layer sublayers] mutableCopy];
  NSMutableArray *new_sublayers = [[NSMutableArray alloc] init];

  NSInteger y;
  for (y = y0; y < y1; y++)
    {
      NSInteger x;
      for (x = 0; x < _columns; x++)
	{
	  NSInteger idx = y * _columns + x;
	  if (idx >= count)
	    continue;

	  PDLibraryImage *image = [_images objectAtIndex:idx];

	  PDThumbnailLayer *sublayer = nil;

	  NSInteger old_idx = 0;
	  for (PDThumbnailLayer *tem in old_sublayers)
	    {
	      if ([tem libraryImage] == image)
		{
		  [old_sublayers removeObjectAtIndex:old_idx];
		  sublayer = tem;
		  break;
		}
	      old_idx++;
	    }

	  if (sublayer == nil)
	    {
	      sublayer = [PDThumbnailLayer layer];
	      [sublayer setLibraryImage:image];
	      [sublayer setDelegate:_controller];
	    }

	  CGSize pixelSize = [image pixelSize];
	  CGFloat w = pixelSize.width;
	  CGFloat h = pixelSize.height;
	  CGFloat tw = w > h ? _size : floor(_size * (w/h));
	  CGFloat th = w > h ? floor(_size*(h/w)) : _size;

	  if ([image orientation] > 4)
	    {
	      CGFloat t = tw;
	      tw = th;
	      th = t;
	    }

	  CGFloat px = round(bounds.origin.x + (_size + GRID_SPACING) * x
			     + (_size - tw) * (CGFloat).5);
	  CGFloat py = round(bounds.origin.y + (_size + GRID_SPACING) * y
			     + (_size - th) * (CGFloat).5);

	  [sublayer setFrame:CGRectMake(px, py, tw, th)];

	  [sublayer setPrimary:_primarySelection == idx];
	  [sublayer setSelected:[_selection containsIndex:idx]];

	  [new_sublayers addObject:sublayer];
	}
    }

  [layer setSublayers:new_sublayers];

  for (PDThumbnailLayer *tem in old_sublayers)
    {
      [tem invalidate];
      [[tem libraryImage] stopPrefetching];
    }

  [new_sublayers release];
  [old_sublayers release];

  [self setPreparedContentRect:rect];
}

- (void)updateLayer
{
  [self updateFrameSize];
  [self updateLayersForRect:[self visibleRect]];
}

- (BOOL)isFlipped
{
  return YES;
}

- (NSRect)boundingRectOfItemAtIndex:(NSInteger)idx
{
  NSInteger y = idx / _columns;
  NSInteger x = idx - (y * _columns);

  NSRect bounds = [self bounds];

  NSRect rect;
  rect.origin.x = (bounds.origin.x + GRID_MARGIN
		   + (_size + GRID_SPACING) * x - MAX_OUTSET);
  rect.origin.y = (bounds.origin.y + GRID_MARGIN
		   + (_size + GRID_SPACING) * y - MAX_OUTSET);
  rect.size.width = _size + MAX_OUTSET*2;
  rect.size.height = _size + TITLE_HEIGHT + MAX_OUTSET*2;

  return rect;
}

- (void)scrollToPrimaryAnimated:(BOOL)flag
{
  if (_primarySelection >= 0)
    {
      [self scrollRectToVisible:
       [self boundingRectOfItemAtIndex:_primarySelection] animated:YES];
    }
}

/* 'p' is in coordinate space of our superview. */

- (PDLibraryImage *)imageAtSuperviewPoint:(NSPoint)p
{
  CALayer *layer = [self layer];

  CALayer *p_layer = [layer hitTest:NSPointToCGPoint(p)];
  while (p_layer != nil && ![p_layer isKindOfClass:[PDThumbnailLayer class]])
    p_layer = [p_layer superlayer];

  if (p_layer != nil && p_layer != layer)
    return [(PDThumbnailLayer *)p_layer libraryImage];
  else
    return nil;
}

- (void)mouseDown:(NSEvent *)e
{
  switch ([e clickCount])
    {
      PDLibraryImage *image;

    case 1:
      image = [self imageAtSuperviewPoint:
	       [[self superview] convertPoint:
		[e locationInWindow] fromView:nil]];

      if (image != nil)
	[[_controller controller] selectImage:image withEvent:e];
      else
	[[_controller controller] clearSelection];

      [self scrollToPrimaryAnimated:YES];
      break;

    case 2:
      if (_primarySelection >= 0)
	[[_controller controller] setContentMode:PDContentMode_Image];
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
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSRightArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionRight:1
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSUpArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionDown:-1
	   rows:_rows columns:_columns
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSDownArrowFunctionKey:
	  [[_controller controller] movePrimarySelectionDown:1
	   rows:_rows columns:_columns
	   byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;
	}
    }

  [super keyDown:e];
}

- (void)selectAll:(id)sender
{
  NSInteger count = [_images count];
  if (count == 0)
    return;

  NSInteger idx = _primarySelection;
  if (idx < 0)
    idx = 0;

  [[_controller controller] setSelectedImageIndexes:
   [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)] primary:idx];
}

- (void)deselectAll:(id)sender
{
  [[_controller controller] setSelectedImageIndexes:
   [NSIndexSet indexSet] primary:-1];
}

@end
