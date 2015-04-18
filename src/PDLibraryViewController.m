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
#import "PDFoundationExtensions.h"
#import "PDImage.h"
#import "PDImageLibrary.h"
#import "PDImageTextCell.h"
#import "PDImageUUID.h"
#import "PDLibraryAlbum.h"
#import "PDLibraryDevice.h"
#import "PDLibraryDirectory.h"
#import "PDLibraryFolder.h"
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
{
  PDImageTextCell *_importCell;

  NSMutableArray *_items;
  PDLibraryGroup *_libraryGroup;
  PDLibraryGroup *_devicesGroup;
  PDLibraryGroup *_foldersGroup;
  PDLibraryGroup *_albumsGroup;

  PDLibraryItem *_allPhotosItem;
  PDLibraryItem *_last12MonthsItem;
  PDLibraryItem *_flaggedItem;
  PDLibraryItem *_rejectedItem;
  PDLibraryItem *_trashItem;

  NSMapTable *_itemViewState;		/* PDLibraryItem -> NSDictionary */

  NSArray *_draggedItems;
  NSPasteboard *_draggedPasteboard;
  NSDragOperation _dragOperation;

  int _ignoreNotifications;

  NSArray *_selectedItems;
}

@synthesize outlineView = _outlineView;
@synthesize normalCell = _normalCell;
@synthesize searchField = _searchField;
@synthesize addButton = _addButton;
@synthesize removeButton = _removeButton;
@synthesize importButton = _importButton;
@synthesize actionButton = _actionButton;

+ (NSString *)viewNibName
{
  return @"PDLibraryView";
}

- (BOOL)addImageLibraryItem:(PDImageLibrary *)lib
{
  for (PDLibraryFolder *item in _foldersGroup.subitems)
    {
      if (item.library == lib)
	return NO;
    }

  PDLibraryFolder *item
    = [[PDLibraryFolder alloc] initWithLibrary:lib directory:@""];

  [item setTitleImageName:PDImage_GenericHardDisk];

  [_foldersGroup addSubitem:item];

  return YES;
}

- (void)addAlbumItem:(NSDictionary *)dict toItem:(PDLibraryGroup *)parent
{
  PDLibraryGroup *item = nil;

  NSString *pred_str = dict[@"predicate"];
  if (pred_str != nil)
    {
      PDLibraryQuery *tem = [[PDLibraryQuery alloc] init];

      tem.predicate = [_controller imagePredicateWithFormat:pred_str];
      tem.trashcan = [dict[@"trashcan"] boolValue];
      tem.nilPredicateIncludesRejected =
       [dict[@"nilPredicateIncludesRejected"] boolValue];
      
      item = tem;
    }
  else
    {
      NSArray *uuids = dict[@"imageUUIDs"];

      if (uuids != nil)
	{
	  PDLibraryAlbum *tem = [[PDLibraryAlbum alloc] init];

	  tem.imageUUIDs = [uuids mappedArray:^(id obj)
	    {
	      return [[NSUUID alloc] initWithUUIDString:obj];
	    }];

	  item = tem;
	}
    }

  if (item != nil)
    {
      NSString *name = dict[@"name"];
      if (name != nil)
	item.name = name;

      NSString *icon_name = dict[@"icon"];
      if (icon_name != nil)
	item.iconImage = [NSImage imageNamed:icon_name];

      for (NSDictionary *sub in dict[@"subitems"])
	[self addAlbumItem:sub toItem:item];

      [parent addSubitem:item];

      NSString *ident = dict[@"identifier"];
      if (ident != nil)
	{
	  if ([ident isEqualToString:@"allPhotos"])
	    _allPhotosItem = item;
	  else if ([ident isEqualToString:@"last12Months"])
	    _last12MonthsItem = item;
	  else if ([ident isEqualToString:@"flagged"])
	    _flaggedItem = item;
	  else if ([ident isEqualToString:@"rejected"])
	    _rejectedItem = item;
	  else if ([ident isEqualToString:@"trash"])
	    _trashItem = item;
	}
    }
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  _items = [[NSMutableArray alloc] init];

  _libraryGroup = [[PDLibraryGroup alloc] init];
  _libraryGroup.name = @"LIBRARY";
  _libraryGroup.identifier = @"library";
  [_items addObject:_libraryGroup];

  _devicesGroup = [[PDLibraryGroup alloc] init];
  _devicesGroup.name = @"DEVICES";
  _devicesGroup.identifier = @"devices";
  [_items addObject:_devicesGroup];

  _foldersGroup = [[PDLibraryGroup alloc] init];
  _foldersGroup.name = @"FOLDERS";
  _foldersGroup.identifier = @"folders";
  [_items addObject:_foldersGroup];

  _albumsGroup = [[PDLibraryGroup alloc] init];
  _albumsGroup.name = @"ALBUMS";
  _albumsGroup.identifier = @"albums";
  [_items addObject:_albumsGroup];

  _itemViewState = [NSMapTable strongToStrongObjectsMapTable];

  return self;
}

static void
invalidate_library(PDImageLibrary *lib)
{
  if (lib.transient)
    [lib emptyCaches];

  [lib invalidate];
}

- (void)invalidate
{
  for (PDLibraryFolder *item in _foldersGroup.subitems)
    invalidate_library(item.library);
  for (PDLibraryDevice *item in _devicesGroup.subitems)
    invalidate_library(item.library);
}

