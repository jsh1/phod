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

#import "PDAppKitExtensions.h"
#import "PDColor.h"
#import "PDImage.h"
#import "PDImageGridView.h"
#import "PDLibraryViewController.h"
#import "PDWindowController.h"

@implementation PDImageListViewController

@synthesize scrollView = _scrollView;
@synthesize gridView = _gridView;
@synthesize sortButton = _sortButton;
@synthesize sortMenu = _sortMenu;
@synthesize titleLabel = _titleLabel;
@synthesize searchField = _searchField;
@synthesize searchMenu = _searchMenu;
@synthesize predicateButton = _predicateButton;
@synthesize rotateLeftButton = _rotateLeftButton;
@synthesize rotateRightButton = _rotateRightButton;
@synthesize scaleSlider = _scaleSlider;

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
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imagePredicateDidChange:)
   name:PDImagePredicateDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(librarySelectionDidChange:)
   name:PDLibrarySelectionDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imagePropertyDidChange:)
   name:PDImagePropertyDidChange object:nil];

  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  _scrollView.backgroundColor = [PDColor imageGridBackgroundColor];

  /* This is so we update when the scroll view scrolls. */

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(gridViewBoundsDidChange:)
   name:NSViewBoundsDidChangeNotification object:_gridView.superview];

  /* This is so we update when the grid view changes size. */

  [_gridView setPostsFrameChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(gridViewBoundsDidChange:)
   name:NSViewFrameDidChangeNotification object:_gridView];

  [_sortButton selectItemWithTag:_controller.imageSortKey];

  _titleLabel.textColor = [PDColor controlTextColor];
  _titleLabel.stringValue = @"";

  [_searchField.cell setBackgroundColor:[NSColor grayColor]];

  _scaleSlider.doubleValue = _gridView.scale;
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
  return @{
    @"Scale": @(_scaleSlider.doubleValue)
  };
}

- (void)applySavedViewState:(NSDictionary *)state
{
  id value = state[@"Scale"];

  if (value != nil)
    {
      _scaleSlider.doubleValue = [value doubleValue];
      [self controlAction:_scaleSlider];
    }
}

- (void)imageListDidChange:(NSNotification *)note
{
  NSArray *images = _controller.filteredImageList;

  _gridView.images = images;

  _titleLabel.stringValue = _controller.imageListTitle;
}

- (void)selectionDidChange:(NSNotification *)note
{
  _gridView.primarySelection = _controller.primarySelectionIndex;
  _gridView.selection = _controller.selectedImageIndexes;

  BOOL enabled = _controller.selectedImageIndexes.count != 0;
  _rotateLeftButton.enabled = enabled;
  _rotateRightButton.enabled = enabled;

  [_sortButton selectItemWithTag:_controller.imageSortKey];
}

- (void)librarySelectionDidChange:(NSNotification *)note
{
  [_gridView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
}

- (void)imagePredicateDidChange:(NSNotification *)note
{
  NSString *str = _controller.imagePredicate.predicateFormat;
  if (str.length == 0)
    str = @"";
  _searchField.stringValue = str;
}

- (void)gridViewBoundsDidChange:(NSNotification *)note
{
  _gridView.needsDisplay = YES;
}

- (void)imagePropertyDidChange:(NSNotification *)note
{
  PDImage *image = note.object;
  if (![_gridView imageMayBeVisible:image])
    return;

  static NSSet *keys;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    keys = [[NSSet alloc] initWithObjects:PDImage_Title, PDImage_Name,
	    PDImage_Rating, PDImage_Flagged, PDImage_Hidden,
	    PDImage_Orientation, PDImage_ActiveType, nil];
  });

  /* FIXME: only update the layer of the image that has changed? */

  NSString *key = note.userInfo[@"key"];
  if ([keys containsObject:key])
    _gridView.needsDisplay = YES;
}

- (BOOL)displaysMetadata
{
  return _gridView.displaysMetadata;
}

- (void)setDisplaysMetadata:(BOOL)x
{
  if (_gridView == nil)
    [self loadView];

  _gridView.displaysMetadata = x;
}

- (IBAction)toggleMetadata:(id)sender
{
  self.displaysMetadata = !self.displaysMetadata;
  [_gridView scrollToPrimaryAnimated:NO];
}

- (IBAction)sortKeyAction:(NSControl *)sender
{
  int key = sender.tag;

  if (_controller.imageSortKey != key)
    {
      _controller.imageSortKey = key;
      [_controller rebuildImageList:0];
      [_sortButton selectItemWithTag:key];
    }
}

- (IBAction)sortOrderAction:(NSControl *)sender
{
  BOOL reversed = sender.tag != 0;

  if (_controller.imageSortReversed != reversed)
    {
      _controller.imageSortReversed = reversed;
      [_controller rebuildImageList:0];
      [_sortButton selectItemWithTag:[_controller imageSortKey]];
    }
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _scaleSlider)
    {
      _gridView.scale = [sender doubleValue];
    }
  else if (sender == _searchField)
    {
      NSString *str = [_searchField.stringValue
		       stringByTrimmingCharactersInSet:
		       [NSCharacterSet whitespaceCharacterSet]];

      if (str.length != 0)
	{
	  NSPredicate *pred = [_controller imagePredicateWithFormat:str];

	  /* If parsing a non-null string fails, we don't want to
	     update the in-use predicate, that would probably set the
	     string being edited to the empty string. */

	  if (pred != nil)
	    {
	      _controller.imagePredicate = pred;
	      [_controller rebuildImageList:0];
	    }
	}
      else if (_controller.imagePredicate != nil)
	{
	  _controller.imagePredicate = nil;
	  [_controller rebuildImageList:0];
	}
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)e
{
  return [_searchMenu performKeyEquivalent:e];
}

// NSMenuDelegate methods

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu == _sortMenu)
    {
      int key = _controller.imageSortKey;
      BOOL reversed = _controller.imageSortReversed;

      for (NSMenuItem *item in menu.itemArray)
	{
	  SEL sel = item.action;
	  if (sel == @selector(sortKeyAction:))
	    item.state = item.tag == key;
	  else if (sel == @selector(sortOrderAction:))
	    item.state = item.tag == reversed;
	}
    }
}

// CALayerDelegate methods

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)key
{
  return [NSNull null];
}

@end
