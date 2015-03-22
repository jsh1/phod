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
#import "PDFoundationExtensions.h"
#import "PDImage.h"
#import "PDImageLibrary.h"
#import "PDImageViewController.h"
#import "PDImageListViewController.h"
#import "PDImportViewController.h"
#import "PDInfoViewController.h"
#import "PDSplitView.h"
#import "PDLibraryViewController.h"
#import "PDPredicatePanelController.h"

NSString *const PDImageListDidChange = @"PDImageListDidChange";
NSString *const PDSelectionDidChange = @"PDSelectionDidChange";
NSString *const PDShowsHiddenImagesDidChange = @"PDShowsHiddenImagesDidChange";
NSString *const PDImagePredicateDidChange = @"PDImagePredicateDidChange";
NSString *const PDImageSortOptionsDidChange = @"PDImageSortOptionsDidChange";
NSString *const PDImportModeDidChange = @"PDImportModeDidChange";
NSString *const PDTrashWasEmptied = @"PDTrashWasEmptied";

@implementation PDWindowController
{
  PDPredicatePanelController *_predicatePanelController;

  NSMutableArray *_viewControllers;

  BOOL _filteredImageListIsPreservingImages;
}

@synthesize splitView = _splitView;
@synthesize sidebarControl = _sidebarControl;
@synthesize sidebarView = _sidebarView;
@synthesize contentView = _contentView;
@synthesize accessoryView = _accessoryView;
@synthesize sidebarMode = _sidebarMode;
@synthesize contentMode = _contentMode;
@synthesize accessoryMode = _accessoryMode;
@synthesize showsHiddenImages = _showsHiddenImages;
@synthesize imageList = _imageList;
@synthesize imageListTitle = _imageListTitle;
@synthesize imagePredicate = _imagePredicate;
@synthesize imageSortKey = _imageSortKey;
@synthesize imageSortReversed = _imageSortReversed;
@synthesize nilPredicateIncludesRejected = _nilPredicateIncludesRejected;
@synthesize filteredImageList = _filteredImageList;
@synthesize selectedImageIndexes = _selectedImageIndexes;
@synthesize primarySelectionIndex = _primarySelectionIndex;
@synthesize importMode = _importMode;

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
      PDViewController *tem = [obj viewControllerWithClass:cls];
      if (tem != nil)
	return tem;
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
  _accessoryMode = PDAccessoryMode_Nil;

  _imageSortKey = PDImageCompare_Date;
  _imageSortReversed = NO;

  _imageList = @[];
  _filteredImageList = @[];

  _primarySelectionIndex = -1;
  _selectedImageIndexes = [[NSIndexSet alloc] init];

  for (Class cls in @[[PDLibraryViewController class],
		      [PDInfoViewController class],
		      [PDAdjustmentsViewController class],
		      [PDImageListViewController class],
		      [PDImageViewController class],
		      [PDImportViewController class]])
    {
      PDViewController *controller = [[cls alloc] initWithController:self];
      if (controller != nil)
	{
	  [_viewControllers addObject:controller];
	}
    }

  return self;
}

- (void)invalidate
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSRunLoop cancelPreviousPerformRequestsWithTarget:self];

  for (PDViewController *controller in _viewControllers)
    [controller invalidate];
}

- (void)dealloc
{
  [self invalidate];
}

- (void)windowDidLoad
{
  NSWindow *window = self.window;

  window.backgroundColor = [PDColor windowBackgroundColor];

  _splitView.indexOfResizableSubview = 1;

  // make sure we're in viewer mode before trying to restore view state

  self.sidebarMode = PDSidebarMode_Library;
  self.contentMode = PDContentMode_List;

  _accessoryMode = -1;
  self.accessoryMode = PDAccessoryMode_Nil;

  [self applySavedWindowState];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(windowWillClose:)
   name:NSWindowWillCloseNotification object:window];

  window.initialFirstResponder =
   [[self viewControllerWithClass:[PDLibraryViewController class]]
    initialFirstResponder];

  [window makeFirstResponder:window.initialFirstResponder];
}

- (void)windowWillClose:(NSNotification *)note
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [self synchronize];

  [self saveWindowState];

  [self invalidate];

  [NSApp terminate:self];
}

- (void)synchronize
{
  for (PDViewController *controller in _viewControllers)
    [controller synchronize];
}

