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

#import "PDImageListViewController.h"

#import "PDColor.h"
#import "PDLibraryImage.h"
#import "PDThumbnailLayer.h"
#import "PDWindowController.h"

#define GRID_MARGIN 20
#define GRID_SPACING 30
#define IMAGE_MIN_SIZE 80
#define IMAGE_MAX_SIZE 300
#define TITLE_HEIGHT 25

@implementation PDImageListViewController

+ (NSString *)viewNibName
{
  return @"PDImageListView";
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imageListDidChange:)
   name:PDImageListDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(selectionDidChange:)
   name:PDSelectionDidChange object:_controller];

  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [super dealloc];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [_scrollView setBackgroundColor:[PDColor imageGridBackgroundColor]];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(gridBoundsDidChange:)
   name:NSViewBoundsDidChangeNotification object:[_gridView superview]];

  [_scaleSlider setDoubleValue:[_gridView scale]];
}

- (void)imageListDidChange:(NSNotification *)note
{
  [_gridView setImages:[_controller imageList]];
  [_gridView scrollPoint:NSZeroPoint];
  [_gridView setNeedsDisplay:YES];
}

- (void)selectionDidChange:(NSNotification *)note
{
  [_gridView setPrimarySelection:[_controller primarySelectionIndex]];
  [_gridView setSelection:[_controller selectedImageIndexes]];
  [_gridView setNeedsDisplay:YES];
}

- (void)gridBoundsDidChange:(NSNotification *)note
{
  [_gridView setNeedsDisplay:YES];
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _scaleSlider)
    {
      [_gridView setScale:[sender doubleValue]];
      [_gridView setNeedsDisplay:YES];
    }
}

// CALayerDelegate methods

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)key
{
  return [NSNull null];
}

@end

@implementation PDImageGridView

@synthesize images = _images;
@synthesize primarySelection = _primarySelection;
@synthesize selection = _selection;
@synthesize scale = _scale;

- (id)init
{
  self = [super init];
  if (self == nil)
    return nil;

  _primarySelection = -1;

  return self;
}

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  _scale = .4;

  return self;
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

	  CGFloat w = [[image imagePropertyForKey:
			kCGImagePropertyPixelWidth] doubleValue];
	  CGFloat h = [[image imagePropertyForKey:
			kCGImagePropertyPixelHeight] doubleValue];
	  CGFloat tw = w > h ? _size : floor(_size * (w/h));
	  CGFloat th = w > h ? floor(_size*(h/w)) : _size;

	  if ([[image imagePropertyForKey:
		kCGImagePropertyOrientation] intValue] > 4)
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
    [tem invalidate];

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

- (CGRect)boundingRectOfItemAtIndex:(NSInteger)idx
{
  NSInteger y = idx / _columns;
  NSInteger x = idx - (y * _columns);

  NSRect bounds = [self bounds];

  NSRect rect;
  rect.origin.x = bounds.origin.x + GRID_MARGIN + (_size + GRID_SPACING) * x;
  rect.origin.y = bounds.origin.y + GRID_MARGIN + (_size + GRID_SPACING) * y;
  rect.size.width = _size;
  rect.size.height = _size + TITLE_HEIGHT;

  return rect;
}

- (void)scrollToPrimary
{
  if (_primarySelection >= 0)
    {
      [self scrollRectToVisible:
       [self boundingRectOfItemAtIndex:_primarySelection]];
    }
}

