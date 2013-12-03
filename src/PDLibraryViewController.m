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
#import "PDImage.h"
#import "PDImageTextCell.h"
#import "PDLibraryDirectory.h"
#import "PDLibraryItem.h"
#import "PDWindowController.h"

NSString *const PDLibrarySelectionDidChange = @"PDLibrarySelectionDidChange";

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

  _itemViewState = [[NSMapTable strongToStrongObjectsMapTable] retain];
  
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

  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(libraryItemSubimagesDidChange:)
   name:PDLibraryItemSubimagesDidChange object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(imageViewOptionsDidChange:)
   name:PDImagePredicateDidChange object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(imageViewOptionsDidChange:)
   name:PDImageSortOptionsDidChange object:nil];

  [[_searchField cell] setBackgroundColor:[NSColor grayColor]];

  for (NSTableColumn *col in [_outlineView tableColumns])
    [[col dataCell] setVerticallyCentered:YES];
}

- (NSView *)initialFirstResponder
{
  return _outlineView;
}

- (void)updateImageList
{
  NSIndexSet *sel = [_outlineView selectedRowIndexes];

  if ([sel count] == 0)
    [_controller setImageList:[NSArray array]];
  else
    {
      NSMutableArray *array = [NSMutableArray array];
      NSDictionary *viewState = nil;

      for (NSInteger row = [sel firstIndex];
	   row != NSNotFound; row = [sel indexGreaterThanIndex:row])
	{
	  PDLibraryItem *item = [_outlineView itemAtRow:row];

	  if (viewState == nil)
	    viewState = [_itemViewState objectForKey:item];

	  [array addObjectsFromArray:[item subimages]];
	}

      int sortKey = PDImageCompare_Date;
      BOOL sortRev = YES;
      NSPredicate *pred = nil;

      if (viewState != nil)
	{
	  NSString *key = [viewState objectForKey:@"imageSortKey"];
	  NSNumber *reversed = [viewState objectForKey:@"imageSortReversed"];
	  NSString *predicate = [viewState objectForKey:@"imagePredicate"];

	  if (key != nil)
	    sortKey = [PDImage imageCompareKeyFromString:key];
	  if (reversed != nil)
	    sortRev = [reversed boolValue];
	  if (predicate != nil)
	    pred = [_controller imagePredicateWithFormat:predicate];
	}

      /* Install sort/filter options before modifying the image list,
	 so that they only get applied once. */

      [_controller setImageSortKey:sortKey];
      [_controller setImageSortReversed:sortRev];
      [_controller setImagePredicate:pred];

      [_controller setImageList:array];
    }
}