- (void)saveWindowState
{
  if (!self.windowLoaded || self.window == nil)
    return;

  NSMutableDictionary *controllers = [NSMutableDictionary dictionary];

  for (PDViewController *controller in _viewControllers)
    {
      NSDictionary *sub = [controller savedViewState];
      if (sub.count != 0)
	controllers[controller.identifier] = sub;
    }

  NSDictionary *dict = @{
    @"PDViewControllers": controllers,
    @"PDSplitViewState": [_splitView savedViewState],
  };

  [[NSUserDefaults standardUserDefaults]
   setObject:dict forKey:@"PDSavedWindowState"];
}

- (void)applySavedWindowState
{
  NSDictionary *state = [[NSUserDefaults standardUserDefaults]
			 dictionaryForKey:@"PDSavedWindowState"];
  if (state == nil)
    return;

  NSDictionary *dict = state[@"PDViewControllers"];
  if (dict != nil)
    {
      for (PDViewController *controller in _viewControllers)
	{
	  NSDictionary *sub = dict[controller.identifier];
	  if (sub != nil)
	    [controller applySavedViewState:sub];
	}
    }

  dict = state[@"PDSplitViewState"];
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

static Class
accessoryClassForMode(enum PDAccessoryMode mode)
{
  switch (mode)
    {
    case PDAccessoryMode_Nil:
      return nil;
    case PDAccessoryMode_Import:
      return [PDImportViewController class];
    }
}

static BOOL
wasFirstResponder(NSView *view)
{
  NSResponder *first = view.window.firstResponder;

  return ([first isKindOfClass:[NSView class]]
	  && [(NSView *)first isDescendantOf:view]);
}

- (void)setSidebarMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_sidebarMode != mode)
    {
      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];

      BOOL wasFirst = wasFirstResponder(controller.view);

      [controller removeFromContainer];

      _sidebarMode = mode;

      cls = sidebarClassForMode(_sidebarMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_sidebarView];

      [_sidebarControl selectSegmentWithTag:_sidebarMode];

      if (wasFirst)
	[self.window makeFirstResponder:controller.initialFirstResponder];
    }
}

- (void)setContentMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_contentMode != mode)
    {
      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];

      BOOL wasFirst = wasFirstResponder(controller.view);

      [controller removeFromContainer];

      _contentMode = mode;

      cls = contentClassForMode(_contentMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_contentView];

      if (wasFirst)
	[self.window makeFirstResponder:controller.initialFirstResponder];
    }
}

- (void)setAccessoryMode:(NSInteger)mode
{
  Class cls;
  PDViewController *controller;

  if (_accessoryMode != mode)
    {
      cls = accessoryClassForMode(_accessoryMode);
      controller = [self viewControllerWithClass:cls];

      BOOL wasFirst = wasFirstResponder(controller.view);

      [controller removeFromContainer];

      _accessoryMode = mode;

      cls = accessoryClassForMode(_accessoryMode);
      controller = [self viewControllerWithClass:cls];
      [controller addToContainerView:_accessoryView];

      [_accessoryView setHidden:controller == nil];

      CGRect aframe = _accessoryView.frame;
      CGFloat llx = aframe.origin.x;
      CGFloat urx = llx + aframe.size.width;

      CGRect cframe = _contentView.frame;
      cframe.size.width = (mode == PDAccessoryMode_Nil ? urx : llx) - cframe.origin.x;
      _contentView.frame = cframe;

      if (wasFirst && controller != nil)
	[self.window makeFirstResponder:controller.initialFirstResponder];
    }
}

- (void)setImportMode:(BOOL)flag
{
  if (_importMode != flag)
    {
      _importMode = flag;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImportModeDidChange object:self];
    }
}

- (void)setImportDestinationLibrary:(PDImageLibrary *)lib
    directory:(NSString *)dir
{
  [(PDImportViewController *)[self viewControllerWithClass:
   [PDImportViewController class]] setImportDestinationLibrary:lib
   directory:dir];
}

- (void)contentKeyDown:(NSEvent *)e makeKey:(BOOL)flag
{
  PDViewController *controller = [self viewControllerWithClass:
				  contentClassForMode(_contentMode)];

  NSView *view = controller.initialFirstResponder;

  if (view != nil)
    {
      if (flag && (e.modifierFlags & (NSShiftKeyMask|NSCommandKeyMask)) == 0)
	{
	  [self.window makeFirstResponder:view];
	}

      [view keyDown:e];
    }
}

