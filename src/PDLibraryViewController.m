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
#import "PDLibraryGroup.h"
#import "PDLibraryQuery.h"
#import "PDWindowController.h"

#import "PXSourceList.h"

#define MAX_TITLE_STRINGS 6

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

  [_foldersGroup addSubitem:item];

  [item release];
}

- (void)addQueryItem:(NSDictionary *)dict
{
  NSString *name = [dict objectForKey:@"name"];
  NSString *format = [dict objectForKey:@"predicate"];
  NSPredicate *pred = format != nil ? [_controller imagePredicateWithFormat:
				       format] : nil;

  PDLibraryQuery *item = [[PDLibraryQuery alloc] init];

  [item setName:name];
  [item setPredicate:pred];

  [_smartFoldersGroup addSubitem:item];

  [item release];
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  _items = [[NSMutableArray alloc] init];

  _folders = [[[NSUserDefaults standardUserDefaults]
	       arrayForKey:@"PDLibraryDirectories"] mutableCopy];
  if (_folders == nil)
    _folders = [[NSMutableArray alloc] init];

  _foldersGroup = [[PDLibraryGroup alloc] init];
  [_foldersGroup setName:@"Folders"];
  [_items addObject:_foldersGroup];
  [_foldersGroup release];

  _smartFolders = [[[NSUserDefaults standardUserDefaults]
		    arrayForKey:@"PDLibraryQueries"] mutableCopy];
  if (_smartFolders == nil)
    _smartFolders = [[NSMutableArray alloc] init];

  _smartFoldersGroup = [[PDLibraryGroup alloc] init];
  [_smartFoldersGroup setName:@"Smart Folders"];
  [_items addObject:_smartFoldersGroup];
  [_smartFoldersGroup release];

  _itemViewState = [[NSMapTable strongToStrongObjectsMapTable] retain];
  
  for (NSString *dir in _folders)
    [self addDirectoryItem:dir];

  for (NSDictionary *dict in _smartFolders)
    [self addQueryItem:dict];

  return self;
}

- (void)dealloc
{
  [_outlineView setDataSource:nil];
  [_outlineView setDelegate:nil];

  [_items release];
  [_itemViewState release];

  [_folders release];
  [_smartFolders release];

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
   name:PDImagePredicateDidChange object:_controller];
  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(imageViewOptionsDidChange:)
   name:PDImageSortOptionsDidChange object:_controller];
  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(showsHiddenImagesDidChange:)
   name:PDShowsHiddenImagesDidChange object:_controller];

  [[_searchField cell] setBackgroundColor:[NSColor grayColor]];

  for (NSTableColumn *col in [_outlineView tableColumns])
    [[col dataCell] setVerticallyCentered:YES];

  [_outlineView expandItem:_foldersGroup];
  [_outlineView expandItem:_smartFoldersGroup];
}

- (NSView *)initialFirstResponder
{
  return _outlineView;
}

- (NSArray *)allImages
{
  return [_foldersGroup subimages];
}

