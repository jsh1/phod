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
#import "PDImageGridView.h"
#import "PDWindowController.h"

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

- (void)viewDidLoad
{
  [super viewDidLoad];

  [_scrollView setBackgroundColor:[PDColor imageGridBackgroundColor]];

  /* This is so we update when the scroll view scrolls. */

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(gridViewBoundsDidChange:)
   name:NSViewBoundsDidChangeNotification object:[_gridView superview]];

  /* This is so we update when the grid view changes size. */

  [_gridView setPostsFrameChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(gridViewBoundsDidChange:)
   name:NSViewFrameDidChangeNotification object:_gridView];

  [_scaleSlider setDoubleValue:[_gridView scale]];
}

- (void)viewDidAppear
{
  [_gridView scrollToPrimaryAnimated:NO];
}

- (NSView *)initialFirstResponder
{
  return _gridView;
}

- (NSDictionary *)savedViewState
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
	  [NSNumber numberWithDouble:[_scaleSlider doubleValue]],
	  @"Scale", nil];
}

- (void)applySavedViewState:(NSDictionary *)state
{
  id value = [state objectForKey:@"Scale"];

  if (value != nil)
    {
      [_scaleSlider setDoubleValue:[value doubleValue]];
      [self controlAction:_scaleSlider];
    }
}

- (void)imageListDidChange:(NSNotification *)note
{
  [_gridView setImages:[_controller imageList]];
  [_gridView scrollPoint:NSZeroPoint];
}

- (void)selectionDidChange:(NSNotification *)note
{
  [_gridView setPrimarySelection:[_controller primarySelectionIndex]];
  [_gridView setSelection:[_controller selectedImageIndexes]];
}

- (void)gridViewBoundsDidChange:(NSNotification *)note
{
  [_gridView setNeedsDisplay:YES];
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _scaleSlider)
    {
      [_gridView setScale:[sender doubleValue]];
    }
}

// CALayerDelegate methods

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)key
{
  return [NSNull null];
}

@end