- (PDPredicatePanelController *)predicatePanelController
{
  if (_predicatePanelController == nil)
    {
      _predicatePanelController = [[PDPredicatePanelController alloc] init];

      if (_imagePredicate != nil)
	_predicatePanelController.predicate = _imagePredicate;

      [[NSNotificationCenter defaultCenter] addObserver:self
       selector:@selector(predicateDidChange:)
       name:PDPredicateDidChange object:_predicatePanelController];
    }

  return _predicatePanelController;
}

- (void)predicateDidChange:(NSNotification *)note
{
  self.imagePredicate = _predicatePanelController.predicate;
  [self rebuildImageList:PDWindowController_StopPreservingImages];
}

- (BOOL)foreachImage:(void (^)(PDImage *im, BOOL *stop))thunk;
{
  return [(PDLibraryViewController *)[self viewControllerWithClass:
	  [PDLibraryViewController class]] foreachImage:thunk];
}

- (void)setShowsHiddenImages:(BOOL)flag
{
  if (_showsHiddenImages != flag)
    {
      _showsHiddenImages = flag;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDShowsHiddenImagesDidChange object:self];
    }
}

- (void)setImageList:(NSArray *)array
{
  if (![_imageList isEqual:array])
    {
      _imageList = [array copy];
    }
}

- (void)setImageListTitle:(NSString *)str
{
  if (_imageListTitle != str)
    {
      _imageListTitle = [str copy];
    }
}

- (NSPredicate *)imagePredicateWithFormat:(NSString *)str, ...
{
  va_list args;
  va_start(args, str);

  NSPredicate *ret = [self.predicatePanelController
		      predicateWithFormat:str argv:args];

  va_end(args);
  return ret;
}

- (NSPredicate *)imagePredicateWithFormat:(NSString *)str argv:(va_list)args
{
  return [self.predicatePanelController predicateWithFormat:str argv:args];
}

- (void)setImagePredicate:(NSPredicate *)pred
{
  if (_imagePredicate != pred)
    {
      _imagePredicate = [pred copy];

      _predicatePanelController.predicate = _imagePredicate;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImagePredicateDidChange object:self];
    }
}

- (void)setImageSortKey:(int)key
{
  if (_imageSortKey != key)
    {
      _imageSortKey = key;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageSortOptionsDidChange object:self];
    }
}

- (void)setImageSortReversed:(BOOL)flag
{
  if (_imageSortReversed != flag)
    {
      _imageSortReversed = flag;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageSortOptionsDidChange object:self];
    }
}

- (void)rebuildImageList:(uint32_t)flags
{
  NSArray *selected_images = [self.selectedImages copy];
  PDImage *primary_image = self.primarySelectedImage;

  NSMutableArray *array = [NSMutableArray array];

  if (_filteredImageListIsPreservingImages
      && !(flags & PDWindowController_StopPreservingImages))
    flags |= PDWindowController_PreserveSelectedImages;

  _filteredImageListIsPreservingImages = NO;

  for (PDImage *image in _imageList)
    {
      /* Implicit predicate is "rating >= 0" (i.e. not-rejected). */

      BOOL included = (_imagePredicate != nil
	  ? [_imagePredicate evaluateWithObject:image.expressionValues]
	  : (_nilPredicateIncludesRejected ? YES : image.rating >= 0));

      if (!included && (flags & PDWindowController_PreserveSelectedImages)
	  && [selected_images indexOfObjectIdenticalTo:image] != NSNotFound)
	{
	  included = YES;
	  _filteredImageListIsPreservingImages = YES;
	}
      
      if (included)
	{
	  [array addObject:image];
	}
    }

  [PDImage callWithImageComparator:_imageSortKey reversed:_imageSortReversed
   block:^(NSComparator cmp) {
     [array sortUsingComparator:cmp];
   }];

  if (![array isEqual:_filteredImageList])
    {
      _filteredImageList = [array copy];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDImageListDidChange object:self];

      [self setSelectedImages:selected_images primary:primary_image];
    }
}

- (void)rebuildImageListIfPreserving
{
  if (_filteredImageListIsPreservingImages)
    {
      [self rebuildImageList:PDWindowController_StopPreservingImages];
    }
}

