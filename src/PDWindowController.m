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

#import "PDWindowController.h"

#import "PDAdjustmentsViewController.h"
#import "PDAppDelegate.h"
#import "PDColor.h"
#import "PDImageViewController.h"
#import "PDImageListViewController.h"
#import "PDInfoViewController.h"
#import "PDSplitView.h"
#import "PDLibraryViewController.h"

NSString *const PDImageListDidChange = @"PDImageListDidChange";
NSString *const PDSelectedImageIndexesDidChange = @"PDSelectedImageIndexesDidChange";

@implementation PDWindowController

- (NSString *)windowNibName
{
  return @"PDWindow";
}

- (PDViewController *)viewControllerWithClass:(Class)cls
{
  if (cls == nil)
    return nil;

  for (PDViewController *obj in _viewControllers)
    {
      obj = [obj viewControllerWithClass:cls];
      if (obj != nil)
	return obj;
    }

  return nil;
}

- (id)init
{
  self = [super initWithWindow:nil];
  if (self == nil)
    return nil;

  _viewControllers = [[NSMutableArray alloc] init];

  _sidebarMode = PDSidebarMode_Nil;
  _contentMode = PDContentMode_Nil;

  _imageList = [[NSArray alloc] init];
  _selectedImageIndexes = [[NSIndexSet alloc] init];

  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSRunLoop cancelPreviousPerformRequestsWithTarget:self];

  [_viewControllers release];
  [_imageList release];
  [_selectedImageIndexes release];

  [super dealloc];
}

- (void)windowDidLoad
{
  NSWindow *window = [self window];

  [window setBackgroundColor:[PDColor windowBackgroundColor]];

  [_splitView setIndexOfResizableSubview:1];

  for (Class cls in @[[PDLibraryViewController class],
		      [PDInfoViewController class],
		      [PDAdjustmentsViewController class],
		      [PDImageListViewController class],
		      [PDImageViewController class]])
    {
      PDViewController *controller = [[cls alloc] initWithController:self];
      if (controller != nil)
	{
	  [_viewControllers addObject:controller];
	  [controller release];
	}
    }

  // make sure we're in viewer mode before trying to restore view state

  [self setSidebarMode:PDSidebarMode_Library];
  [self setContentMode:PDContentMode_List];

  [self applySavedWindowState];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(windowWillClose:)
   name:NSWindowWillCloseNotification object:window];

  [window setInitialFirstResponder:
   [[self viewControllerWithClass:[PDLibraryViewController class]]
    initialFirstResponder]];

  [window makeFirstResponder:[window initialFirstResponder]];
}

- (void)windowWillClose:(NSNotification *)note
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [self saveWindowState];

  [NSApp terminate:self];
}

- (void)saveWindowState
{
  if (![self isWindowLoaded] || [self window] == nil)
    return;

  NSMutableDictionary *controllers = [NSMutableDictionary dictionary];

  for (PDViewController *controller in _viewControllers)
    {
      NSDictionary *sub = [controller savedViewState];
      if ([sub count] != 0)
	[controllers setObject:sub forKey:[controller identifier]];
    }

  NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
			controllers, @"PDViewControllers",
			[_splitView savedViewState], @"PDSplitViewState",
			nil];

  [[NSUserDefaults standardUserDefaults]
   setObject:dict forKey:@"PDSavedWindowState"];
}

- (void)applySavedWindowState
{
  NSDictionary *state, *dict, *sub;

  state = [[NSUserDefaults standardUserDefaults]
	   dictionaryForKey:@"PDSavedWindowState"];
  if (state == nil)
    return;

  dict = [state objectForKey:@"PDViewControllers"];

  if (dict != nil)
    {
      for (PDViewController *controller in _viewControllers)
	{
	  sub = [dict objectForKey:[controller identifier]];
	  if (sub != nil)
	    [controller applySavedViewState:sub];
	}
    }

  dict = [state objectForKey:@"PDSplitViewState"];
  if (dict != nil)
    [_splitView applySavedViewState:dict];
}

static Class
sidebarClassForMode(enum PDSidebarMode mode)
{
  switch (mode)
    {
    case PDSidebarMode_Nil:
      return nil;
    case PDSidebarMode_Library:
      return [PDLibraryViewController class];
    case PDSidebarMode_Info:
      return [PDInfoViewController class];
    case PDSidebarMode_Adjustments:
      return [PDAdjustmentsViewController class];
    }
}

static Class
contentClassForMode(enum PDContentMode mode)
{
  switch (mode)
    {
    case PDContentMode_Nil:
      return nil;
    case PDContentMode_List:
      return [PDImageListViewController class];
    case PDContentMode_Image:
      return [PDImageViewController class];
    }
}

- (NSInteger)sidebarMode
{
  return _sidebarMode;
}

- (void)setSidebarMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_sidebarMode != mode)
    {
      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];
      [controller removeFromContainer];

      _sidebarMode = mode;

      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_sidebarView];

      [_sidebarControl setSelectedSegment:
       _sidebarMode - PDSidebarMode_Library];
    }
}

- (NSInteger)contentMode
{
  return _contentMode;
}

- (void)setContentMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_contentMode != mode)
    {
      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];
      [controller removeFromContainer];

      _contentMode = mode;

      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_contentView];
    }
}

- (NSArray *)imageList
{
  return _imageList;
}

- (void)setImageList:(NSArray *)array
{
  if (_imageList != array)
    {
      [_imageList release];
      _imageList = [array copy];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageListDidChange object:self];
    }
}

- (NSIndexSet *)selectedImageIndexes
{
  return _selectedImageIndexes;
}

- (void)setSelectedImageIndexes:(NSIndexSet *)set
{
  if (_selectedImageIndexes != set)
    {
      [_selectedImageIndexes release];
      _selectedImageIndexes = [set copy];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDSelectedImageIndexesDidChange object:self];
    }
}

- (IBAction)setSidebarModeAction:(id)sender
{
  if (sender == _sidebarControl)
    {
      [self setSidebarMode:
       PDSidebarMode_Library + [_sidebarControl selectedSegment]];
    }
  else
    [self setSidebarMode:[sender tag]];
}

- (IBAction)setContentModeAction:(id)sender
{
  [self setContentMode:[sender tag]];
}

// NSSplitViewDelegate methods

- (BOOL)splitView:(NSSplitView *)view canCollapseSubview:(NSView *)subview
{
  return NO;
}

- (BOOL)splitView:(NSSplitView *)view shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)idx
{
  return NO;
}

- (CGFloat)splitView:(NSSplitView *)view constrainMinCoordinate:(CGFloat)p
    ofSubviewAt:(NSInteger)idx
{
  NSView *subview = [[view subviews] objectAtIndex:idx];
  CGFloat min_size = [(PDSplitView *)view minimumSizeOfSubview:subview];

  return p + min_size;
}

- (CGFloat)splitView:(NSSplitView *)view constrainMaxCoordinate:(CGFloat)p
    ofSubviewAt:(NSInteger)idx
{
  NSView *subview = [[view subviews] objectAtIndex:idx];
  CGFloat min_size = [(PDSplitView *)view minimumSizeOfSubview:subview];

  return p - min_size;
}

- (BOOL)splitView:(NSSplitView *)view
    shouldAdjustSizeOfSubview:(NSView *)subview
{
  if ([view isKindOfClass:[PDSplitView class]])
    return [(PDSplitView *)view shouldAdjustSizeOfSubview:subview];
  else
    return YES;
}

@end
