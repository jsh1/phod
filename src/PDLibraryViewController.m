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

#import "PDLibraryViewController.h"

#import "PDAppKitExtensions.h"
#import "PDImageTextCell.h"
#import "PDLibraryDirectory.h"
#import "PDLibraryItem.h"
#import "PDWindowController.h"

@implementation PDLibraryViewController

+ (NSString *)viewNibName
{
  return @"PDLibraryView";
}

- (void)addDirectoryItem:(NSString *)dir
{
  PDLibraryDirectory *item
    = [[PDLibraryDirectory alloc] initWithLibraryPath:
       [dir stringByExpandingTildeInPath] directory:@""];

  [item setTitleImageName:PDImage_GenericHardDisk];
  [_items addObject:item];
  [item release];
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  _folders = [[[NSUserDefaults standardUserDefaults]
	       arrayForKey:@"PDLibraryDirectories"] mutableCopy];

  _items = [[NSMutableArray alloc] init];
  
  for (NSString *dir in _folders)
    [self addDirectoryItem:dir];

  return self;
}

- (void)dealloc
{
  [_outlineView setDataSource:nil];
  [_outlineView setDelegate:nil];

  [_items release];

  [super dealloc];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [[_searchField cell] setBackgroundColor:[NSColor grayColor]];

  for (NSTableColumn *col in [_outlineView tableColumns])
    [[col dataCell] setVerticallyCentered:YES];
}

- (NSView *)initialFirstResponder
{
  return _outlineView;
}

- (IBAction)addFolderAction:(id)sender
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];

  [panel setCanChooseDirectories:YES];
  [panel setCanChooseFiles:NO];
  [panel setAllowsMultipleSelection:YES];
  [panel setPrompt:@"Add Folder"];
  [panel setTitle:@"Select folder to add to library"];

  [panel beginWithCompletionHandler:
   ^(NSInteger status) {
     if (status == NSFileHandlingPanelOKButton)
       {
	 BOOL changed = NO;
	 NSArray *urls = [panel URLs];

	 for (NSURL *url in urls)
	   {
	     if (![url isFileURL])
	       continue;

	     NSString *dir = [[url path] stringByAbbreviatingWithTildeInPath];
	     if ([_folders containsObject:dir])
	       continue;

	     [_folders addObject:dir];
	     [self addDirectoryItem:dir];
	     changed = YES;
	   }

	 if (changed)
	   {
	     [[NSUserDefaults standardUserDefaults] setObject:_folders
	      forKey:@"PDLibraryDirectories"];

	     [_outlineView reloadData];
	   }
       }
   }];
}

- (IBAction)removeFolderAction:(id)sender
{
  BOOL changed = NO;
  NSIndexSet *sel = [_outlineView selectedRowIndexes];
  NSInteger idx;

  for (idx = [sel lastIndex]; idx != NSNotFound;
       idx = [sel indexLessThanIndex:idx])
    {
      PDLibraryItem *item = [_outlineView itemAtRow:idx];

      if ([_outlineView parentForItem:item] == nil
	  && [item isKindOfClass:[PDLibraryDirectory class]])
	{
	  NSInteger idx = [_items indexOfObjectIdenticalTo:item];
	  if (idx != NSNotFound)
	    {
	      [_folders removeObjectAtIndex:idx];
	      [_items removeObjectAtIndex:idx];
	      changed = YES;
	    }
	}
    }

  if (changed)
    {
      [[NSUserDefaults standardUserDefaults] setObject:_folders
       forKey:@"PDLibraryDirectories"];

      [_outlineView reloadData];
    }

  [self outlineViewSelectionDidChange:nil];
}

- (IBAction)searchAction:(id)sender
{
  NSString *str = [_searchField stringValue];

  for (PDLibraryItem *item in _items)
    {
      if ([str length] != 0)
	[item applySearchString:str];
      else
	[item resetSearchState];
    }

  [_outlineView reloadData];
}

- (IBAction)controlAction:(id)sender
{
}

static void
add_expanded_items(PDLibraryViewController *self,
		   NSMutableDictionary *expanded, NSArray *items)
{
  for (PDLibraryItem *item in items)
    {
      if ([self->_outlineView isItemExpanded:item])
	{
	  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	  add_expanded_items(self, dict, [item subitems]);
	  [expanded setObject:dict forKey:[item identifier]];
	}
    }
}

static void
expand_expanded_items(PDLibraryViewController *self,
		      NSDictionary *expanded, NSArray *items)
{
  for (PDLibraryItem *item in items)
    {
      NSString *ident = [item identifier];

      if ([ident length] != 0)
	{
	  NSDictionary *dict = [expanded objectForKey:ident];

	  if (dict != nil)
	    {
	      [self->_outlineView expandItem:item];
	      expand_expanded_items(self, dict, [item subitems]);
	    }
	}
    }
}

static BOOL
add_selection_path(PDLibraryViewController *self,
		   NSMutableArray *path, PDLibraryItem *item)
{
  NSString *ident = [item identifier];
  if ([ident length] == 0)
    return NO;

  PDLibraryItem *parent = [self->_outlineView parentForItem:item];

  if (parent != nil)
    {
      if (!add_selection_path(self, path, parent))
	return NO;
    }

  [path addObject:ident];
  return YES;
}

