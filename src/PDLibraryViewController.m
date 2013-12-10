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
#import "PDImageLibrary.h"
#import "PDLibraryDevice.h"
#import "PDLibraryDirectory.h"
#import "PDLibraryItem.h"
#import "PDLibraryGroup.h"
#import "PDLibraryQuery.h"
#import "PDWindowController.h"

#import "PXSourceList.h"

#define MAX_TITLE_STRINGS 6

NSString *const PDLibrarySelectionDidChange = @"PDLibrarySelectionDidChange";

@interface PDLibraryViewController ()
- (PDLibraryDevice *)addVolumeAtPath:(NSString *)path;
- (void)removeVolumeAtPath:(NSString *)path;
- (void)updateControls;
@end

NSString *const PDLibraryItemType = @"org.unfactored.PDLibraryItem";

@implementation PDLibraryViewController

+ (NSString *)viewNibName
{
  return @"PDLibraryView";
}

- (void)addImageLibraryItem:(PDImageLibrary *)lib
{
  PDLibraryDirectory *item
    = [[PDLibraryDirectory alloc] initWithLibrary:lib directory:@""];

  [item setTitleImageName:PDImage_GenericHardDisk];

  [_libraryGroup addSubitem:item];

  [item release];
}

- (void)addAlbumItem:(NSDictionary *)dict
{
  NSString *name = [dict objectForKey:@"name"];
  NSString *pred_str = [dict objectForKey:@"predicate"];

  PDLibraryItem *item = nil;

  if (pred_str != nil)
    {
      NSPredicate *pred = [_controller imagePredicateWithFormat:pred_str];

      if (pred != nil)
	{
	  PDLibraryQuery *tem = [[PDLibraryQuery alloc] init];
	  [tem setName:name];
	  [tem setPredicate:pred];
	  item = tem;
	}
    }

  if (item != nil)
    {
      [_albumsGroup addSubitem:item];
      [item release];
    }
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  _items = [[NSMutableArray alloc] init];

  _devicesGroup = [[PDLibraryGroup alloc] init];
  [_devicesGroup setName:@"DEVICES"];
  [_items addObject:_devicesGroup];
  [_devicesGroup release];

  _libraryGroup = [[PDLibraryGroup alloc] init];
  [_libraryGroup setName:@"LIBRARIES"];
  [_items addObject:_libraryGroup];
  [_libraryGroup release];

  _albumsGroup = [[PDLibraryGroup alloc] init];
  [_albumsGroup setName:@"ALBUMS"];
  [_items addObject:_albumsGroup];
  [_albumsGroup release];

  _itemViewState = [[NSMapTable strongToStrongObjectsMapTable] retain];

  return self;
}

- (void)invalidate
{
  for (PDLibraryDevice *item in [_devicesGroup subitems])
    {
      [[item library] remove];
    }
}

- (void)dealloc
{
  [_outlineView setDataSource:nil];
  [_outlineView setDelegate:nil];

  [_items release];
  [_itemViewState release];

  [_draggedItems release];
  [_draggedPasteboard release];

  [super dealloc];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [PDImageLibrary removeInvalidLibraries];

  for (id obj in [[NSUserDefaults standardUserDefaults]
		  arrayForKey:@"PDImageLibraries"])
    {
      PDImageLibrary *lib = [[PDImageLibrary alloc] initWithPropertyList:obj];
      if (lib != nil)
	{
	  [self addImageLibraryItem:lib];
	  [lib release];
	}
    }

  for (NSDictionary *dict in [[NSUserDefaults standardUserDefaults]
			      arrayForKey:@"PDLibraryAlbums"])
    {
      [self addAlbumItem:dict];
    }

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

  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  [[workspace notificationCenter]
   addObserver:self selector:@selector(volumeDidMount:)
   name:NSWorkspaceDidMountNotification object:nil];
  [[workspace notificationCenter]
   addObserver:self selector:@selector(volumeDidUnmount:)
   name:NSWorkspaceDidUnmountNotification object:nil];

  [[_searchField cell] setBackgroundColor:[NSColor grayColor]];

  for (NSTableColumn *col in [_outlineView tableColumns])
    [[col dataCell] setVerticallyCentered:YES];

  [_outlineView expandItem:_devicesGroup];
  [_outlineView expandItem:_libraryGroup];
  [_outlineView expandItem:_albumsGroup];

  [_outlineView registerForDraggedTypes:@[PDLibraryItemType]];

  [self rescanVolumes];

  [self updateControls];
}