static NSInteger
closestIndexInSetToIndex(NSIndexSet *set, NSInteger idx)
{
  /* In case 'set' is nil. */

  if (set.count == 0)
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

- (void)setSelectedImageIndexes:(NSIndexSet *)set
{
  if (_selectedImageIndexes != set)
    {
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
      _selectedImageIndexes = [set copy];

      _primarySelectionIndex = idx;

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDSelectionDidChange object:self];
    }
}

static PDImage *
convert_index_to_image(NSInteger idx, NSArray *image_list)
{
  if (idx >= 0 && idx < image_list.count)
    return image_list[idx];
  else
    return nil;
}

static NSInteger
convert_image_to_index(PDImage *im, NSArray *image_list)
{
  return [image_list indexOfObjectIdenticalTo:im];
}

static NSArray *
convert_index_set_to_array(NSIndexSet *set, NSArray *image_list)
{
  NSMutableArray *array = [NSMutableArray array];
  NSInteger count = image_list.count;

  NSInteger idx;
  for (idx = [set firstIndex]; idx != NSNotFound;
       idx = [set indexGreaterThanIndex:idx])
    {
      if (idx >= 0 && idx < count)
	[array addObject:image_list[idx]];
    }

  return array;
}

static NSIndexSet *
convert_array_to_index_set(NSArray *array, NSArray *image_list)
{
  if (array.count == 0)
    return [NSIndexSet indexSet];
  else
    {
      NSMutableIndexSet *set = [NSMutableIndexSet indexSet];

      for (PDImage *im in array)
	{
	  NSInteger idx = [image_list indexOfObjectIdenticalTo:im];
	  if (idx != NSNotFound)
	    [set addIndex:idx];
	}

      return set;
    }
}

- (NSArray *)selectedImages
{
  return convert_index_set_to_array(_selectedImageIndexes, _filteredImageList);
}

- (void)setSelectedImages:(NSArray *)array
{
  [self setSelectedImageIndexes:
   convert_array_to_index_set(array, _filteredImageList)];
}

- (PDImage *)primarySelectedImage
{
  return convert_index_to_image(_primarySelectionIndex, _filteredImageList);
}

- (void)setPrimarySelectedImage:(PDImage *)im
{
  [self setPrimarySelectionIndex:
   convert_image_to_index(im, _filteredImageList)];
}

- (void)setSelectedImages:(NSArray *)array primary:(PDImage *)im
{
  [self setSelectedImageIndexes:
   convert_array_to_index_set(array, _filteredImageList)
   primary:convert_image_to_index(im, _filteredImageList)];
}

- (void)selectImage:(PDImage *)image withEvent:(NSEvent *)e;
{
  NSInteger idx = [_filteredImageList indexOfObjectIdenticalTo:image];

  if (idx != NSNotFound)
    {
      NSMutableIndexSet *sel = [_selectedImageIndexes mutableCopy];
      if (sel == nil)
	sel = [[NSMutableIndexSet alloc] init];

      NSInteger primary = _primarySelectionIndex;

      unsigned int modifiers = e.modifierFlags;

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
	  if (sel.count > 0 && primary >= 0)
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
    }
  else
    [self deselectAll:nil];

  [self rebuildImageListIfPreserving];
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
      NSMutableIndexSet *set = [sel mutableCopy];
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
  NSInteger count = _filteredImageList.count;
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
  [self rebuildImageListIfPreserving];
}

- (void)movePrimarySelectionDown:(NSInteger)delta rows:(NSInteger)rows
    columns:(NSInteger)cols byExtendingSelection:(BOOL)extend
{
  NSInteger count = _filteredImageList.count;
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
  [self rebuildImageListIfPreserving];
}

- (void)selectAll:(id)sender
{
  NSInteger count = _filteredImageList.count;
  if (count == 0)
    return;

  NSInteger idx = _primarySelectionIndex;
  if (idx < 0)
    idx = 0;

  [self setSelectedImageIndexes:
   [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)] primary:idx];
  [self rebuildImageListIfPreserving];
}

- (void)deselectAll:(id)sender
{
  [self setSelectedImageIndexes:[NSIndexSet indexSet] primary:-1];
  [self rebuildImageListIfPreserving];
}

- (void)selectFirstByExtendingSelection:(BOOL)extend
{
  NSInteger count = _filteredImageList.count;
  if (count == 0)
    return;

  NSInteger idx = 0;

  NSIndexSet *sel = extendSelection(_selectedImageIndexes,
				    _primarySelectionIndex, idx, extend);

  [self setSelectedImageIndexes:sel primary:idx];
  [self rebuildImageListIfPreserving];
}