- (void)updateImageList
{
  NSIndexSet *sel = [_outlineView selectedRowIndexes];

  if ([sel count] == 0)
    {
      [_controller setImageListTitle:@""];
      [_controller setImageList:[NSArray array]];
    }
  else
    {
      NSMutableArray *array = [NSMutableArray array];
      NSMutableString *title = [NSMutableString string];
      BOOL showsHidden = [_controller showsHiddenImages];
      NSInteger count = 0;
      NSDictionary *viewState = nil;

      for (NSInteger row = [sel firstIndex];
	   row != NSNotFound; row = [sel indexGreaterThanIndex:row])
	{
	  PDLibraryItem *item = [_outlineView itemAtRow:row];

	  if (viewState == nil)
	    viewState = [_itemViewState objectForKey:item];

	  NSArray *subimages = [item subimages];
	  if ([subimages count] == 0)
	    continue;

	  BOOL none = NO;

	  if (showsHidden)
	    {
	      [array addObjectsFromArray:subimages];
	    }
	  else
	    {
	      none = YES;
	      for (PDImage *im in subimages)
		{
		  if ([im isHidden])
		    continue;
		  [array addObject:im];
		  none = NO;
		}
	    }

	  if (!none)
	    {
	      NSString *item_title = [item titleString];
	      if ([item_title length] != 0)
		{
		  if (count < MAX_TITLE_STRINGS)
		    {
		      if ([title length] != 0)
			[title appendString:@" & "];
		      [title appendString:item_title];
		    }
		  else if (count == MAX_TITLE_STRINGS)
		    {
		      [title appendString:@" & "];
		      unichar c = 0x2026;	/* HORIZONTAL ELLIPSIS */
		      [title appendString:
		       [NSString stringWithCharacters:&c length:1]];
		    }
		  count++;
		}
	    }
	}

      int sortKey = PDImageCompare_Date;
      BOOL sortRev = NO;
      NSPredicate *pred = nil;

      if (viewState != nil)
	{
	  NSString *key = [viewState objectForKey:@"imageSortKey"];
	  if (key != nil)
	    sortKey = [PDImage imageCompareKeyFromString:key];

	  sortRev = [[viewState objectForKey:@"imageSortReversed"] boolValue];

	  NSString *predicate = [viewState objectForKey:@"imagePredicate"];
	  if (predicate != nil)
	    pred = [_controller imagePredicateWithFormat:predicate];
	}

      /* Install sort/filter options before modifying the image list,
	 so that they only get applied once. */

      [_controller setImageSortKey:sortKey];
      [_controller setImageSortReversed:sortRev];
      [_controller setImagePredicate:pred];

      [_controller setImageListTitle:title];
      [_controller setImageList:array];
    }
}

- (NSInteger)imageListSizeFromItem:(PDLibraryItem *)item
{
  NSArray *subimages = [item subimages];
  if ([subimages count] == 0)
    return 0;

  BOOL showsHidden = [_controller showsHiddenImages];
  if (showsHidden)
    return [subimages count];

  NSInteger count = 0;

  for (PDImage *im in subimages)
    {
      if ([im isHidden])
	continue;
      count++;
    }

  return count;
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

  if (!selected)
    {
      NSInteger idx;
      for (idx = [sel firstIndex]; idx != NSNotFound;
	   idx = [sel indexGreaterThanIndex:idx])
	{
	  PDLibraryItem *item = [_outlineView itemAtRow:idx];
	  if ([item isKindOfClass:[PDLibraryQuery class]])
	    {
	      selected = YES;
	      break;
	    }
	}
    }

  if (selected)
    [self updateImageList];
}