- (NSView *)initialFirstResponder
{
  return _outlineView;
}

- (void)updateControls
{
  BOOL can_delete = NO;

  NSIndexSet *sel = [_outlineView selectedRowIndexes];
  NSInteger idx;
  for (idx = [sel firstIndex]; idx != NSNotFound;
       idx = [sel indexGreaterThanIndex:idx])
    {
      PDLibraryItem *item = [_outlineView itemAtRow:idx];

      if ([[item parent] isKindOfClass:[PDLibraryGroup class]])
	can_delete = YES;
    }

  [_removeButton setEnabled:can_delete];
  [_actionButton setEnabled:NO];
}

- (NSArray *)allImages
{
  return [_libraryGroup subimages];
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

- (void)rescanVolumes
{
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

  NSMutableSet *items = [NSMutableSet setWithArray:[_devicesGroup subitems]];

  for (NSString *path in [workspace mountedLocalVolumePaths])
    {
      PDLibraryDevice *item = [self addVolumeAtPath:path];
      if (item != nil)
	[items removeObject:item];
    }

  for (NSString *path in [workspace mountedRemovableMedia])
    {
      PDLibraryDevice *item = [self addVolumeAtPath:path];
      if (item != nil)
	[items removeObject:item];
    }

  if ([items count] != 0)
    {
      for (PDLibraryDevice *item in items)
	{
	  [[item library] remove];
	  [_devicesGroup removeSubitem:item];
	}
    }

  [_devicesGroup setHidden:[[_devicesGroup subitems] count] == 0];
  [_outlineView reloadDataPreservingSelectedRows];
}

- (PDLibraryDevice *)addVolumeAtPath:(NSString *)path
{
  NSString *dcim_path = [path stringByAppendingPathComponent:@"DCIM"];

  BOOL isdir = NO;
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:dcim_path isDirectory:&isdir] || !isdir)
    return nil;

  PDImageLibrary *lib = [PDImageLibrary libraryWithPath:dcim_path];

  if (lib != nil)
    {
      for (PDLibraryDevice *item in [_devicesGroup subitems])
	{
	  if ([item library] == lib)
	    {
	      if ([item needsUpdate])
		[_outlineView reloadItem:item];
	      return item;
	    }
	}
    }
  else
    {
      lib = [[[PDImageLibrary alloc] initWithPath:dcim_path] autorelease];
      if (lib == nil)
	return nil;
    }

  PDLibraryDevice *item = [[PDLibraryDevice alloc] initWithLibrary:lib];
  if (item == nil)
    return nil;

  [_devicesGroup addSubitem:item];
  [_devicesGroup setHidden:NO];

  [_outlineView reloadDataPreservingSelectedRows];
  [_outlineView expandItem:_devicesGroup];

  return item;
}

- (void)removeVolumeAtPath:(NSString *)path
{
  NSString *dcim_path = [path
			 stringByAppendingPathComponent:@"DCIM"];

  PDImageLibrary *lib = [PDImageLibrary libraryWithPath:dcim_path];
  if (lib == nil)
    return;

  BOOL changed = NO;

  for (PDLibraryDevice *item in [_devicesGroup subitems])
    {
      if ([item library] == lib)
	{
	  [lib remove];
	  [_devicesGroup removeSubitem:item];
	  changed = YES;
	  break;
	}
    }

  if (changed)
    {
      [_devicesGroup setHidden:[[_devicesGroup subitems] count] == 0];
      [_outlineView reloadDataPreservingSelectedRows];

      /* FIXME: why is this necessary? */
      [self sourceListSelectionDidChange:nil];
    }
}

- (void)volumeDidMount:(NSNotification *)note
{
  [self addVolumeAtPath:[[[note userInfo] objectForKey:
			  NSWorkspaceVolumeURLKey] path]];
}