- (void)selectLastByExtendingSelection:(BOOL)extend
{
  NSInteger count = _filteredImageList.count;
  if (count == 0)
    return;

  NSInteger idx = count - 1;

  NSIndexSet *sel = extendSelection(_selectedImageIndexes,
				    _primarySelectionIndex, idx, extend);

  [self setSelectedImageIndexes:sel primary:idx];
  [self rebuildImageListIfPreserving];
}

- (void)selectLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
{
  [(PDLibraryViewController *)[self viewControllerWithClass:
   [PDLibraryViewController class]] selectLibrary:lib directory:dir];
  
}

- (IBAction)nextLibraryItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)previousLibraryItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)parentLibraryItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)firstLibraryChildItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)expandLibraryItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)collapseLibraryItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)expandCollapseLibraryItemAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (void)foreachSelectedImage:(void (^)(PDImage *))block
{
  if (_selectedImageIndexes.count == 0)
    return;

  /* Not using _selectedImageIndexes in case it changes while
     iterating. */

  for (PDImage *image in self.selectedImages)
    {
      block(image);
    }
}

- (IBAction)toggleSidebarAction:(id)sender
{
  NSView *view = _sidebarView.superview;

  [_splitView setSubview:view collapsed:!view.hidden];
}

- (BOOL)isSidebarVisible
{
  NSView *view = _sidebarView.superview;

  return !view.hidden;
}

- (IBAction)setSidebarModeAction:(NSControl *)sender
{
  if (!self.sidebarVisible)
    [self toggleSidebarAction:sender];

  if (sender == _sidebarControl)
    {
      self.sidebarMode = [_sidebarControl.cell tagForSegment:
			  _sidebarControl.selectedSegment];
    }
  else
    self.sidebarMode = sender.tag;
}

- (IBAction)cycleSidebarModeAction:(id)sender
{
  if (!self.sidebarVisible)
    [self toggleSidebarAction:sender];

  NSInteger idx = _sidebarMode + 1;
  if (idx > PDSidebarMode_Adjustments)
    idx = PDSidebarMode_Library;
  self.sidebarMode = idx;
}

- (IBAction)setContentModeAction:(NSControl *)sender
{
  self.contentMode = sender.tag;
}

- (IBAction)cycleContentModeAction:(id)sender
{
  NSInteger idx = _contentMode + 1;
  if (idx > PDContentMode_Image)
    idx = PDContentMode_List;
  self.contentMode = idx;
}

- (IBAction)toggleListMetadata:(id)sender
{
  [(PDImageListViewController *)[self viewControllerWithClass:
    [PDImageListViewController class]] toggleMetadata:sender];
}

- (IBAction)toggleImageMetadata:(id)sender
{
  [(PDImageViewController *)[self viewControllerWithClass:
    [PDImageViewController class]] toggleMetadata:sender];
}

- (BOOL)displaysListMetadata
{
  return [(PDImageListViewController *)[self viewControllerWithClass:
    [PDImageListViewController class]] displaysMetadata];
}

- (BOOL)displaysImageMetadata
{
  return [(PDImageViewController *)[self viewControllerWithClass:
    [PDImageViewController class]] displaysMetadata];
}

- (IBAction)toggleShowsHiddenImages:(id)sender
{
  self.showsHiddenImages = !self.showsHiddenImages;
}

- (IBAction)showPredicatePanel:(id)sender
{
  [self.predicatePanelController showWindow:self];
}

- (IBAction)performFindPanelAction:(id)sender
{
  [self showPredicatePanel:sender];
}

- (IBAction)setImageRatingAction:(NSControl *)sender
{
  NSNumber *rating = @(sender.tag);

  [self foreachSelectedImage:^(PDImage *image) {
    [image setImageProperty:rating forKey:PDImage_Rating];
  }];
}

- (IBAction)addImageRatingAction:(id)sender
{
  int delta = [sender tag];

  [self foreachSelectedImage:^(PDImage *image) {
    int rating = [[image imagePropertyForKey:PDImage_Rating] intValue] + delta;
    rating = MIN(rating, 5); rating = MAX(rating, -1);
    [image setImageProperty:
     [NSNumber numberWithInt:rating] forKey:PDImage_Rating];
  }];
}

