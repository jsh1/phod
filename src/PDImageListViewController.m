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

  [_gridView setPostsBoundsChangedNotifications:YES];
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

@end

@implementation PDImageGridView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  _scale = .2;

  return self;
}

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (void)updateLayer
{
  NSRect frame = [self frame];

  CGFloat width = frame.size.width - GRID_MARGIN*2;
  CGFloat ideal = IMAGE_MIN_SIZE + _scale * (IMAGE_MAX_SIZE - IMAGE_MIN_SIZE);

  _columns = floor(width / ideal);
  _rows = ([_images count] + (_columns - 1) / _columns);
  _size = (width - GRID_SPACING * (_columns - 1)) / _columns;

  CGFloat height = GRID_MARGIN*2 + _size * _rows + GRID_SPACING * (_rows - 1);

  if (height != frame.size.height)
    {
      [self setFrameSize:NSMakeSize(frame.size.width, height)];

      NSScrollView *scrollView = [self enclosingScrollView];
      if (height > [scrollView bounds].size.height)
	[scrollView flashScrollers];
    }

  NSRect rect = [self visibleRect];

  // FIXME: create and layout image layers in rect.

  [self setPreparedContentRect:rect];
}

- (BOOL)isFlipped
{
  return YES;
}

@end