- (void)dealloc
{
  [_outlineView setDataSource:nil];
  [_outlineView setDelegate:nil];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [PDImageLibrary removeInvalidLibraries];

  for (NSDictionary *dict in [[NSUserDefaults standardUserDefaults]
			      arrayForKey:@"PDLibraryFixed"])
    {
      [self addAlbumItem:dict toItem:_libraryGroup];
    }

  for (id obj in [[NSUserDefaults standardUserDefaults]
		  arrayForKey:@"PDImageLibraries"])
    {
      PDImageLibrary *lib
        = [PDImageLibrary libraryWithPropertyListRepresentation:obj];

      if (lib != nil)
	[self addImageLibraryItem:lib];
    }

  for (NSDictionary *dict in [[NSUserDefaults standardUserDefaults]
			      arrayForKey:@"PDLibraryAlbums"])
    {
      [self addAlbumItem:dict toItem:_albumsGroup];
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
  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(importModeDidChange:)
   name:PDImportModeDidChange object:_controller];
  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(trashWasEmptied:)
   name:PDTrashWasEmptied object:_controller];

  [[NSNotificationCenter defaultCenter] addObserver:self
   selector:@selector(libraryDirectoryDidChange:)
   name:PDImageLibraryDirectoryDidChange object:nil];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imagePropertyDidChange:)
   name:PDImagePropertyDidChange object:nil];

  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  [[workspace notificationCenter]
   addObserver:self selector:@selector(volumeDidMount:)
   name:NSWorkspaceDidMountNotification object:nil];
  [[workspace notificationCenter]
   addObserver:self selector:@selector(volumeDidUnmount:)
   name:NSWorkspaceDidUnmountNotification object:nil];

  [_searchField.cell setBackgroundColor:[NSColor grayColor]];

  for (NSTableColumn *col in _outlineView.tableColumns)
    [col.dataCell setVerticallyCentered:YES];

  [_outlineView expandItem:_libraryGroup];
  [_outlineView expandItem:_devicesGroup];
  [_outlineView expandItem:_foldersGroup];
  [_outlineView expandItem:_albumsGroup];

  [_outlineView registerForDraggedTypes:@[PDLibraryItemType, PDImageUUIDType]];

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

  for (PDLibraryItem *item in _selectedItems)
    {
      PDLibraryItem *parent = item.parent;
      if (parent == _foldersGroup || parent == _devicesGroup
	  || [parent isDescendantOf:_albumsGroup])
	{
	  can_delete = YES;
	}
    }

  [_controller setAccessoryMode:_controller.importMode
   ? PDAccessoryMode_Import : PDAccessoryMode_Nil];

  _removeButton.enabled = can_delete;
  _actionButton.enabled = NO;
  _importButton.state = _controller.importMode;
  _importButton.enabled = _devicesGroup.subitems.count != 0;
}

- (BOOL)foreachImage:(void (^)(PDImage *im, BOOL *stop))thunk
{
  if (![_foldersGroup foreachSubimage:thunk])
    return NO;

  if (![_devicesGroup foreachSubimage:thunk])
    return NO;

  return YES;
}

- (void)updateSelectedItems
{
  _selectedItems = [_outlineView.selectedItems copy];
}