- (IBAction)setRatingPredicateAction:(NSControl *)sender
{
  NSPredicate *pred = nil;
  int arg = sender.tag;

  switch (arg)
    {
    case 0:
      pred = nil;
      break;

    case 1:
    case 2:
    case 3:
    case 4:
    case 5:
      pred = [self imagePredicateWithFormat:@"rating >= %d", arg];
      break;

    case 6:				/* show all */
      pred = [self imagePredicateWithFormat:@"rating >= -1"];
      break;

    case 7:				/* unrated */
      pred = [self imagePredicateWithFormat:@"rating == 0"];
      break;

    case 8:				/* rejected */
      pred = [self imagePredicateWithFormat:@"rating == -1"];
      break;

    case 9:				/* flagged */
      pred = [self imagePredicateWithFormat:@"flagged == 1"];
      break;
    }

  self.imagePredicate = pred;
  [self rebuildImageList:PDWindowController_StopPreservingImages];
}

- (IBAction)toggleFlaggedAction:(id)sender
{
  [self foreachSelectedImage:^(PDImage *image) {
    BOOL flagged = [[image imagePropertyForKey:PDImage_Flagged] boolValue];
    [image setImageProperty:[NSNumber numberWithBool:!flagged]
     forKey:PDImage_Flagged];
  }];
}

- (NSInteger)flaggedState
{
  __block BOOL all_set = YES, all_clear = YES;

  [self foreachSelectedImage:^(PDImage *image) {
    if ([[image imagePropertyForKey:PDImage_Flagged] boolValue])
      all_clear = NO;
    else
      all_set = NO;
  }];

  return all_set ? NSOnState : all_clear ? NSOffState : NSMixedState;
}

- (IBAction)toggleHiddenAction:(id)sender
{
  [self foreachSelectedImage:^(PDImage *image) {
    image.hidden = !image.hidden;
  }];
}

- (NSInteger)hiddenState
{
  __block BOOL all_set = YES, all_clear = YES;

  [self foreachSelectedImage:^(PDImage *image) {
    if (image.hidden)
      all_clear = NO;
    else
      all_set = NO;
  }];

  return all_set ? NSOnState : all_clear ? NSOffState : NSMixedState;
}

- (IBAction)copy:(id)sender
{
  NSPasteboard *pboard = [NSPasteboard generalPasteboard];

  [pboard clearContents];
  if (![pboard writeObjects:[self selectedImages]])
    NSLog(@"failed to write to pasteboard!");
}

- (IBAction)cut:(id)sender
{
  [self copy:sender];
  [self delete:sender];
}

- (IBAction)delete:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)toggleDeletedAction:(id)sender
{
  [self foreachSelectedImage:^(PDImage *image) {
    image.deleted = !image.deleted;
  }];
}

- (NSInteger)deletedState
{
  __block BOOL all_set = YES, all_clear = YES;

  [self foreachSelectedImage:^(PDImage *image) {
    if (image.deleted)
      all_clear = NO;
    else
      all_set = NO;
  }];

  return all_set ? NSOnState : all_clear ? NSOffState : NSMixedState;
}

- (IBAction)toggleRawAction:(id)sender
{
  [self foreachSelectedImage:^(PDImage *image) {
    image.usesRAW = !image.usesRAW;
  }];
}

- (NSInteger)rawState
{
  __block BOOL all_set = YES, all_clear = YES;

  [self foreachSelectedImage:^(PDImage *image) {
    if (image.usesRAW)
      all_clear = NO;
    else
      all_set = NO;
  }];

  return all_set ? NSOnState : all_clear ? NSOffState : NSMixedState;
}

- (BOOL)isToggleRawSupported
{
  __block BOOL supported = NO;

  [self foreachSelectedImage:^(PDImage *image) {
    if ([image supportsUsesRAW:!image.usesRAW])
      supported = YES;
  }];

  return supported;
}

- (IBAction)zoomIn:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [[self viewControllerWithClass:[PDImageViewController class]]
       performVoidSelector:_cmd withObject:sender];
    }
}

- (IBAction)zoomOut:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [[self viewControllerWithClass:[PDImageViewController class]]
       performVoidSelector:_cmd withObject:sender];
    }
}

- (IBAction)zoomActualSize:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [[self viewControllerWithClass:[PDImageViewController class]]
       performVoidSelector:_cmd withObject:sender];
    }
}

