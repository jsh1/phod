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
#import "PDImage.h"
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
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imagePredicateDidChange:)
   name:PDImagePredicateDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imagePropertyDidChange:)
   name:PDImagePropertyDidChange object:nil];

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

  [_sortButton selectItemWithTag:[_controller imageSortKey]];

  [_titleLabel setTextColor:[PDColor controlTextColor]];
  [_titleLabel setStringValue:@""];

  [[_searchField cell] setBackgroundColor:[NSColor grayColor]];

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
  NSArray *images = [_controller filteredImageList];

  [_gridView setImages:images];
  [_gridView scrollPoint:NSZeroPoint];

  if ([images count] != 0)
    {
      NSMutableSet *paths = [NSMutableSet set];

      for (PDImage *image in images)
	[paths addObject:[image lastLibraryPathComponent]];

      NSMutableString *str = [NSMutableString string];

      for (NSString *path in [[paths allObjects]
			      sortedArrayUsingSelector:@selector(compare:)])
	{
	  path = [[path lastPathComponent]
		  stringByReplacingOccurrencesOfString:@":" withString:@"/"];
	  if ([str length] != 0)
	    [str appendString:@" & "];
	  [str appendString:path];
	}

      [_titleLabel setStringValue:str];
    }
  else
    [_titleLabel setStringValue:@""];
}

- (void)selectionDidChange:(NSNotification *)note
{
  [_gridView setPrimarySelection:[_controller primarySelectionIndex]];
  [_gridView setSelection:[_controller selectedImageIndexes]];

  BOOL enabled = [[_controller selectedImageIndexes] count] != 0;
  [_rotateLeftButton setEnabled:enabled];
  [_rotateRightButton setEnabled:enabled];

  [_sortButton selectItemWithTag:[_controller imageSortKey]];
}

- (void)imagePredicateDidChange:(NSNotification *)note
{
  NSString *str = [[_controller imagePredicate] predicateFormat];
  if ([str length] == 0)
    str = @"";
  [_searchField setStringValue:str];
}

- (void)gridViewBoundsDidChange:(NSNotification *)note
{
  [_gridView setNeedsDisplay:YES];
}

- (void)imagePropertyDidChange:(NSNotification *)note
{
  PDImage *image = [note object];
  if (![_gridView imageMayBeVisible:image])
    return;

  NSString *key = [[note userInfo] objectForKey:@"key"];
  if (![key isEqualToString:PDImage_Title]
      && ![key isEqualToString:PDImage_Name]
      && ![key isEqualToString:PDImage_Rating]
      && ![key isEqualToString:PDImage_Flagged]
      && ![key isEqualToString:PDImage_Orientation])
    return;

  /* FIXME: only update the layer of the image that has changed? */

  [_gridView setNeedsDisplay:YES];
}

- (BOOL)displaysMetadata
{
  return [_gridView displaysMetadata];
}

- (void)setDisplaysMetadata:(BOOL)x
{
  if (_gridView == nil)
    [self loadView];

  [_gridView setDisplaysMetadata:x];
}

- (IBAction)toggleMetadata:(id)sender
{
  [self setDisplaysMetadata:![self displaysMetadata]];
  [_gridView scrollToPrimaryAnimated:NO];
}

- (IBAction)sortKeyAction:(id)sender
{
  int key = [sender tag];

  if ([_controller imageSortKey] != key)
    {
      [_controller setImageSortKey:key];
      [_controller rebuildImageList];
      [_sortButton selectItemWithTag:key];
    }
}

- (IBAction)sortOrderAction:(id)sender
{
  BOOL reversed = [sender tag] != 0;

  if ([_controller isImageSortReversed] != reversed)
    {
      [_controller setImageSortReversed:reversed];
      [_controller rebuildImageList];
      [_sortButton selectItemWithTag:[_controller imageSortKey]];
    }
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _scaleSlider)
    {
      [_gridView setScale:[sender doubleValue]];
    }
  else if (sender == _searchField)
    {
      NSString *str = [_searchField stringValue];
      [_controller setImagePredicate:
       [_controller imagePredicateWithFormat:str]];
      [_controller rebuildImageList];
    }
}

// NSMenuDelegate methods

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu == _sortMenu)
    {
      int key = [_controller imageSortKey];
      BOOL reversed = [_controller isImageSortReversed];

      for (NSMenuItem *item in [menu itemArray])
	{
	  SEL sel = [item action];
	  if (sel == @selector(sortKeyAction:))
	    [item setState:[item tag] == key];
	  else if (sel == @selector(sortOrderAction:))
	    [item setState:[item tag] == reversed];
	}
    }
}

// CALayerDelegate methods

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)key
{
  return [NSNull null];
}

@end