- (void)updateImageList:(uint32_t)flags
{
  if (_selectedItems.count == 0)
    {
      _controller.imageListTitle = @"";
      _controller.imageList = @[];
    }
  else
    {
      NSMutableArray *images = [NSMutableArray array];
      NSMutableSet *image_set = [NSMutableSet set];
      NSMutableString *title = [NSMutableString string];
      BOOL showsHidden = _controller.showsHiddenImages;
      BOOL includesRejected = NO;
      NSInteger count = 0;
      NSDictionary *viewState = nil;

      for (PDLibraryItem *item in _selectedItems)
	{
	  /* FIXME: checking trash state here is ugly, but it's not
	     possible to make the library item classes do it without
	     introducing a lot of extra code (since the query class
	     uses the other classes to prepare the list it queries). */

	  BOOL trash_item = item.trashcan;

	  if (viewState == nil)
	    viewState = [_itemViewState objectForKey:item];

	  if (item.nilPredicateIncludesRejected)
	    includesRejected = YES;

	  __block BOOL need_title = NO;

	  [item foreachSubimage:^(PDImage *im, BOOL *stop)
	    {
	      if ((showsHidden || !im.hidden)
		  && im.deleted == trash_item
		  && ![image_set containsObject:im])
		{
		  [images addObject:im];
		  [image_set addObject:im];
		  need_title = YES;
		}
	    }];

	  if (need_title)
	    {
	      NSString *item_title = item.titleString;
	      if (item_title.length != 0)
		{
		  if (count < MAX_TITLE_STRINGS)
		    {
		      if (title.length != 0)
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
	  NSString *key = viewState[@"imageSortKey"];
	  if (key != nil)
	    sortKey = [PDImage imageCompareKeyFromString:key];

	  sortRev = [viewState[@"imageSortReversed"] boolValue];

	  NSString *predicate = viewState[@"imagePredicate"];
	  if (predicate != nil)
	    pred = [_controller imagePredicateWithFormat:predicate];
	}

      /* Install sort/filter options before modifying the image list,
	 so that they only get applied once. */

      _ignoreNotifications++;
      _controller.imageSortKey = sortKey;
      _controller.imageSortReversed = sortRev;
      _controller.imagePredicate = pred;
      _controller.nilPredicateIncludesRejected = includesRejected;
      _ignoreNotifications--;

      _controller.imageListTitle = title;
      _controller.imageList = images;
    }

  [_controller rebuildImageList:flags];
}

- (NSInteger)imageListSizeFromItem:(PDLibraryItem *)item
{
  BOOL showsHidden = _controller.showsHiddenImages;
  BOOL trash_item = item.trashcan;

  __block NSInteger count = 0;

  [item foreachSubimage:^(PDImage *im, BOOL *stop)
    {
      if ((showsHidden || !im.hidden) && im.deleted == trash_item)
	count++;
    }];

  return count;
}

- (void)libraryItemSubimagesDidChange:(NSNotification *)note
{
  PDLibraryItem *item = note.object;
  BOOL need_update = NO;

  while (item != nil)
    {
      [_outlineView reloadItem:item];

      if ([_selectedItems indexOfObjectIdenticalTo:item] != NSNotFound)
	need_update = YES;

      item = item.parent;
    }

  if (!need_update)
    {
      for (PDLibraryItem *item in _selectedItems)
	{
	  if ([item isKindOfClass:[PDLibraryQuery class]]
	      || [item isKindOfClass:[PDLibraryAlbum class]])
	    {
	      need_update = YES;
	      break;
	    }
	}
    }

  if (need_update)
    [self updateImageList:0];
}

- (void)showsHiddenImagesDidChange:(NSNotification *)note
{
  [self updateImageList:PDWindowController_StopPreservingImages];

  [_outlineView reloadData];
}

- (void)rescanVolumes
{
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

  NSMutableSet *items = [NSMutableSet setWithArray:_devicesGroup.subitems];

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

  if (items.count != 0)
    {
      for (PDLibraryDevice *item in items)
	{
	  invalidate_library(item.library);
	  [_devicesGroup removeSubitem:item];
	}
    }

  [_devicesGroup setHidden:_devicesGroup.subitems.count == 0];
  [_outlineView reloadDataPreservingSelectedRows];
}

- (PDLibraryDevice *)addVolumeAtPath:(NSString *)path
{
  NSString *dcim_path = [path stringByAppendingPathComponent:@"DCIM"];

  BOOL isdir = NO;
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:dcim_path isDirectory:&isdir] || !isdir)
    return nil;

  PDImageLibrary *lib = [PDImageLibrary libraryWithPath:path];
  if (lib == nil)
    return nil;

  for (PDLibraryDevice *item in _devicesGroup.subitems)
    {
      if (item.library == lib)
	{
	  [item setNeedsUpdate];
	  [_outlineView reloadItem:item];
	  return item;
	}
    }

  lib.transient = YES;

  PDLibraryDevice *item = [[PDLibraryDevice alloc] initWithLibrary:lib];
  if (item == nil)
    return nil;

  [_devicesGroup addSubitem:item];
  _devicesGroup.hidden = NO;

  [_outlineView reloadDataPreservingSelectedRows];
  [_outlineView expandItem:_devicesGroup];

  return item;
}

- (void)removeVolumeAtPath:(NSString *)path
{
  PDImageLibrary *lib = [PDImageLibrary libraryWithPath:path onlyIfExists:YES];
  if (lib == nil)
    return;

  BOOL changed = NO;

  for (PDLibraryDevice *item in _devicesGroup.subitems)
    {
      if (item.library == lib)
	{
	  invalidate_library(lib);
	  [_devicesGroup removeSubitem:item];
	  changed = YES;
	  break;
	}
    }

  if (changed)
    {
      [_devicesGroup setHidden:_devicesGroup.subitems.count == 0];
      [_outlineView reloadDataPreservingSelectedRows];

      /* FIXME: why is this necessary? */
      [self sourceListSelectionDidChange:nil];
    }
}

- (void)volumeDidMount:(NSNotification *)note
{
  [self addVolumeAtPath:[note.userInfo[NSWorkspaceVolumeURLKey] path]];
}

- (void)volumeDidUnmount:(NSNotification *)note
{
  [self removeVolumeAtPath:[note.userInfo[NSWorkspaceVolumeURLKey] path]];
  [self updateControls];
}

- (void)updateImageLibraries
{
  NSMutableArray *array = [NSMutableArray array];

  for (PDLibraryFolder *item in _foldersGroup.subitems)
    {
      id obj = [item.library propertyListRepresentation];
      if (obj != nil)
	[array addObject:obj];
    }

  [[NSUserDefaults standardUserDefaults]
   setObject:array forKey:@"PDImageLibraries"];
}

static NSDictionary *
library_group_description(PDLibraryGroup *item)
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  dict[@"name"] = item.name;

  NSArray *subitems = item.subitems;
  if (subitems.count != 0)
    {
      dict[@"subitems"] = [subitems mappedArray:^(id obj) {
	return library_group_description(obj);}];
    }

  if ([item isKindOfClass:[PDLibraryQuery class]])
    {
      NSString *pred = ((PDLibraryQuery *)item).predicate.predicateFormat;
      if (pred != nil)
	dict[@"predicate"] = pred;
    }
  else if ([item isKindOfClass:[PDLibraryAlbum class]])
    {
      dict[@"imageUUIDs"] = [((PDLibraryAlbum *)item).imageUUIDs
			     mappedArray:^(id obj) {
			       return ((NSUUID *)obj).UUIDString;}];
    }

  return dict;
}

- (void)updateImageAlbums
{
  [[NSUserDefaults standardUserDefaults] setObject:
   [[_albumsGroup subitems] mappedArray:^(id obj) {
     return library_group_description(obj);}]
   forKey:@"PDLibraryAlbums"];
}

