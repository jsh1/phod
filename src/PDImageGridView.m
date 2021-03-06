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

#import "PDAppDelegate.h"
#import "PDAppKitExtensions.h"
#import "PDImage.h"
#import "PDImageListViewController.h"
#import "PDThumbnailLayer.h"
#import "PDWindowController.h"

#define GRID_MARGIN 20
#define GRID_SPACING 12
#define IMAGE_MIN_SIZE 80
#define IMAGE_MAX_SIZE 450
#define TITLE_HEIGHT 15
#define MAX_OUTSET 10

#define DRAG_THRESH 3

@implementation PDImageGridView
{
  CGFloat _size;
  NSInteger _columns;
  NSInteger _rows;

  CGPoint _mouseDownLocation;
  BOOL _mouseDownOverImage;
}

@synthesize controller = _controller;
@synthesize images = _images;
@synthesize primarySelection = _primarySelection;
@synthesize selection = _selection;
@synthesize scale = _scale;
@synthesize displaysMetadata = _displaysMetadata;

- (id)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self != nil)
    {
      _scale = .3;
      _displaysMetadata = YES;
      _primarySelection = -1;
    }
  return self;
}

- (void)setImages:(NSArray *)array
{
  if (_images != array)
    {
      _images = [array copy];
      [self setNeedsDisplay:YES];
    }
}

- (void)setPrimarySelection:(NSInteger)idx
{
  if (_primarySelection != idx)
    {
      _primarySelection = idx;
      [self setNeedsDisplay:YES];
    }
}

- (void)setSelection:(NSIndexSet *)set
{
  if (_selection != set)
    {
      _selection = [set copy];
      [self setNeedsDisplay:YES];
    }
}

- (void)setScale:(CGFloat)x
{
  if (_scale != x)
    {
      _scale = x;
      [self setNeedsDisplay:YES];
    }
}

- (void)setDisplaysMetadata:(BOOL)flag
{
  if (_displaysMetadata != flag)
    {
      _displaysMetadata = flag;
      [self setNeedsDisplay:YES];
    }
}

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (void)updateFrameSize
{
  CGRect frame = self.frame;

  CGFloat width = frame.size.width - GRID_MARGIN*2;
  CGFloat ideal = IMAGE_MIN_SIZE + _scale * (IMAGE_MAX_SIZE - IMAGE_MIN_SIZE);

  _columns = fmax(1, floor(width / ideal));
  _rows = (_images.count + (_columns - 1)) / _columns;
  _size = floor((width - GRID_SPACING * (_columns - 1)) / _columns);

  CGFloat v_spacing = GRID_SPACING + (_displaysMetadata ? TITLE_HEIGHT : 0);
  CGFloat height = ceil(GRID_MARGIN*2 + _size * _rows
			+ v_spacing * (_rows - 1)) + MAX_OUTSET;

  if (height != frame.size.height)
    {
      [self setFrameSize:CGSizeMake(frame.size.width, height)];
      [self flashScrollersIfNeeded];
    }
}

- (void)updateLayersForRect:(CGRect)rect
{
  CGRect bounds = CGRectInset(self.bounds, GRID_MARGIN, GRID_MARGIN);

  CGFloat v_spacing = GRID_SPACING + (_displaysMetadata ? TITLE_HEIGHT : 0);
  NSInteger y0 = floor((rect.origin.y - bounds.origin.y)
		       / (_size + v_spacing));
  NSInteger y1 = ceil((rect.origin.y + rect.size.height - bounds.origin.y)
		      / (_size + v_spacing));
  if (y0 < 0) y0 = 0;
  if (y1 < 0) y1 = 0;

  CGFloat backing_scale = self.window.backingScaleFactor;

  NSInteger count = _images.count;

  CALayer *layer = self.layer;
  NSMutableArray *old_sublayers = [layer.sublayers mutableCopy];
  NSMutableArray *new_sublayers = [NSMutableArray array];

  NSInteger y;
  for (y = y0; y < y1; y++)
    {
      NSInteger x;
      for (x = 0; x < _columns; x++)
	{
	  NSInteger idx = y * _columns + x;
	  if (idx >= count)
	    continue;

	  PDImage *image = _images[idx];

	  /* FIXME: hack -- without this, the method will be called
	     from -layoutSublayers, which traverses the sublayers array
	     in reverse order, which cause the thumbnails to update
	     from the bottom not the top of the visible area. */

	  [image startPrefetching];

	  PDThumbnailLayer *sublayer = nil;

	  NSInteger old_idx = 0;
	  for (PDThumbnailLayer *tem in old_sublayers)
	    {
	      if (tem.image == image)
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
	      sublayer.image = image;
	      sublayer.delegate = _controller;
	    }

	  CGSize pixelSize = image.pixelSize;
	  CGFloat w = pixelSize.width;
	  CGFloat h = pixelSize.height;
	  CGFloat aspect = w != 0 && h != 0 ? w/h : 1.3;
	  CGFloat tw = w >= h ? _size : floor(_size * aspect);
	  CGFloat th = w >= h ? floor(_size/aspect) : _size;

	  if (image.orientation > 4)
	    {
	      CGFloat t = tw;
	      tw = th;
	      th = t;
	    }

	  CGFloat px = round(bounds.origin.x + (_size + GRID_SPACING) * x
			     + (_size - tw) * (CGFloat).5);
	  CGFloat py = round(bounds.origin.y + (_size + v_spacing) * y
			     + (_size - th) * (CGFloat).5);

	  sublayer.frame = CGRectMake(px, py, tw, th);
	  sublayer.contentsScale = backing_scale;

	  sublayer.primary = _primarySelection == idx;
	  sublayer.selected = [_selection containsIndex:idx];
	  sublayer.displaysMetadata = _displaysMetadata;

	  /* Just in case size didn't change, but image metadata did. */

	  [sublayer setNeedsLayout];

	  [new_sublayers addObject:sublayer];
	}
    }

  layer.sublayers = new_sublayers;

  for (PDThumbnailLayer *tem in old_sublayers)
    {
      [tem invalidate];
      [tem.image stopPrefetching];
    }

  self.preparedContentRect = rect;
}