- (void)showsHiddenImagesDidChange:(NSNotification *)note
{
  [self updateImageList];

  [_outlineView reloadData];
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

- (void)addSmartFolder:(NSString *)name predicate:(NSPredicate *)pred
{
  NSString *query = [pred predicateFormat];
  if (query == nil)
    query = @"";

  NSDictionary *dict = @{
    @"name": name,
    @"predicate": query
  };

  [_smartFolders addObject:dict];

  [self addQueryItem:dict];

  [[NSUserDefaults standardUserDefaults] setObject:_smartFolders
   forKey:@"PDLibraryQueries"];

  [_outlineView reloadItem:_smartFoldersGroup reloadChildren:YES];
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

      if ([item parent] != nil)
	continue;

      if ([item isKindOfClass:[PDLibraryDirectory class]])
	{
	  NSArray *subitems = [_foldersGroup subitems];
	  NSInteger idx = [subitems indexOfObjectIdenticalTo:item];
	  if (idx != NSNotFound)
	    {
	      [_folders removeObjectAtIndex:idx];
	      [_foldersGroup removeSubitem:[subitems objectAtIndex:idx]];
	      changed = YES;
	    }
	}
      else if ([item isKindOfClass:[PDLibraryQuery class]])
	{
	  NSArray *subitems = [_smartFoldersGroup subitems];
	  NSInteger idx = [subitems indexOfObjectIdenticalTo:item];
	  if (idx != NSNotFound)
	    {
	      [_smartFolders removeObjectAtIndex:idx];
	      [_smartFoldersGroup removeSubitem:[subitems objectAtIndex:idx]];
	      changed = YES;
	    }
	}
    }

  if (changed)
    {
      [[NSUserDefaults standardUserDefaults] setObject:_folders
       forKey:@"PDLibraryDirectories"];
      [[NSUserDefaults standardUserDefaults] setObject:_smartFolders
       forKey:@"PDLibraryQueries"];

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
  if (rev)
    [opts setObject:[NSNumber numberWithBool:rev] forKey:@"imageSortReversed"];
  if (pred != nil)
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

- (void)addItem:(PDLibraryItem *)item viewState:(NSMutableDictionary *)state
{
  NSString *ident = [item identifier];
  if ([ident length] == 0)
    return;

  BOOL expanded = [_outlineView isItemExpanded:item];
  NSDictionary *opts = [_itemViewState objectForKey:item];

  NSMutableDictionary *subdict = [[NSMutableDictionary alloc] init];

  for (PDLibraryItem *subitem in [item subitems])
    [self addItem:subitem viewState:subdict];

  NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

  if (expanded)
    [dict setObject:[NSNumber numberWithBool:YES] forKey:@"expanded"];
  if ([opts count] != 0)
    [dict setObject:opts forKey:@"viewState"];
  if ([subdict count] != 0)
    [dict setObject:subdict forKey:@"subitems"];

  [subdict release];

  if ([dict count] != 0)
    [state setObject:dict forKey:ident];

  [dict release];
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

// PXSourceListDataSource methods

- (NSUInteger)sourceList:(PXSourceList *)lst numberOfChildrenOfItem:(id)item
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

- (id)sourceList:(PXSourceList *)lst child:(NSUInteger)idx ofItem:(id)item
{
  NSArray *array = item == nil ? _items : [(PDLibraryItem *)item subitems];
  NSUInteger count = 0;

  for (PDLibraryItem *item in array)
    {
      if (![item isHidden] && count++ == idx)
       return item;
    }

  return nil;
}

- (id)sourceList:(PXSourceList *)lst objectValueForItem:(id)item
{
  return [(PDLibraryItem *)item titleString];
}

- (BOOL)sourceList:(PXSourceList *)lst isItemExpandable:(id)item
{
  return [(PDLibraryItem *)item isExpandable];
}

- (BOOL)sourceList:(PXSourceList *)lst itemHasBadge:(id)item
{
  return [(PDLibraryItem *)item hasBadge];
}

- (NSInteger)sourceList:(PXSourceList *)lst badgeValueForItem:(id)item
{
  if ([(PDLibraryItem *)item badgeValueIsNumberOfSubimages])
    return [self imageListSizeFromItem:item];
  else
    return [(PDLibraryItem *)item badgeValue];
}

- (BOOL)sourceList:(PXSourceList *)lst itemHasIcon:(id)item
{
  return [(PDLibraryItem *)item hasTitleImage];
}

- (NSImage*)sourceList:(PXSourceList *)lst iconForItem:(id)item
{
  return [(PDLibraryItem *)item titleImage];
}

// PXSourceListDelegate methods

- (CGFloat)sourceList:(PXSourceList *)lst heightOfRowByItem:(id)item
{
  if ([item isKindOfClass:[PDLibraryGroup class]])
    return 24;
  else
    return 22;
}

- (BOOL)sourceList:(PXSourceList *)lst shouldEditItem:(id)item
{
  return NO;
}

- (void)sourceListSelectionDidChange:(NSNotification *)note
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

@end