static PDLibraryItem *
item_for_selection_path(PDLibraryViewController *self,
			NSArray *path, NSInteger idx, NSArray *items)
{
  NSInteger count = [path count];
  if (idx >= count)
    return nil;

  NSString *ident = [path objectAtIndex:idx];

  for (PDLibraryItem *item in items)
    {
      if (![[item identifier] isEqualToString:ident])
	continue;

      if (idx + 1 < count)
	return item_for_selection_path(self, path, idx + 1, [item subitems]);
      else
	return item;
    }

  return nil;
}

- (NSDictionary *)savedViewState
{
  NSMutableDictionary *expanded = [NSMutableDictionary dictionary];

  add_expanded_items(self, expanded, _items);

  NSMutableArray *selected = [NSMutableArray array];
  NSIndexSet *sel = [_outlineView selectedRowIndexes];
  NSInteger idx;

  for (idx = [sel firstIndex]; idx != NSNotFound;
       idx = [sel indexGreaterThanIndex:idx])
    {
      PDLibraryItem *item = [_outlineView itemAtRow:idx];
      NSMutableArray *path = [NSMutableArray array];
      if (add_selection_path(self, path, item))
	[selected addObject:path];
    }

  return [NSDictionary dictionaryWithObjectsAndKeys:
	  expanded, @"expandedItems",
	  selected, @"selectedItems",
	  nil];
}

- (void)applySavedViewState:(NSDictionary *)state
{
  NSDictionary *expanded = [state objectForKey:@"expandedItems"];

  if (expanded != nil)
    expand_expanded_items(self, expanded, _items);

  NSArray *selected = [state objectForKey:@"selectedItems"];
  NSMutableIndexSet *sel = [NSMutableIndexSet indexSet];

  for (NSArray *path in selected)
    {
      PDLibraryItem *item = item_for_selection_path(self, path, 0, _items);
      if (item != nil)
	{
	  NSInteger row = [_outlineView rowForItem:item];
	  if (row != NSNotFound)
	    [sel addIndex:row];
	}
    }

  if ([sel count] != 0)
    {
      [_outlineView selectRowIndexes:sel byExtendingSelection:NO];
      [_outlineView scrollRowToVisible:[sel firstIndex]];
    }

  [self outlineViewSelectionDidChange:nil];
}

// NSOutlineViewDataSource methods

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
  NSArray *array = item == nil ? _items : [(PDLibraryItem *)item subitems];
  NSInteger count = 0;

  for (PDLibraryItem *item in array)
    {
      if (![item isHidden])
	count++;
    }

  return count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
  NSArray *array = item == nil ? _items : [(PDLibraryItem *)item subitems];
  NSInteger count = 0;

  for (PDLibraryItem *item in array)
    {
      if (![item isHidden] && count++ == index)
	return item;
    }

  return nil;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
  return [(PDLibraryItem *)item isExpandable];
}

- (id)outlineView:(NSOutlineView *)ov
    objectValueForTableColumn:(NSTableColumn *)col byItem:(id)item
{
  NSString *ident = [col identifier];

  if ([ident isEqualToString:@"name"])
    return [item titleString];
  else if ([ident isEqualToString:@"badge"])
    return [item hasBadge] ? [NSString stringWithFormat:@"%d", (int)[item badgeValue]] : nil;

  return nil;
}

- (void)outlineView:(NSOutlineView *)ov setObjectValue:(id)object
    forTableColumn:(NSTableColumn *)col byItem:(id)item
{
}

// NSOutlineViewDelegate methods

- (void)outlineView:(NSOutlineView *)ov willDisplayCell:(id)cell
    forTableColumn:(NSTableColumn *)col item:(id)item
{
  NSString *ident = [col identifier];

  if ([ident isEqualToString:@"name"])
    {
      [(PDImageTextCell *)cell setImage:[item titleImage]];
    }
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
  NSIndexSet *sel;
  NSMutableArray *array;

  sel = [_outlineView selectedRowIndexes];
  if (sel == nil)
    [_controller setImageList:[NSArray array]];
  else
    {
      array = [NSMutableArray array];

      for (NSInteger row = [sel firstIndex];
	   row != NSNotFound; row = [sel indexGreaterThanIndex:row])
	{
	  [array addObjectsFromArray:[[_outlineView itemAtRow:row] subimages]];
	}

      [_controller setImageList:array];

      if ([array count] > 0)
	[_controller setSelectedImageIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
}

- (NSString *)outlineView:(NSOutlineView *)ov toolTipForCell:(NSCell *)cell
    rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)col item:(id)item
    mouseLocation:(NSPoint)p
{
  if ([[col identifier] isEqualToString:@"name"]
      && [item isKindOfClass:[PDLibraryDirectory class]])
    {
      return [[(PDLibraryDirectory *)item path]
	      stringByAbbreviatingWithTildeInPath];
    }

  return nil;
}

@end