- (void)updateLayer
{
  [self updateFrameSize];
  [self updateLayersForRect:self.visibleRect];
}

- (BOOL)isFlipped
{
  return YES;
}

- (CGRect)boundingRectOfItemAtIndex:(NSInteger)idx
{
  NSInteger y = idx / _columns;
  NSInteger x = idx - (y * _columns);

  CGRect bounds = self.bounds;

  CGFloat title_height = _displaysMetadata ? TITLE_HEIGHT : 0;
  CGFloat v_spacing = GRID_SPACING + title_height;

  CGRect rect;
  rect.origin.x = (bounds.origin.x + GRID_MARGIN
		   + (_size + GRID_SPACING) * x - MAX_OUTSET);
  rect.origin.y = (bounds.origin.y + GRID_MARGIN
		   + (_size + v_spacing) * y - MAX_OUTSET);
  rect.size.width = _size + MAX_OUTSET*2;
  rect.size.height = _size + v_spacing + MAX_OUTSET*2;

  return rect;
}

- (void)scrollToPrimaryAnimated:(BOOL)flag
{
  if (_primarySelection >= 0)
    {
      [self scrollRectToVisible:
       [self boundingRectOfItemAtIndex:_primarySelection] animated:flag];
    }
}

- (void)scrollPageUpAnimated:(BOOL)flag
{
  CGRect rect = self.visibleRect;
  rect.origin.y -= rect.size.height;
  [self scrollRectToVisible:rect animated:flag];
}

- (void)scrollPageDownAnimated:(BOOL)flag
{
  CGRect rect = self.visibleRect;
  rect.origin.y += rect.size.height;
  [self scrollRectToVisible:rect animated:flag];
}

/* 'p' is in coordinate space of our superview. */

- (PDImage *)imageAtSuperviewPoint:(CGPoint)p
{
  CALayer *layer = self.layer;

  CALayer *p_layer = [layer hitTest:p];
  while (p_layer != nil && ![p_layer isKindOfClass:[PDThumbnailLayer class]])
    p_layer = p_layer.superlayer;

  if (p_layer != nil && p_layer != layer)
    return ((PDThumbnailLayer *)p_layer).image;
  else
    return nil;
}

- (CALayer *)layerForImage:(PDImage *)image
{
  for (PDThumbnailLayer *layer in self.layer.sublayers)
    {
      if (layer.image == image)
	return layer;
    }

  return nil;
}

- (BOOL)imageMayBeVisible:(PDImage *)image
{
  return [self layerForImage:image] != nil;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
  return YES;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)e
{
  switch (e.type)
    {
    case NSLeftMouseDown:
    case NSLeftMouseDragged:
      return YES;

    default:
      return NO;
    }
}

- (void)mouseDown:(NSEvent *)e
{
  switch ([e clickCount])
    {
    case 1: {
      _mouseDownLocation = [self.superview convertPoint:
			    e.locationInWindow fromView:nil];

      PDImage *image = [self imageAtSuperviewPoint:_mouseDownLocation];

      _mouseDownOverImage = image != nil;

      if (image != nil)
	[_controller.controller selectImage:image withEvent:e];
      else
	[_controller.controller deselectAll:nil];

      [self scrollToPrimaryAnimated:YES];

      if (e.type == NSRightMouseDown
	  || (e.modifierFlags & NSControlKeyMask) != 0)
	{
	  [(PDAppDelegate *)[NSApp delegate]
	   popUpImageContextMenuWithEvent:e forView:self];
	}
      break; }

    case 2:
      if (_primarySelection >= 0)
	[_controller.controller setContentMode:PDContentMode_Image];
      break;
    }
}

