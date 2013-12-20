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

#import "PDViewController.h"

#import "PXSourceListDataSource.h"
#import "PXSourceListDelegate.h"

/* posted to window controller. */
extern NSString *const PDLibrarySelectionDidChange;

@class PDLibraryGroup, PDImage, PDImageLibrary, PDImageTextCell, PDLibraryItem;

@interface PDLibraryViewController : PDViewController
    <PXSourceListDataSource, PXSourceListDelegate>
{
  IBOutlet PXSourceList *_outlineView;
  IBOutlet PDImageTextCell *_normalCell;
  IBOutlet PDImageTextCell *_importCell;
  IBOutlet NSSearchField *_searchField;
  IBOutlet NSButton *_addButton;
  IBOutlet NSButton *_removeButton;
  IBOutlet NSButton *_importButton;
  IBOutlet NSButton *_actionButton;

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

- (BOOL)foreachImage:(void (^)(PDImage *im, BOOL *stop))thunk;

- (void)selectLibrary:(PDImageLibrary *)lib directory:(NSString *)dir;

- (IBAction)nextLibraryItemAction:(id)sender;
- (IBAction)previousLibraryItemAction:(id)sender;
- (IBAction)parentLibraryItemAction:(id)sender;
- (IBAction)firstLibraryChildItemAction:(id)sender;
- (IBAction)expandLibraryItemAction:(id)sender;
- (IBAction)collapseLibraryItemAction:(id)sender;

- (void)rescanVolumes;

- (IBAction)addLibraryAction:(id)sender;
- (IBAction)newAlbumAction:(id)sender;

- (void)addSmartAlbum:(NSString *)name predicate:(NSPredicate *)pred;

- (IBAction)removeAction:(id)sender;
- (IBAction)searchAction:(id)sender;
- (IBAction)importAction:(id)sender;

- (IBAction)delete:(id)sender;

- (IBAction)controlAction:(id)sender;

@end
