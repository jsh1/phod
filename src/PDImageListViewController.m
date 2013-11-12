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
   addObserver:self selector:@selector(selectedImageIndexesDidChange:)
   name:PDSelectedImageIndexesDidChange object:_controller];

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

- (void)selectedImageIndexesDidChange:(NSNotification *)note
{
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
			+ GRID_SPACING * (_rows - 1));

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

	  [sublayer setBounds:CGRectMake(0, 0, tw, th)];

	  CGFloat px = (_size + GRID_SPACING) * x + _size * (CGFloat) .5;
	  CGFloat py = (_size + GRID_SPACING) * y + _size * (CGFloat) .5;

	  [sublayer setPosition:
	   CGPointMake(bounds.origin.x + px, bounds.origin.y + py)];

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

@end