- (void)rightMouseDown:(NSEvent *)e
{
  [self mouseDown:e];
}

static CGImageRef
copy_layer_snapshot(CALayer *layer)
{
  CGRect bounds = layer.bounds;

  size_t w = ceil(bounds.size.width);
  size_t h = ceil(bounds.size.height);

  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

  CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, space,
		kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst);

  CGImageRef im = NULL;

  if (ctx != NULL)
    {
      CGContextTranslateCTM(ctx, 0, h);
      CGContextScaleCTM(ctx, 1, -1);

      [layer renderInContext:ctx];

      im = CGBitmapContextCreateImage(ctx);

      CGContextRelease(ctx);
    }

  CGColorSpaceRelease(space);

  return im;
}

- (void)beginDraggingSessionWithEvent:(NSEvent *)e
{
  NSMutableArray *items = [NSMutableArray array];

  for (NSInteger idx = [_selection firstIndex]; idx != NSNotFound;
       idx = [_selection indexGreaterThanIndex:idx])
    {
      PDImage *image = _images[idx];
      NSDraggingItem *item = [[NSDraggingItem alloc]
			      initWithPasteboardWriter:image];

      CALayer *layer = [self layerForImage:image];

      if (layer != nil)
	{
	  CGRect r = [layer convertRect:layer.bounds toLayer:self.layer];

	  item.draggingFrame = r;

	  item.imageComponentsProvider = ^{
	    CGImageRef im = copy_layer_snapshot(layer);
	    NSDraggingImageComponent *comp = [NSDraggingImageComponent
		draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
	    comp.frame = NSMakeRect(0, 0, r.size.width, r.size.height);
	    comp.contents = (__bridge id)im;
	    CGImageRelease(im);
	    return @[comp];
	  };
	}

      [items addObject:item];
    }

  [self beginDraggingSessionWithItems:items event:e source:self];
}

- (void)mouseDragged:(NSEvent *)e
{
  if (e.clickCount != 1)
    return;

  if (!_mouseDownOverImage)
    {
      /* FIXME: rubber-band selection. */
    }
  else
    {
      CGPoint p = [self.superview convertPoint:
		   e.locationInWindow fromView:nil];

      if (fabs(p.x - _mouseDownLocation.x) > DRAG_THRESH
	  || fabs(p.y - _mouseDownLocation.y) > DRAG_THRESH)
	{
	  [NSApp preventWindowOrdering];
	  [self beginDraggingSessionWithEvent:e];
	}
    }
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)e
{
  return [_controller performKeyEquivalent:e];
}

- (void)keyDown:(NSEvent *)e
{
  NSString *chars = [e charactersIgnoringModifiers];

  if (chars.length == 1)
    {
      switch ([chars characterAtIndex:0])
	{
	case NSLeftArrowFunctionKey:
	  [_controller.controller movePrimarySelectionRight:-1
	   byExtendingSelection:(e.modifierFlags & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSRightArrowFunctionKey:
	  [_controller.controller movePrimarySelectionRight:1
	   byExtendingSelection:(e.modifierFlags & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSUpArrowFunctionKey:
	  [_controller.controller movePrimarySelectionDown:-1
	   rows:_rows columns:_columns
	   byExtendingSelection:(e.modifierFlags & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSDownArrowFunctionKey:
	  [_controller.controller movePrimarySelectionDown:1
	   rows:_rows columns:_columns
	   byExtendingSelection:(e.modifierFlags & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:YES];
	  return;

	case NSHomeFunctionKey:
	  [_controller.controller selectFirstByExtendingSelection:
	   (e.modifierFlags & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:NO];
	  [self flashScrollersIfNeeded];
	  return;

	case NSEndFunctionKey:
	  [_controller.controller selectLastByExtendingSelection:
	   (e.modifierFlags & NSShiftKeyMask) != 0];
	  [self scrollToPrimaryAnimated:NO];
	  [self flashScrollersIfNeeded];
	  return;

	case NSPageUpFunctionKey:
	  [self scrollPageUpAnimated:NO];
	  [self flashScrollersIfNeeded];
	  return;

	case NSPageDownFunctionKey:
	  [self scrollPageDownAnimated:NO];
	  [self flashScrollersIfNeeded];
	  return;

	case 0x7f:			/* backspace */
	case NSDeleteFunctionKey:
	  [_controller.controller delete:self];
	  return;
	}
    }

  [super keyDown:e];
}

// NSDraggingSource methods

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)ctx
{
  return NSDragOperationGeneric;
}

@end