- (IBAction)zoomToFill:(id)sender
{
  if (_contentMode == PDContentMode_Image)
    {
      [[self viewControllerWithClass:[PDImageViewController class]]
       performVoidSelector:_cmd withObject:sender];
    }
}

- (void)rotateUsingMap:(const int *)map
{
  [self foreachSelectedImage:^(PDImage *image) {
    int orientation = image.orientation;
    if (orientation >= 1 && orientation <= 8)
      {
	orientation = map[orientation-1];
	[image setImageProperty:@(orientation) forKey:PDImage_Orientation];
      }
  }];
}

/* FIXME: these two tables haven't been verified for the flipped
   orientations, only for the plain 90 degree rotations. */

static const int rotate_left_map[8] = {8, 5, 6, 7, 4, 1, 2, 3};
static const int rotate_right_map[8] = {6, 7, 8, 5, 2, 3, 4, 1};

- (IBAction)rotateLeft:(id)sender
{
  [self rotateUsingMap:rotate_left_map];
}

- (IBAction)rotateRight:(id)sender
{
  [self rotateUsingMap:rotate_right_map];
}

- (IBAction)addLibraryAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)newFolderAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)newAlbumAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)newSmartAlbumAction:(id)sender
{
  NSPredicate *pred = self.predicatePanelController.predicate;
  if (pred == nil)
    return;

  NSString *format = pred.predicateFormat;

  [(PDLibraryViewController *)[self viewControllerWithClass:
   [PDLibraryViewController class]] addSmartAlbum:format predicate:pred];
}

- (IBAction)importAction:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (IBAction)emptyTrashAction:(id)sender
{
  NSMutableArray *images = [NSMutableArray array];

  [self foreachImage:^
    (PDImage *image, BOOL *stop)
    {
      if (image.deleted)
	[images addObject:image];
    }];

  if (images.count != 0)
    {
      [PDImageLibrary removeImages:images];

      NSArray *removed = [images filteredArray:^BOOL (id obj) {
	return ((PDImage *)obj).removed;}];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDTrashWasEmptied object:self
       userInfo:@{@"imagesRemoved": removed}];
    }
}

- (BOOL)isTrashEmpty
{
  return [self foreachImage:^(PDImage *image, BOOL *stop) {
    if (image.deleted)
      *stop = YES;
  }];
}

- (IBAction)reloadLibraries:(id)sender
{
  [[self viewControllerWithClass:[PDLibraryViewController class]]
   performVoidSelector:_cmd withObject:sender];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
  SEL sel = anItem.action;

  if (sel == @selector(zoomIn:)
      || sel == @selector(zoomOut:)
      || sel == @selector(zoomActualSize:)
      || sel == @selector(zoomToFill:))
    {
      return (_contentMode == PDContentMode_Image
	      && _primarySelectionIndex >= 0);
    }

  if (sel == @selector(delete:)
      || sel == @selector(setImageRatingAction:)
      || sel == @selector(addImageRatingAction:)
      || sel == @selector(toggleFlaggedAction:)
      || sel == @selector(toggleHiddenAction:)
      || sel == @selector(rotateLeft:)
      || sel == @selector(rotateRight:))
    {
      return _selectedImageIndexes.count != 0;
    }

  if (sel == @selector(toggleRawAction:))
    {
      return self.toggleRawSupported;
    }

  if (sel == @selector(emptyTrashAction:))
    {
      return !self.trashEmpty;
    }

  return YES;
}

// NSSplitViewDelegate methods

- (CGFloat)splitView:(PDSplitView *)view minimumSizeOfSubview:(NSView *)subview
{
  if (subview == _sidebarView.superview)
    return 250;
  else
    return 500;
}

- (BOOL)splitView:(NSSplitView *)view canCollapseSubview:(NSView *)subview
{
  return YES;
}

- (BOOL)splitView:(NSSplitView *)view shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)idx
{
  return YES;
}

- (CGFloat)splitView:(NSSplitView *)view constrainMinCoordinate:(CGFloat)p
    ofSubviewAt:(NSInteger)idx
{
  NSView *subview = view.subviews[idx];
  CGFloat min_size = [(PDSplitView *)view minimumSizeOfSubview:subview];

  return p + min_size;
}

- (CGFloat)splitView:(NSSplitView *)view constrainMaxCoordinate:(CGFloat)p
    ofSubviewAt:(NSInteger)idx
{
  NSView *subview = view.subviews[idx+1];
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