- (IBAction)addLibraryAction:(id)sender
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];

  panel.canChooseDirectories = YES;
  panel.canChooseFiles = NO;
  panel.allowsMultipleSelection = YES;
  panel.prompt = @"Add Folder";
  panel.title = @"Select folder to add to library";

  [panel beginWithCompletionHandler:^(NSInteger status)
    {
      if (status == NSFileHandlingPanelOKButton)
	{
	  BOOL changed = NO;
	  NSArray *urls = panel.URLs;

	  for (NSURL *url in urls)
	    {
	      if (!url.fileURL)
		continue;

	      NSString *path = url.path;
	      PDImageLibrary *lib = [PDImageLibrary libraryWithPath:path];
	      if (lib == nil)
		continue;

	      [self addImageLibraryItem:lib];
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

- (IBAction)newFolderAction:(id)sender
{
  if (_selectedItems.count != 1)
    {
      NSBeep();
      return;
    }

  PDLibraryFolder *item = [_selectedItems firstObject];
  if (![item isKindOfClass:[PDLibraryFolder class]])
    {
      NSBeep();
      return;
    }

  NSString *dir = [item.libraryDirectory
		   stringByAppendingPathComponent:@"Untitled"];

  [item.library createDirectory:dir];
}

- (IBAction)newAlbumAction:(id)sender
{
  NSDictionary *dict = @{
    @"name": @"Untitled",
    @"imageUUIDs": @[]
  };

  [self addAlbumItem:dict toItem:_albumsGroup];

  [self updateImageAlbums];

  [_outlineView reloadItem:_albumsGroup reloadChildren:YES];
}

- (void)addSmartAlbum:(NSString *)name predicate:(NSPredicate *)pred
{
  NSString *query = pred.predicateFormat;
  if (query == nil)
    query = @"";

  NSDictionary *dict = @{
    @"name": name,
    @"predicate": query
  };

  [self addAlbumItem:dict toItem:_albumsGroup];

  [self updateImageAlbums];

  [_outlineView reloadItem:_albumsGroup reloadChildren:YES];
}

static void
reload_item(PDLibraryItem *item)
{
  for (PDLibraryItem *subitem in item.subitems)
    reload_item(subitem);

  [item setNeedsUpdate];
}

- (IBAction)reloadLibraries:(id)sender
{
  for (PDLibraryItem *item in _items)
    reload_item(item);

  [_outlineView reloadData];
}

- (IBAction)removeAction:(id)sender
{
  BOOL changed = NO;

  for (PDLibraryItem *item in [_selectedItems copy])
    {
      PDLibraryItem *parent = item.parent;

      if (parent == _foldersGroup)
	{
	  NSArray *subitems = parent.subitems;
	  NSInteger idx = [subitems indexOfObjectIdenticalTo:item];
	  if (idx != NSNotFound)
	    {
	      invalidate_library(((PDLibraryFolder *)item).library);
	      [_foldersGroup removeSubitem:subitems[idx]];
	      changed = YES;
	    }
	}
      else if ([item isDescendantOf:_albumsGroup])
	{
	  [(PDLibraryGroup *)parent removeSubitem:item];
	  changed = YES;
	}
      else if (parent == _devicesGroup)
	{
	  [item unmount];
	}
    }

  if (changed)
    {
      [self updateImageLibraries];
      [self updateImageAlbums];

      [_outlineView reloadDataPreservingSelectedRows];
    }

  [self sourceListSelectionDidChange:nil];
}

- (void)renameItem:(PDLibraryItem *)item name:(NSString *)str
{
  PDLibraryItem *parent = [item parent];

  if (parent == _foldersGroup)
    {
      /* Top-level directory item. Just rename the library. */

      ((PDLibraryFolder *)item).library.name = str;
      [self updateImageLibraries];
    }
  else if ([item isKindOfClass:[PDLibraryFolder class]])
    {
      PDLibraryFolder *f_item = (PDLibraryFolder *)item;

      /* Non-top-level directory -- rename the directory. */

      NSString *old_dir = f_item.libraryDirectory;
      NSString *new_dir = [[old_dir stringByDeletingLastPathComponent]
			   stringByAppendingPathComponent:str];

      [f_item.library renameDirectory:old_dir to:new_dir];
    }
  else if (parent == _albumsGroup)
    {
      NSInteger idx = [_albumsGroup.subitems indexOfObjectIdenticalTo:item];

      if (idx != NSNotFound)
	{
	  ((PDLibraryQuery *)item).name = str;

	  [self updateImageAlbums];
	}
    }

  [_outlineView reloadItem:item];
}

- (IBAction)searchAction:(id)sender
{
  NSString *str = _searchField.stringValue;

  if (str.length != 0)
    [_foldersGroup applySearchString:str];
  else
    [_foldersGroup resetSearchState];

  [_outlineView reloadDataPreservingSelectedRows];

  [self updateImageList:0];
}

- (IBAction)importAction:(id)sender
{
  if (sender == _importButton)
    _controller.importMode = _importButton.state;
  else
    _controller.importMode = YES;
}

- (void)importModeDidChange:(NSNotification *)note
{
  if (_ignoreNotifications)
    return;

  if (_controller.importMode)
    {
      NSMutableArray *import_items = [NSMutableArray array];

      for (PDLibraryItem *item in _selectedItems)
	{
	  if ([item isKindOfClass:[PDLibraryDevice class]])
	    [import_items addObject:item];
	}

      if (import_items.count == 0)
	{
	  [_outlineView expandItem:_devicesGroup];

	  PDLibraryItem *item = [_devicesGroup.subitems firstObject];
	  if (item != nil)
	    [import_items addObject:item];
	}

      if (import_items.count != 0)
	{
	  _selectedItems = [import_items copy];

	  [self updateImageList:PDWindowController_StopPreservingImages];
	  [self updateControls];

	  for (PDLibraryItem *item in _outlineView.selectedItems)
	    {
	      if ([item isKindOfClass:[PDLibraryFolder class]])
		{
		  [_controller setImportDestinationLibrary:
		   ((PDLibraryFolder *)item).library
		   directory:((PDLibraryFolder *)item).libraryDirectory];
		  break;
		}
	    }
	}
      else
	_controller.importMode = NO;
    }
  else
    {
      [self sourceListSelectionDidChange:nil];
      [self updateControls];
    }

  [_outlineView reloadData];
}

- (IBAction)delete:(id)sender
{
  /* Deletion is context-sensitive, e.g. deleting an image from an
     album vs deleting an image from a folder on disk. */

  NSMapTable *table = [NSMapTable strongToStrongObjectsMapTable];

  BOOL update_albums = NO;

  for (PDImage *image in _controller.selectedImages)
    {
      [table setObject:@(NO) forKey:image];
    }

  for (PDLibraryItem *item in _selectedItems)
    {
      if ([item isKindOfClass:[PDLibraryAlbum class]])
	{
	  PDLibraryAlbum *a_item = (PDLibraryAlbum *)item;
	  for (PDImage *image in table)
	    {
	      NSUUID *uuid = [image UUIDIfDefined];
	      if (uuid != nil && [a_item.imageUUIDs containsObject:uuid])
		{
		  [a_item removeImageWithUUID:uuid];
		  update_albums = YES;
		}
	    }
	}
      else if ([item isKindOfClass:[PDLibraryDirectory class]])
	{
	  [item foreachSubimage:^(PDImage *im, BOOL *stop)
	    {
	      if ([table objectForKey:im] != nil)
		[table setObject:@(YES) forKey:im];
	    }];
	}
    }

  for (PDImage *image in table)
    {
      if ([[table objectForKey:image] boolValue])
	[image setDeleted:YES];
    }

  [_outlineView reloadData];

  [self updateImageList:PDWindowController_StopPreservingImages];

  if (update_albums)
    [self updateImageAlbums];
}

- (void)trashWasEmptied:(NSNotification *)note
{
  NSArray *images = note.userInfo[@"imagesRemoved"];

  NSMutableSet *items = [NSMutableSet set];

  for (PDImage *image in images)
    {
      PDImageLibrary *lib = image.library;
      NSString *lib_dir = image.libraryDirectory;

      for (PDLibraryFolder *item in _foldersGroup.subitems)
	{
	  if (item.library == lib)
	    {
	      PDLibraryDirectory *subitem
	        = [item subitemContainingDirectory:lib_dir];

	      if (subitem != nil)
		{
		  [subitem setNeedsUpdate];
		  [items addObject:subitem];
		}
	    }
	}

      for (PDLibraryDevice *item in _devicesGroup.subitems)
	{
	  if (item.library == lib)
	    {
	      [item setNeedsUpdate];
	      [items addObject:item];
	    }
	}

      for (PDLibraryItem *item in _libraryGroup.subitems)
	{
	  if (item.trashcan)
	    [items addObject:item];
	}
    }

  if (items.count != 0)
    {
      for (PDLibraryItem *item in items)
	{
	  [_outlineView reloadItem:item reloadChildren:YES];
	}

      [self updateImageList:0];
    }
}

static void
expand_item_recursively(NSOutlineView *view, PDLibraryItem *item)
{
  if (item != nil)
    {
      expand_item_recursively(view, item.parent);
      [view expandItem:item];
    }
}

- (void)selectLibrary:(PDImageLibrary *)lib directory:(NSString *)dir
{
  for (PDLibraryFolder *item in _foldersGroup.subitems)
    {
      if (item.library != lib)
	continue;

      PDLibraryDirectory *subitem = [item subitemContainingDirectory:dir];
      if (subitem == nil)
	continue;

      expand_item_recursively(_outlineView, subitem);

      NSInteger row = [_outlineView rowForItem:subitem];
      if (row >= 0)
	_outlineView.selectedRow = row;
    }
}

- (IBAction)nextLibraryItemAction:(id)sender
{
  NSIndexSet *sel = [_outlineView selectedRowIndexes];

  NSInteger row;
  if (sel.count == 0)
    row = 0;
  else
    row = [sel lastIndex] + 1;

  NSInteger count = _outlineView.numberOfRows;

  while (row < count
	 && [_outlineView isGroupItem:[_outlineView itemAtRow:row]])
    row++;

  if (row < count)
    _outlineView.selectedRow = row;
}

- (IBAction)previousLibraryItemAction:(id)sender
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;

  NSInteger row;
  if (sel.count == 0)
    row = _outlineView.numberOfRows - 1;
  else
    row = [sel firstIndex] - 1;

  while (row >= 0
	 && [_outlineView isGroupItem:[_outlineView itemAtRow:row]])
    row--;

  if (row >= 0)
    _outlineView.selectedRow = row;
}

- (IBAction)parentLibraryItemAction:(id)sender
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;

  if (sel.count != 1)
    {
      NSBeep();
      return;
    }

  NSInteger row = [_outlineView rowForItem:
		   [[_outlineView itemAtRow:[sel firstIndex]] parent]];
  if (row >= 0)
    _outlineView.selectedRow = row;
}

- (IBAction)firstLibraryChildItemAction:(id)sender
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;

  if (sel.count != 1)
    {
      NSBeep();
      return;
    }

  PDLibraryItem *item = [_outlineView itemAtRow:[sel firstIndex]];
  PDLibraryItem *subitem = [item.subitems firstObject];

  if (subitem == nil)
    {
      NSBeep();
      return;
    }

  [_outlineView expandItem:item];

  NSInteger row = [_outlineView rowForItem:subitem];
  if (row >= 0)
    _outlineView.selectedRow = row;
}

- (IBAction)expandLibraryItemAction:(id)sender
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;

  if (sel.count != 1)
    {
      NSBeep();
      return;
    }

  PDLibraryItem *item = [_outlineView itemAtRow:[sel firstIndex]];
  if (item != nil)
    [_outlineView expandItem:item];
}