- (void)mouseDownSelection:(NSEvent *)e
{
  NSMutableIndexSet *sel = nil;
  NSInteger primary = -1;

  CALayer *layer = [self layer];

  NSPoint p = [[self superview] convertPoint:
	       [e locationInWindow] fromView:nil];

  CALayer *p_layer = [layer hitTest:NSPointToCGPoint(p)];
  while (p_layer != nil && ![p_layer isKindOfClass:[PDThumbnailLayer class]])
    p_layer = [p_layer superlayer];

  if (p_layer != nil && p_layer != layer)
    {
      PDLibraryImage *image = [(PDThumbnailLayer *)p_layer libraryImage];
      NSInteger idx = [_images indexOfObjectIdenticalTo:image];

      if (idx != NSNotFound)
	{
	  unsigned int modifiers = [e modifierFlags];

	  sel = [_selection mutableCopy];
	  if (sel == nil)
	    sel = [[NSMutableIndexSet alloc] init];

	  primary = _primarySelection;

	  if (modifiers & NSCommandKeyMask)
	    {
	      if (![sel containsIndex:idx])
		{
		  [sel addIndex:idx];
		  primary = idx;
		}
	      else
		[sel removeIndex:idx];
	    }
	  else if (modifiers & NSShiftKeyMask)
	    {
	      if ([sel count] > 0 && primary >= 0)
		{
		  NSInteger i0 = idx < primary ? idx : primary;
		  NSInteger i1 = idx < primary ? primary : idx;
		  [sel addIndexesInRange:NSMakeRange(i0, i1 - i0 + 1)];
		}
	      else
		[sel addIndex:idx];

	      primary = idx;
	    }
	  else
	    {
	      if (![sel containsIndex:idx])
		{
		  [sel removeAllIndexes];
		  [sel addIndex:idx];
		}

	      primary = idx;
	    }
	}
    }

  [[_controller controller] setSelectedImageIndexes:sel primary:primary];

  [sel release];
}

- (void)mouseDown:(NSEvent *)e
{
  switch ([e clickCount])
    {
    case 1:
      [self mouseDownSelection:e];
      break;

    case 2:
      // FIXME: switch to viewer if selection non-empty
      break;
    }
}

static NSIndexSet *
extendSelection(NSEvent *e, NSIndexSet *sel,
		NSInteger oldIdx, NSInteger newIdx)
{
  if (!([e modifierFlags] & NSShiftKeyMask))
    {
      if (![sel containsIndex:newIdx])
	sel = [NSIndexSet indexSetWithIndex:newIdx];
    }
  else
    {
      NSMutableIndexSet *set = [[sel mutableCopy] autorelease];
      NSInteger i0 = oldIdx < newIdx ? oldIdx : newIdx;
      NSInteger i1 = oldIdx < newIdx ? newIdx : oldIdx;
      [set addIndexesInRange:NSMakeRange(i0, i1 - i0 + 1)];
      sel = set;
    }

  return sel;
}

- (void)keyDown:(NSEvent *)e movePrimaryHorizontally:(NSInteger)delta
{
  NSInteger count = [_images count];
  if (count == 0)
    return;

  NSInteger idx = _primarySelection;

  if (idx >= 0)
    {
      idx = idx + delta;
      if (idx < 0)
	idx = 0;
      else if (idx >= count)
	idx = count - 1;
    }
  else
    idx = delta > 0 ? 0 : count - 1;

  NSIndexSet *sel = extendSelection(e, _selection, _primarySelection, idx);

  [[_controller controller] setSelectedImageIndexes:sel primary:idx];

  [self scrollToPrimary];
}

- (void)keyDown:(NSEvent *)e movePrimaryVertically:(NSInteger)delta
{
  NSInteger count = [_images count];
  if (count == 0)
    return;

  NSInteger idx = _primarySelection;

  if (idx >= 0)
    {
      NSInteger y = idx / _columns;
      NSInteger x = idx - (y * _columns);

      y = y + delta;

      if (y < 0)
	y = 0;
      else if (y > _rows)
	y = _rows;

      idx = y * _columns + x;
      if (idx >= count)
	idx -= _columns;
    }
  else
    idx = delta > 0 ? 0 : count - 1;
    
  NSIndexSet *sel = extendSelection(e, _selection, _primarySelection, idx);

  [[_controller controller] setSelectedImageIndexes:sel primary:idx];

  [self scrollToPrimary];
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)keyDown:(NSEvent *)e
{
  NSString *chars = [e charactersIgnoringModifiers];
  if ([chars length] < 1)
    return;

  switch ([chars characterAtIndex:0])
    {
    case NSUpArrowFunctionKey:
      [self keyDown:e movePrimaryVertically:-1];
      break;

    case NSDownArrowFunctionKey:
      [self keyDown:e movePrimaryVertically:1];
      break;

    case NSLeftArrowFunctionKey:
      [self keyDown:e movePrimaryHorizontally:-1];
      break;

    case NSRightArrowFunctionKey:
      [self keyDown:e movePrimaryHorizontally:1];
      break;
    }
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