- (void)volumeDidUnmount:(NSNotification *)note
{
  [self removeVolumeAtPath:[[[note userInfo] objectForKey:
			     NSWorkspaceVolumeURLKey] path]];
}

- (void)updateImageLibraries
{
  NSMutableArray *array = [NSMutableArray array];

  for (PDLibraryDirectory *item in [_libraryGroup subitems])
    {
      id obj = [[item library] propertyList];
      if (obj != nil)
	[array addObject:obj];
    }

  [[NSUserDefaults standardUserDefaults]
   setObject:array forKey:@"PDImageLibraries"];
}

- (void)updateImageAlbums
{
  NSMutableArray *array = [NSMutableArray array];

  for (PDLibraryQuery *item in [_albumsGroup subitems])
    {
      NSString *name = [item name];
      NSString *pred = [[item predicate] predicateFormat];
      if (pred == nil)
	pred = @"";

      [array addObject:@{@"name": name, @"predicate": pred}];
    }

  [[NSUserDefaults standardUserDefaults] setObject:array
   forKey:@"PDLibraryAlbums"];
}

- (IBAction)addLibraryAction:(id)sender
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

	     NSString *path = [url path];

	     if ([PDImageLibrary libraryWithPath:path] != nil)
	       continue;

	     PDImageLibrary *lib = [[PDImageLibrary alloc] initWithPath:path];
	     if (lib == nil)
	       continue;

	     [self addImageLibraryItem:lib];
	     [lib release];
	     changed = YES;
	   }

	 if (changed)
	   {
	     [self updateImageLibraries];
	     [_outlineView reloadDataPreservingSelectedRows];
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

  [self addAlbumItem:dict];

  [self updateImageAlbums];

  [_outlineView reloadItem:_albumsGroup reloadChildren:YES];
}

- (IBAction)removeAction:(id)sender
{
  BOOL changed = NO;
  NSIndexSet *sel = [_outlineView selectedRowIndexes];
  NSInteger idx;

  for (idx = [sel lastIndex]; idx != NSNotFound;
       idx = [sel indexLessThanIndex:idx])
    {
      PDLibraryItem *item = [_outlineView itemAtRow:idx];

      if (![[item parent] isKindOfClass:[PDLibraryGroup class]])
	continue;

      if ([item isKindOfClass:[PDLibraryDirectory class]])
	{
	  NSArray *subitems = [_libraryGroup subitems];
	  NSInteger idx = [subitems indexOfObjectIdenticalTo:item];
	  if (idx != NSNotFound)
	    {
	      PDImageLibrary *lib = [(PDLibraryDirectory *)item library];
	      [lib remove];
	      [_libraryGroup removeSubitem:[subitems objectAtIndex:idx]];
	      changed = YES;
	    }
	}
      else if ([item isKindOfClass:[PDLibraryQuery class]])
	{
	  NSArray *subitems = [_albumsGroup subitems];
	  NSInteger idx = [subitems indexOfObjectIdenticalTo:item];
	  if (idx != NSNotFound)
	    {
	      [_albumsGroup removeSubitem:[subitems objectAtIndex:idx]];
	      changed = YES;
	    }
	}
      else if ([item isKindOfClass:[PDLibraryDevice class]])
	{
	  NSString *path = [[[(PDLibraryDevice *)item library] path]
			    stringByDeletingLastPathComponent];
	  [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:path];
	}
    }

  if (changed)
    {
      [self updateImageLibraries];
      [self updateImageAlbums];

      [_outlineView reloadDataPreservingSelectedRows];
    }

  [self updateImageList];
}

static NSString *
find_unique_name(NSString *root, NSString *file)
{
  NSFileManager *fm = [NSFileManager defaultManager];

  for (int i = 0;; i++)
    {
      NSString *tem
        = i == 0 ? file : [NSString stringWithFormat:@"%@-%d", file, i];
      if (![fm fileExistsAtPath:[root stringByAppendingPathComponent:tem]])
	return tem;
    }

  /* not reached. */
}