- (IBAction)collapseLibraryItemAction:(id)sender
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;

  if (sel.count != 1)
    {
      NSBeep();
      return;
    }

  PDLibraryItem *item = [_outlineView itemAtRow:[sel firstIndex]];
  if (item != nil)
    [_outlineView collapseItem:item];
}

- (IBAction)expandCollapseLibraryItemAction:(id)sender
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;

  if (sel.count != 1)
    {
      NSBeep();
      return;
    }

  PDLibraryItem *item = [_outlineView itemAtRow:[sel firstIndex]];

  if ([_outlineView isItemExpanded:item])
    [_outlineView collapseItem:item];
  else
    [_outlineView expandItem:item];
}

- (void)libraryDirectoryDidChange:(NSNotification *)note
{
  PDImageLibrary *lib = note.object;
  NSDictionary *info = note.userInfo;
  NSString *lib_dir = info[@"libraryDirectory"];

  for (PDLibraryFolder *item in _foldersGroup.subitems)
    {
      if (item.library == lib)
	{
	  PDLibraryDirectory *subitem
	    = [item subitemContainingDirectory:lib_dir];

	  if (subitem != nil)
	    {
	      [subitem setNeedsUpdate];
	      [_outlineView reloadItem:subitem reloadChildren:YES];
	    }
	}
    }

  [self updateImageList:0];
}

- (void)imagePropertyDidChange:(NSNotification *)note
{
  static NSSet *keys;
  static dispatch_once_t once;

  dispatch_once(&once, ^
    {
      keys = [[NSSet alloc] initWithObjects:
	      PDImage_Deleted, PDImage_Hidden, PDImage_Rating, nil];
    });

  if ([keys containsObject:note.userInfo[@"key"]])
    {
      [self updateImageList:PDWindowController_PreserveSelectedImages];
    }
}

- (IBAction)controlAction:(id)sender
{
}

