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
#import "PDLibraryImage.h"
#import "PDSplitView.h"
#import "PDLibraryViewController.h"

NSString *const PDImageListDidChange = @"PDImageListDidChange";
NSString *const PDSelectionDidChange = @"PDSelectionDidChange";

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
  _primarySelectionIndex = -1;
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

static BOOL
wasFirstResponder(NSView *view)
{
  NSResponder *first = [[view window] firstResponder];

  return ([first isKindOfClass:[NSView class]]
	  && [(NSView *)first isDescendantOf:view]);
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

      BOOL wasFirst = wasFirstResponder([controller view]);

      [controller removeFromContainer];

      _sidebarMode = mode;

      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_sidebarView];

      [_sidebarControl selectSegmentWithTag:_sidebarMode];

      if (wasFirst)
	[[self window] makeFirstResponder:[controller initialFirstResponder]];
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

      BOOL wasFirst = wasFirstResponder([controller view]);

      [controller removeFromContainer];

      _contentMode = mode;

      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_contentView];

      if (wasFirst)
	[[self window] makeFirstResponder:[controller initialFirstResponder]];
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

      if ([_selectedImageIndexes count] != 0)
	[self setSelectedImageIndexes:nil];
    }
}

static NSInteger
closestIndexInSetToIndex(NSIndexSet *set, NSInteger idx)
{
  /* In case 'set' is nil. */

  if ([set count] == 0)
    return -1;

  if ([set containsIndex:idx])
    return idx;

  NSInteger after = [set indexGreaterThanIndex:idx];
  NSInteger before = [set indexLessThanIndex:idx];

  if (after == NSNotFound)
    {
      if (before == NSNotFound)
	return -1;
      else
	return before;
    }
  else if (before == NSNotFound)
    return after;
  else
    return abs(after - idx) < abs(before - idx) ? after : before;
}

- (NSInteger)primarySelectionIndex
{
  return _primarySelectionIndex;
}

- (void)setPrimarySelectionIndex:(NSInteger)idx
{
  idx = closestIndexInSetToIndex(_selectedImageIndexes, idx);

  if (_primarySelectionIndex != idx)
    {
      _primarySelectionIndex = idx;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDSelectionDidChange object:self];
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

      _primarySelectionIndex
        = closestIndexInSetToIndex(set, _primarySelectionIndex);

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDSelectionDidChange object:self];
    }
}

- (void)setSelectedImageIndexes:(NSIndexSet *)set primary:(NSInteger)idx
{
  idx = closestIndexInSetToIndex(set, idx);

  if (_selectedImageIndexes != set || _primarySelectionIndex != idx)
    {
      [_selectedImageIndexes release];
      _selectedImageIndexes = [set copy];

      _primarySelectionIndex = idx;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDSelectionDidChange object:self];
    }
}

- (void)clearSelection
{
  [self setSelectedImageIndexes:[NSIndexSet indexSet] primary:-1];
}

- (void)selectImage:(PDLibraryImage *)image withEvent:(NSEvent *)e;
{
  NSInteger idx = [_imageList indexOfObjectIdenticalTo:image];

  if (idx != NSNotFound)
    {
      NSMutableIndexSet *sel = [_selectedImageIndexes mutableCopy];
      if (sel == nil)
	sel = [[NSMutableIndexSet alloc] init];

      NSInteger primary = _primarySelectionIndex;

      unsigned int modifiers = [e modifierFlags];

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

      [self setSelectedImageIndexes:sel primary:primary];
      [sel release];
    }
  else
    [self clearSelection];
}

static NSIndexSet *
extendSelection(NSIndexSet *sel, NSInteger oldIdx,
		NSInteger newIdx, BOOL byExtending)
{
  if (!byExtending)
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

- (void)movePrimarySelectionRight:(NSInteger)delta
    byExtendingSelection:(BOOL)extend
{
  NSInteger count = [_imageList count];
  if (count == 0)
    return;

  NSInteger idx = _primarySelectionIndex;

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

  NSIndexSet *sel = extendSelection(_selectedImageIndexes,
				    _primarySelectionIndex, idx, extend);

  [self setSelectedImageIndexes:sel primary:idx];
}

- (void)movePrimarySelectionDown:(NSInteger)delta rows:(NSInteger)rows
    columns:(NSInteger)cols byExtendingSelection:(BOOL)extend
{
  NSInteger count = [_imageList count];
  if (count == 0)
    return;

  NSInteger idx = _primarySelectionIndex;

  if (idx >= 0)
    {
      NSInteger y = idx / cols;
      NSInteger x = idx - (y * cols);

      y = y + delta;

      if (y < 0)
	y = 0;
      else if (y > rows)
	y = rows;

      idx = y * cols + x;
      if (idx >= count)
	idx -= cols;
    }
  else
    idx = delta > 0 ? 0 : count - 1;
    
  NSIndexSet *sel = extendSelection(_selectedImageIndexes,
				    _primarySelectionIndex, idx, extend);

  [self setSelectedImageIndexes:sel primary:idx];
}

- (IBAction)setSidebarModeAction:(id)sender
{
  if (sender == _sidebarControl)
    {
      [self setSidebarMode:[[_sidebarControl cell] tagForSegment:
			    [_sidebarControl selectedSegment]]];
    }
  else
    [self setSidebarMode:[sender tag]];
}

- (IBAction)cycleSidebarModeAction:(id)sender
{
  NSInteger idx = _sidebarMode + 1;
  if (idx > PDSidebarMode_Adjustments)
    idx = PDSidebarMode_Library;
  [self setSidebarMode:idx];
}

- (IBAction)setContentModeAction:(id)sender
{
  [self setContentMode:[sender tag]];
}

- (IBAction)cycleContentModeAction:(id)sender
{
  NSInteger idx = _contentMode + 1;
  if (idx > PDContentMode_Image)
    idx = PDContentMode_List;
  [self setContentMode:idx];
}

- (IBAction)zoomIn:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [(PDImageViewController *)[self viewControllerWithClass:
	[PDImageViewController class]] zoomIn:sender];
    }
}

- (IBAction)zoomOut:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [(PDImageViewController *)[self viewControllerWithClass:
	[PDImageViewController class]] zoomOut:sender];
    }
}

- (IBAction)zoomActualSize:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [(PDImageViewController *)[self viewControllerWithClass:
	[PDImageViewController class]] zoomActualSize:sender];
    }
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
  SEL sel = [anItem action];

  if (sel == @selector(zoomIn:)
      || sel == @selector(zoomOut:)
      || sel == @selector(zoomActualSize:))
    {
      return (_contentMode == PDContentMode_Image
	      && _primarySelectionIndex >= 0);
    }

  return YES;
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