- (void)renameItem:(PDLibraryItem *)item name:(NSString *)str
{
  if ([item isKindOfClass:[PDLibraryDirectory class]])
    {
      PDImageLibrary *lib = [(PDLibraryDirectory *)item library];

      if ([[(PDLibraryDirectory *)item libraryDirectory] length] == 0)
	{
	  /* Top-level item. Just rename the library. */

	  [lib setName:str];
	  [self updateImageLibraries];
	}
      else
	{
	  /* Rename the actual library directory. */

	  NSString *root = [lib path];
	  NSString *old_dir = [(PDLibraryDirectory *)item libraryDirectory];
	  NSString *new_dir = [[old_dir stringByDeletingLastPathComponent]
			       stringByAppendingPathComponent:str];

	  new_dir = find_unique_name(root, new_dir);

	  NSFileManager *fm = [NSFileManager defaultManager];

	  if ([fm moveItemAtPath:[root stringByAppendingPathComponent:old_dir]
	       toPath:[root stringByAppendingPathComponent:new_dir] error:nil])
	    {
	      [(PDLibraryDirectory *)item setLibraryDirectory:new_dir];

	      [lib didRenameDirectory:old_dir to:new_dir];
	    }
	}
    }
  else if ([item isKindOfClass:[PDLibraryQuery class]])
    {
      NSInteger idx = [[_albumsGroup subitems] indexOfObjectIdenticalTo:item];

      if (idx != NSNotFound)
	{
	  [(PDLibraryQuery *)item setName:str];

	  [self updateImageAlbums];
	}
    }

  [_outlineView reloadItem:item];
}