- (void)imageViewOptionsDidChange:(NSNotification *)note
{
  if (_ignoreNotifications != 0)
    return;

  int key = _controller.imageSortKey;
  BOOL rev = _controller.imageSortReversed;
  NSPredicate *pred = _controller.imagePredicate;

  NSMutableDictionary *opts = [NSMutableDictionary dictionary];

  if (key != PDImageCompare_Date)
    opts[@"imageSortKey"] = [PDImage imageCompareKeyString:key];
  if (rev)
    opts[@"imageSortReversed"] = @(rev);
  if (pred != nil)
    opts[@"imagePredicate"] = pred.predicateFormat;

  if (opts.count == 0)
    opts = nil;

  for (PDLibraryItem *item in _selectedItems)
    {
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
      __unsafe_unretained NSString *ident;
    };

  struct node *lst = NULL;

  for (; item != nil; item = item.parent)
    {
      NSString *ident = item.identifier;
      if (ident.length == 0)
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
	  NSString *ident2 = subitem.identifier;

	  if ([ident isEqualToString:ident2])
	    {
	      found = YES;
	      item = subitem;
	      items = subitem.subitems;
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
  NSString *ident = item.identifier;
  if (ident.length == 0)
    return;

  BOOL expanded = [_outlineView isItemExpanded:item];
  NSDictionary *opts = [_itemViewState objectForKey:item];

  NSMutableDictionary *subdict = [[NSMutableDictionary alloc] init];

  for (PDLibraryItem *subitem in item.subitems)
    [self addItem:subitem viewState:subdict];

  NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

  if (expanded)
    dict[@"expanded"] = @YES;
  if (opts.count != 0)
    dict[@"viewState"] = opts;
  if (subdict.count != 0)
    dict[@"subitems"] = subdict;

  if (dict.count != 0)
    state[ident] = dict;
}

- (void)applyItem:(PDLibraryItem *)item viewState:(NSDictionary *)dict
{
  NSString *ident = item.identifier;
  if (ident.length == 0)
    return;

  NSDictionary *state = dict[ident];
  if (state == nil)
    return;

  if ([state[@"expanded"] boolValue])
    [_outlineView expandItem:item];

  NSDictionary *view_state = state[@"viewState"];
  if (view_state.count != 0)
    [_itemViewState setObject:view_state forKey:item];

  NSDictionary *sub_state = state[@"subitems"];
  if (sub_state != nil)
    {
      for (PDLibraryItem *subitem in item.subitems)
	[self applyItem:subitem viewState:sub_state];
    }
}

- (void)synchronize
{
  [self updateImageLibraries];

  /* Don't synchronize transient libraries (i.e. automounted devices),
     they'll be removed before we quit. */

  for (PDLibraryFolder *item in _foldersGroup.subitems)
    [item.library synchronize];
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

  for (PDLibraryItem *item in _selectedItems)
    {
      NSArray *path = path_for_item(item);
      if (path != nil)
	[selected addObject:path];
    }

  return @{
    @"itemState": dict,
    @"selectedItems": selected
  };
}

- (void)applySavedViewState:(NSDictionary *)state
{
  NSDictionary *item_state = state[@"itemState"];

  if (item_state != nil)
    {
      for (PDLibraryItem *item in _items)
	[self applyItem:item viewState:item_state];
    }

  NSArray *selected = state[@"selectedItems"];
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

  if (sel.count != 0)
    {
      [_outlineView selectRowIndexes:sel byExtendingSelection:NO];
      [_outlineView scrollRowToVisible:[sel firstIndex]];
    }

  [self updateImageList:0];
}

- (void)scrollSelectionToVisible
{
  NSIndexSet *sel = _outlineView.selectedRowIndexes;
  if (sel.count == 0)
    return;

  CGRect rect = CGRectNull;

  for (NSInteger idx = [sel firstIndex];
       idx != NSNotFound; idx = [sel indexGreaterThanIndex:idx])
    {
      rect = CGRectUnion(rect, [_outlineView rectOfRow:idx]);
    }

  if (!CGRectIsEmpty(rect))
    {
      rect = CGRectInset(rect, 0, -4);
      [_outlineView scrollRectToVisible:rect];
    }
}

// PXSourceListDataSource methods

- (NSUInteger)sourceList:(PXSourceList *)lst numberOfChildrenOfItem:(id)item
{
  NSArray *array = item == nil ? _items : ((PDLibraryItem *)item).subitems;
  NSInteger count = 0;

  for (PDLibraryItem *item in array)
    {
      if (!item.hidden)
       count++;
    }

  return count;
}

- (id)sourceList:(PXSourceList *)lst child:(NSUInteger)idx ofItem:(id)item
{
  NSArray *array = item == nil ? _items : ((PDLibraryItem *)item).subitems;
  NSUInteger count = 0;

  for (PDLibraryItem *item in array)
    {
      if (!item.hidden && count++ == idx)
       return item;
    }

  return nil;
}

- (id)sourceList:(PXSourceList *)lst objectValueForItem:(id)item
{
  return ((PDLibraryItem *)item).titleString;
}

- (void)sourceList:(PXSourceList *)lst setObjectValue:(id)value
    forItem:(id)item
{
  [self renameItem:item name:value];
}

- (BOOL)sourceList:(PXSourceList *)lst isItemExpandable:(id)item
{
  return ((PDLibraryItem *)item).expandable;
}

- (BOOL)sourceList:(PXSourceList *)lst itemHasBadge:(id)item
{
  return ((PDLibraryItem *)item).hasBadge;
}

- (NSInteger)sourceList:(PXSourceList *)lst badgeValueForItem:(id)item
{
  if (((PDLibraryItem *)item).badgeValueIsNumberOfSubimages)
    return [self imageListSizeFromItem:item];
  else
    return ((PDLibraryItem *)item).badgeValue;
}

- (BOOL)sourceList:(PXSourceList *)lst itemHasIcon:(id)item
{
  return ((PDLibraryItem *)item).hasTitleImage;
}

- (NSImage*)sourceList:(PXSourceList *)lst iconForItem:(id)item
{
  return ((PDLibraryItem *)item).titleImage;
}

- (BOOL)sourceList:(PXSourceList *)lst writeItems:(NSArray *)items
    toPasteboard:(NSPasteboard *)pboard
{
  /* FIXME: replace by a call to -writeObjects:. And declare items
     that represent physical directories as doing so. */

  [pboard declareTypes:@[PDLibraryItemType] owner:self];

  _draggedItems = [items copy];
  _draggedPasteboard = pboard;

  return YES;
}

- (NSDragOperation)sourceList:(PXSourceList *)lst
    validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)obj
    proposedChildIndex:(NSInteger)idx
{
  PDLibraryItem *item = obj;
  NSPasteboard *pboard = info.draggingPasteboard;
  NSDragOperation op = NSDragOperationNone;

  /* FIXME: support dropping images into libraries as well. */

  NSString *type = [pboard availableTypeFromArray:
		    @[PDLibraryItemType, PDImageUUIDType]];

  if ([type isEqualToString:PDLibraryItemType])
    {
      if (_draggedItems == nil)
	op = NSDragOperationNone;

      else if ([item isDescendantOf:_albumsGroup])
	{
	  op = NSDragOperationMove;

	  for (PDLibraryItem *dragged_item in _draggedItems)
	    {
	      if (![dragged_item.parent isDescendantOf:_albumsGroup])
		{
		  op = NSDragOperationNone;
		  break;
		}
	    }
	}
      else if (item == _foldersGroup)
	{
	  op = NSDragOperationMove;
	  for (PDLibraryItem *dragged_item in _draggedItems)
	    {
	      if (![dragged_item isKindOfClass:[PDLibraryFolder class]])
		{
		  op = NSDragOperationNone;
		  break;
		}
	    }
	}
      else if ([item isKindOfClass:[PDLibraryFolder class]])
	{
	  PDImageLibrary *lib = ((PDLibraryFolder *)item).library;

	  op = NSDragOperationMove;
	  
	  for (PDLibraryFolder *dragged_item in _draggedItems)
	    {
	      if (![dragged_item isKindOfClass:[PDLibraryFolder class]]
		  || dragged_item.library != lib
		  || [item isDescendantOf:dragged_item])
		op = NSDragOperationNone;
	    }
	}
    }
  else if ([type isEqualToString:PDImageUUIDType])
    {
      PDLibraryItem *parent = ((PDLibraryItem *)item).parent;

      info.draggingFormation = NSDraggingFormationDefault;

      /* Can never drop images between library rows. */

      [_outlineView setDropItem:item
       dropChildIndex:NSOutlineViewDropOnItemIndex];

      NSArray *uuids = [[pboard readObjectsForClasses:
			 @[[PDImageUUID class]] options:nil]
			mappedArray:^id (id obj) {return [obj UUID];}];
      NSSet *uuid_set = [NSSet setWithArray:uuids];

      unsigned int mods = _controller.window.currentEvent.modifierFlags;

      if (parent == _libraryGroup)
	{
	  if (item == _flaggedItem || item == _rejectedItem)
	    op = NSDragOperationCopy;
	  else if (item == _trashItem)
	    op = NSDragOperationMove;
	  else
	    op = NSDragOperationNone;
	}
      else if ([item isKindOfClass:[PDLibraryAlbum class]])
	{
	  /* If dropping an image from another album, can only copy. */

	  __block BOOL can_copy = YES;

	  for (PDLibraryItem *item in _selectedItems)
	    {
	      [item foreachSubimage:^(PDImage *image, BOOL *stop)
		{
		  NSUUID *uuid = [image UUIDIfDefined];
		  if (uuid != nil && [uuid_set containsObject:uuid])
		    {
		      if ([item isKindOfClass:[PDLibraryAlbum class]])
			can_copy = NO, *stop = YES;
		    }
		}];
	    }

	  if ((mods & NSAlternateKeyMask) && can_copy)
	    op = NSDragOperationCopy;
	  else
	    op = NSDragOperationMove;
	}
      else if ([item isKindOfClass:[PDLibraryDirectory class]])
	{
	  if (mods & NSAlternateKeyMask)
	    op = NSDragOperationCopy;
	  else
	    op = NSDragOperationMove;
	}
    }

  _dragOperation = op;
  return op;
}

- (BOOL)sourceList:(PXSourceList *)lst acceptDrop:(id<NSDraggingInfo>)info
    item:(id)item childIndex:(NSInteger)idx
{
  NSPasteboard *pboard = info.draggingPasteboard;

  /* FIXME: support dropping images into libraries as well. */

  NSString *type = [pboard availableTypeFromArray:
		    @[PDLibraryItemType, PDImageUUIDType]];

  if ([type isEqualToString:PDLibraryItemType])
    {
      if (_draggedItems == nil)
	return NO;

      if (item == _foldersGroup
	  || [(PDLibraryItem *)item isDescendantOf:_albumsGroup])
	{
	  [_outlineView callPreservingSelectedRows:^
	    {
	      NSInteger i = idx;

	      NSMutableSet *reload = [NSMutableSet setWithObject:item];

	      for (PDLibraryItem *dragged_item in _draggedItems)
		{
		  PDLibraryGroup *parent = (id)dragged_item.parent;
		  NSInteger item_idx = [parent.subitems
					indexOfObjectIdenticalTo:dragged_item];
		  if (item_idx == NSNotFound)
		    continue;
		  [parent removeSubitem:dragged_item];
		  [reload addObject:parent];
		  if (parent == item && item_idx < i)
		    i--;
		}

	      for (PDLibraryItem *dragged_item in _draggedItems)
		[item insertSubitem:dragged_item atIndex:i++];

	      for (PDLibraryItem *item in reload)
		[_outlineView reloadItem:item reloadChildren:YES];
	    }];

	  if (item == _foldersGroup)
	    [self updateImageLibraries];
	  else
	    [self updateImageAlbums];

	  return YES;
	}
      else if ([item isKindOfClass:[PDLibraryFolder class]])
	{
	  /* -callPreservingSelectedRows: doesn't work as we cause the
	     library items to be destroyed and recreated. */

	  PDImageLibrary *lib = ((PDLibraryFolder *)item).library;

	  NSString *item_dir = ((PDLibraryFolder *)item).libraryDirectory;

	  /* -validateDrop: verified dragged items are PDLibraryFolder. */

	  for (PDLibraryFolder *dragged_item in _draggedItems)
	    {
	      assert(dragged_item.library == lib);

	      NSString *old_dir = dragged_item.libraryDirectory;
	      NSString *new_dir = [item_dir stringByAppendingPathComponent:
				   [old_dir lastPathComponent]];

	      [lib renameDirectory:old_dir to:new_dir];
	      [(PDLibraryFolder *)dragged_item.parent setNeedsUpdate];
	    }

	  [(PDLibraryFolder *)item setNeedsUpdate];
	  [_outlineView reloadItem:_foldersGroup reloadChildren:YES];

	  NSInteger row = [_outlineView rowForItem:item];
	  if (row >= 0)
	    _outlineView.selectedRow = row;

	  return YES;
	}
    }
  else if ([type isEqualToString:PDImageUUIDType])
    {
      PDLibraryItem *parent = ((PDLibraryItem *)item).parent;
      NSArray *uuids = [[pboard readObjectsForClasses:
			 @[[PDImageUUID class]] options:nil]
			mappedArray:^id (id obj) {return [obj UUID];}];
      NSSet *uuid_set = [NSSet setWithArray:uuids];

      if (_dragOperation == NSDragOperationMove)
	{
	  for (PDLibraryItem *sel_item in _selectedItems)
	    {
	      if (sel_item != item
		  && [sel_item isKindOfClass:[PDLibraryAlbum class]])
		{
		  for (NSUUID *uuid in uuids)
		    [(PDLibraryAlbum *)sel_item removeImageWithUUID:uuid];
		}
	    }
	}

      if ([item isKindOfClass:[PDLibraryAlbum class]])
	{
	  for (NSUUID *uuid in uuids)
	    [(PDLibraryAlbum *)item addImageWithUUID:uuid];

	  [self foreachImage:^(PDImage *image, BOOL *stop)
	    {
	      NSUUID *uuid = [image UUIDIfDefined];
	      if (uuid != nil && [uuid_set containsObject:uuid])
		{
		  if (image.deleted)
		    image.deleted = NO;
		}
	    }];

	  [self updateImageAlbums];
	}
      else if (parent == _libraryGroup)
	{
	  [self foreachImage:^(PDImage *image, BOOL *stop)
	    {
	      NSUUID *uuid = [image UUIDIfDefined];
	      if (uuid != nil && [uuid_set containsObject:uuid])
		{
		  BOOL deleted = NO;
		  if (item == _flaggedItem)
		    image.flagged = YES;
		  else if (item == _rejectedItem)
		    image.rating = -1;
		  else if (item == _trashItem)
		    deleted = YES;
		  image.deleted = deleted;
		}
	    }];
	}
      else if ([item isKindOfClass:[PDLibraryFolder class]])
	{
	  PDImageLibrary *dest_lib = ((PDLibraryFolder *)item).library;
	  NSString *dest_dir = ((PDLibraryFolder *)item).libraryDirectory;

	  /* FIXME: need to move these copies to an async queue. */

	  NSMutableArray *move_images = [NSMutableArray array];
	  NSMutableArray *copy_images = [NSMutableArray array];

	  [self foreachImage:^(PDImage *image, BOOL *stop)
	    {
	      NSUUID *uuid = [image UUIDIfDefined];
	      if (uuid != nil && [uuid_set containsObject:uuid])
		{
		  if (_dragOperation == NSDragOperationMove)
		    [move_images addObject:image];
		  else
		    [copy_images addObject:image];
		}
	    }];

	  if (move_images.count != 0)
	    [dest_lib moveImages:move_images toDirectory:dest_dir];
	  if (copy_images.count != 0)
	    [dest_lib copyImages:move_images toDirectory:dest_dir];
	}

      [_outlineView reloadData];
      [self updateImageList:0];

      return YES;
    }

  return NO;
}

// PXSourceListDelegate methods

- (BOOL)sourceList:(PXSourceList *)lst shouldEditItem:(id)item
{
  return ([item isKindOfClass:[PDLibraryFolder class]]
	  || ((PDLibraryItem *)item).parent == _albumsGroup);
}

- (NSCell *)sourceList:(PXSourceList *)lst dataCellForItem:(id)item
{
  if (_controller.importMode
      && [_selectedItems indexOfObjectIdenticalTo:item] != NSNotFound)
    {
      if (_importCell == nil)
	{
	  _importCell = [_normalCell copy];
	  _importCell.iconImage = PDImageWithName(PDImage_ImportFolder);
	}

      return _importCell;
    }
  else
    return _normalCell;
}

- (void)sourceListSelectionDidChange:(NSNotification *)note
{
  if (_ignoreNotifications != 0)
    return;

  BOOL import_mode = _controller.importMode;
  BOOL allow_change = YES;

  if (import_mode)
    {
      for (PDLibraryItem *item in _outlineView.selectedItems)
	{
	  if (item.parent != _devicesGroup)
	    {
	      allow_change = NO;
	      break;
	    }
	}
    }

  if (allow_change)
    {
      [self updateSelectedItems];
      [self updateImageList:PDWindowController_StopPreservingImages];
      [self updateControls];

      if (_controller.filteredImageList.count > 0
	  && _controller.selectedImageIndexes.count == 0)
	{
	  _controller.selectedImageIndexes = [NSIndexSet indexSetWithIndex:0];
	}

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDLibrarySelectionDidChange object:_controller];
    }
  else if (import_mode)
    {
      for (PDLibraryItem *item in _outlineView.selectedItems)
	{
	  if ([item isKindOfClass:[PDLibraryFolder class]])
	    {
	      [_controller setImportDestinationLibrary:
	       ((PDLibraryFolder *)item).library
	       directory:((PDLibraryFolder *)item).libraryDirectory];
	      break;
	    }
	}
    }

  [self scrollSelectionToVisible];
}

// NSPasteboardOwner methods

- (void)pasteboard:(NSPasteboard *)sender provideDataForType:(NSString *)type
{
}

- (void)pasteboardChangedOwner:(NSPasteboard *)sender
{
  if (_draggedPasteboard == sender)
    {
      _draggedItems = nil;
      _draggedPasteboard = nil;
    }
}

@end