- (void)libraryItemSubimagesDidChange:(NSNotification *)note
{
  PDLibraryItem *item = [note object];
  NSIndexSet *sel = [_outlineView selectedRowIndexes];
  BOOL selected = NO;

  while (item != nil)
    {
      [_outlineView reloadItem:item];

      NSInteger row = [_outlineView rowForItem:item];
      if (row != NSNotFound && [sel containsIndex:row])
	selected = YES;

      item = [item parent];
    }

  if (selected)
    [self updateImageList];
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

      if ([item parent] == nil
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

  [self updateImageList];
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

- (void)imageViewOptionsDidChange:(NSNotification *)note
{
  NSIndexSet *sel = [_outlineView selectedRowIndexes];

  int key = [_controller imageSortKey];
  BOOL rev = [_controller isImageSortReversed];
  NSPredicate *pred = [_controller imagePredicate];

  NSMutableDictionary *opts = [NSMutableDictionary dictionary];

  if (key != PDImageCompare_Date)
    [opts setObject:[PDImage imageCompareKeyString:key] forKey:@"imageSortKey"];
  if (!rev)
    [opts setObject:[NSNumber numberWithBool:rev] forKey:@"imageSortReversed"];
  if (pred != nil != 0)
    [opts setObject:[pred predicateFormat] forKey:@"imagePredicate"];

  if ([opts count] == 0)
    opts = nil;

  NSInteger idx;
  for (idx = [sel firstIndex]; idx != NSNotFound;
       idx = [sel indexGreaterThanIndex:idx])
    {
      PDLibraryItem *item = [_outlineView itemAtRow:idx];
      if (opts != nil)
	[_itemViewState setObject:opts forKey:item];
      else
	[_itemViewState removeObjectForKey:item];
    }
}

static NSArray *
path_for_item(PDLibraryItem *item)
{
  struct node
    {
      struct node *next;
      NSString *ident;
    };

  struct node *lst = NULL;

  for (; item != nil; item = [item parent])
    {
      NSString *ident = [item identifier];
      if ([ident length] == 0)
	break;
      struct node *node = alloca(sizeof(*node));
      node->next = lst;
      lst = node;
      node->ident = ident;
    }

  if (item != nil)
    return nil;

  NSMutableArray *path = [NSMutableArray array];

  for (; lst != NULL; lst = lst->next)
    [path addObject:lst->ident];

  return path;
}

static PDLibraryItem *
item_for_path(NSArray *items, NSArray *path)
{
  PDLibraryItem *item = nil;

  for (NSString *ident in path)
    {
      BOOL found = NO;

      for (PDLibraryItem *subitem in items)
	{
	  NSString *ident2 = [subitem identifier];

	  if ([ident isEqualToString:ident2])
	    {
	      found = YES;
	      item = subitem;
	      items = [subitem subitems];
	      break;
	    }
	}

      if (!found)
	return nil;
    }

  return item;
}

- (void)addItem:(PDLibraryItem *)item viewState:(NSMutableDictionary *)dict
{
  NSString *ident = [item identifier];
  if ([ident length] == 0)
    return;

  BOOL expanded = [_outlineView isItemExpanded:item];
  NSDictionary *opts = [_itemViewState objectForKey:item];

  NSMutableDictionary *subdict = [NSMutableDictionary dictionary];

  for (PDLibraryItem *subitem in [item subitems])
    [self addItem:subitem viewState:subdict];

  if (expanded || [opts count] != 0 || [subdict count] != 0)
    {
      if (opts == nil)
	opts = @{};

      NSDictionary *tem = @{
	@"expanded": @(expanded),
	@"viewState": opts,
	@"subitems": subdict
      };

      [dict setObject:tem forKey:ident];
    }
}

- (void)applyItem:(PDLibraryItem *)item viewState:(NSDictionary *)dict
{
  NSString *ident = [item identifier];
  if ([ident length] == 0)
    return;

  NSDictionary *state = [dict objectForKey:ident];
  if (state == nil)
    return;

  if ([[state objectForKey:@"expanded"] boolValue])
    [_outlineView expandItem:item];

  NSDictionary *view_state = [state objectForKey:@"viewState"];
  if ([view_state count] != 0)
    [_itemViewState setObject:view_state forKey:item];

  NSDictionary *sub_state = [state objectForKey:@"subitems"];
  if (sub_state != nil)
    {
      for (PDLibraryItem *subitem in [item subitems])
	[self applyItem:subitem viewState:sub_state];
    }
}

- (NSDictionary *)savedViewState
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  for (PDLibraryItem *item in _items)
    [self addItem:item viewState:dict];

  NSMutableArray *selected = [NSMutableArray array];
  NSIndexSet *sel = [_outlineView selectedRowIndexes];
  NSInteger idx;

  for (idx = [sel firstIndex]; idx != NSNotFound;
       idx = [sel indexGreaterThanIndex:idx])
    {
      NSArray *path = path_for_item([_outlineView itemAtRow:idx]);
      if (path != nil)
	[selected addObject:path];
    }

  return [NSDictionary dictionaryWithObjectsAndKeys:
	  dict, @"itemState",
	  selected, @"selectedItems",
	  nil];
}

- (void)applySavedViewState:(NSDictionary *)state
{
  NSDictionary *item_state = [state objectForKey:@"itemState"];

  if (item_state != nil)
    {
      for (PDLibraryItem *item in _items)
	[self applyItem:item viewState:item_state];
    }

  NSArray *selected = [state objectForKey:@"selectedItems"];
  NSMutableIndexSet *sel = [NSMutableIndexSet indexSet];

  for (NSArray *path in selected)
    {
      PDLibraryItem *item = item_for_path(_items, path);
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

  [self updateImageList];
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
  [self updateImageList];

  if ([[_controller filteredImageList] count] > 0
      && [[_controller selectedImageIndexes] count] == 0)
    {
      [_controller setSelectedImageIndexes:[NSIndexSet indexSetWithIndex:0]];
    }

  [[NSNotificationCenter defaultCenter]
   postNotificationName:PDLibrarySelectionDidChange object:_controller];
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