- (IBAction)searchAction:(id)sender
{
  NSString *str = [_searchField stringValue];

  if ([str length] != 0)
    [_libraryGroup applySearchString:str];
  else
    [_libraryGroup resetSearchState];

  [_outlineView reloadDataPreservingSelectedRows];
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

- (void)synchronize
{
  [self updateImageLibraries];

  /* Don't synchronize transient libraries (i.e. automounted devices),
     they'll be removed before we quit. */

  for (PDLibraryDirectory *item in [_libraryGroup subitems])
    [[item library] synchronize];
}

- (NSDictionary *)savedViewState
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  for (PDLibraryItem *item in _items)
    {
      if (item == _devicesGroup)
	continue;

      [self addItem:item viewState:dict];
    }

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

- (void)sourceList:(PXSourceList *)lst setObjectValue:(id)value
    forItem:(id)item
{
  [self renameItem:item name:value];
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

- (BOOL)sourceList:(PXSourceList *)lst writeItems:(NSArray *)items
    toPasteboard:(NSPasteboard *)pboard
{
  [pboard declareTypes:@[PDLibraryItemType] owner:self];
  [_draggedItems release];
  _draggedItems = [items copy];
  _draggedPasteboard = [pboard retain];
  return YES;
}

- (NSDragOperation)sourceList:(PXSourceList *)lst
    validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)obj
    proposedChildIndex:(NSInteger)idx
{
  PDLibraryItem *item = obj;
  NSPasteboard *pboard = [info draggingPasteboard];

  /* FIXME: support dropping images into libraries as well. */

  NSString *type = [pboard availableTypeFromArray:@[PDLibraryItemType]];

  if ([type isEqualToString:PDLibraryItemType])
    {
      if (_draggedItems == nil)
	return NSDragOperationNone;

      if (item == _libraryGroup || item == _albumsGroup)
	{
	  Class required_class = (item == _libraryGroup
				  ? [PDLibraryDirectory class]
				  : [PDLibraryQuery class]);

	  for (PDLibraryItem *dragged_item in _draggedItems)
	    {
	      if (![dragged_item isKindOfClass:required_class])
		return NSDragOperationNone;
	    }

	  return NSDragOperationMove;
	}
      else if ([item isKindOfClass:[PDLibraryDirectory class]])
	{
	  PDImageLibrary *lib = [(PDLibraryDirectory *)item library];

	  for (PDLibraryDirectory *dragged_item in _draggedItems)
	    {
	      if (![dragged_item isKindOfClass:[PDLibraryDirectory class]])
		return NSDragOperationNone;
	      if ([dragged_item library] != lib)
		return NSDragOperationNone;
	      if ([item isDescendantOf:dragged_item])
		return NSDragOperationNone;
	    }

	  return NSDragOperationMove;
	}
    }

  return NSDragOperationNone;
}

- (BOOL)sourceList:(PXSourceList *)lst acceptDrop:(id<NSDraggingInfo>)info
    item:(id)item childIndex:(NSInteger)idx
{
  NSPasteboard *pboard = [info draggingPasteboard];

  /* FIXME: support dropping images into libraries as well. */

  NSString *type = [pboard availableTypeFromArray:@[PDLibraryItemType]];

  if ([type isEqualToString:PDLibraryItemType])
    {
      if (_draggedItems == nil)
	return NSDragOperationNone;

      if (item == _libraryGroup || item == _albumsGroup)
	{
	  [_outlineView callPreservingSelectedRows:^{
	    NSInteger i = idx;

	    for (PDLibraryItem *dragged_item in _draggedItems)
	      {
		NSInteger item_idx
		  = [[item subitems] indexOfObjectIdenticalTo:dragged_item];
		if (item_idx == NSNotFound)
		  continue;
		[item removeSubitem:dragged_item];
		if (item_idx < i)
		  i--;
	      }

	    for (PDLibraryItem *dragged_item in _draggedItems)
	      [item insertSubitem:dragged_item atIndex:i++];

	    [_outlineView reloadItem:item reloadChildren:YES];
	  }];

	  if (item == _libraryGroup)
	    [self updateImageLibraries];
	  else
	    [self updateImageAlbums];

	  return YES;
	}
      else if ([item isKindOfClass:[PDLibraryDirectory class]])
	{
	  /* -callPreservingSelectedRows: doesn't work as we cause the
	     library items to be destroyed and recreated. */

	  PDImageLibrary *lib = [(PDLibraryDirectory *)item library];

	  NSString *item_dir = [(PDLibraryDirectory *)item libraryDirectory];

	  NSFileManager *fm = [NSFileManager defaultManager];

	  for (PDLibraryDirectory *dragged_item in _draggedItems)
	    {
	      NSString *src_dir = [dragged_item libraryDirectory];
	      NSString *dst_dir = [item_dir stringByAppendingPathComponent:
				   [src_dir lastPathComponent]];

	      NSString *src_path = [[lib path]
				    stringByAppendingPathComponent:src_dir];
	      NSString *dst_path = [[lib path]
				    stringByAppendingPathComponent:dst_dir];

	      if ([fm moveItemAtPath:src_path toPath:dst_path error:nil])
		[lib didRenameDirectory:src_dir to:dst_dir];

	      [(PDLibraryDirectory *)[dragged_item parent]
	       invalidateContents];
	    }

	  [(PDLibraryDirectory *)item invalidateContents];

	  [_outlineView reloadItem:_libraryGroup reloadChildren:YES];

	  NSInteger row = [_outlineView rowForItem:item];
	  if (row >= 0)
	    {
	      [_outlineView selectRowIndexes:
	       [NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	    }

	  return YES;
	}
    }

  return NO;
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
  return ([item isKindOfClass:[PDLibraryDirectory class]]
	  || [item isKindOfClass:[PDLibraryQuery class]]);
}

- (void)sourceListSelectionDidChange:(NSNotification *)note
{
  [self updateImageList];
  [self updateControls];

  if ([[_controller filteredImageList] count] > 0
      && [[_controller selectedImageIndexes] count] == 0)
    {
      [_controller setSelectedImageIndexes:[NSIndexSet indexSetWithIndex:0]];
    }

  [[NSNotificationCenter defaultCenter]
   postNotificationName:PDLibrarySelectionDidChange object:_controller];
}

// NSPasteboardOwner methods

- (void)pasteboard:(NSPasteboard *)sender provideDataForType:(NSString *)type
{
}

- (void)pasteboardChangedOwner:(NSPasteboard *)sender
{
  if (_draggedPasteboard == sender)
    {
      [_draggedItems release];
      _draggedItems = nil;
      [_draggedPasteboard release];
      _draggedPasteboard = nil;
    }
}

@end
