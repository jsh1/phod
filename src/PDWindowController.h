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

#import <AppKit/AppKit.h>

extern NSString *const PDImageListDidChange;
extern NSString *const PDSelectionDidChange;
extern NSString *const PDShowsHiddenImagesDidChange;
extern NSString *const PDImagePredicateDidChange;
extern NSString *const PDImageSortOptionsDidChange;
extern NSString *const PDImportModeDidChange;
extern NSString *const PDTrashWasEmptied;

enum PDSidebarMode
{
  PDSidebarMode_Nil,
  PDSidebarMode_Library,
  PDSidebarMode_Info,
  PDSidebarMode_Adjustments,
};

enum PDContentMode
{
  PDContentMode_Nil,
  PDContentMode_List,
  PDContentMode_Image,
};

enum PDAccessoryMode
{
  PDAccessoryMode_Nil,
  PDAccessoryMode_Import,
};

enum PDWindowControllerRebuildImageListFlags
{
  PDWindowController_PreserveSelectedImages	= 1U << 0,
  PDWindowController_StopPreservingImages	= 1U << 1,
};

@class PDViewController, PDPredicatePanelController;
@class PDSplitView, PDImage, PDImageLibrary;

@interface PDWindowController : NSWindowController <NSSplitViewDelegate>

@property(nonatomic, weak) IBOutlet PDSplitView *splitView;
@property(nonatomic, weak) IBOutlet NSSegmentedControl *sidebarControl;
@property(nonatomic, weak) IBOutlet NSView *sidebarView;
@property(nonatomic, weak) IBOutlet NSView *contentView;
@property(nonatomic, weak) IBOutlet NSView *accessoryView;

- (void)invalidate;

@property(nonatomic, assign) NSInteger sidebarMode;
@property(nonatomic, assign) NSInteger contentMode;
@property(nonatomic, assign) NSInteger accessoryMode;

@property(nonatomic, assign) BOOL showsHiddenImages;

- (BOOL)foreachImage:(void (^)(PDImage *, BOOL *stop))thunk;

/* Setting the 'imageList' doesn't call -rebuildImageList implicitly,
   callers must do that explicitly, to update 'filteredImageList'. */

@property(nonatomic, copy) NSArray *imageList;

@property(nonatomic, copy) NSString *imageListTitle;

- (NSPredicate *)imagePredicateWithFormat:(NSString *)str, ...;
- (NSPredicate *)imagePredicateWithFormat:(NSString *)str argv:(va_list)args;

@property(nonatomic, copy) NSPredicate *imagePredicate;

@property(nonatomic, assign) BOOL nilPredicateIncludesRejected;

@property(nonatomic, assign) int imageSortKey;
@property(nonatomic, assign, getter=isImageSortReversed) BOOL imageSortReversed;

@property(nonatomic, copy, readonly) NSArray *filteredImageList;

/* Setting the sort key or image predicate does not change the result
   of filteredImageList, this method must be called explicitly. (But
   setting imageList does filter and sort the new array.) */

- (void)rebuildImageList:(uint32_t)flags;
- (void)rebuildImageListIfPreserving;

@property(nonatomic, copy) NSIndexSet *selectedImageIndexes;
@property(nonatomic, assign) NSInteger primarySelectionIndex;
- (void)setSelectedImageIndexes:(NSIndexSet *)set primary:(NSInteger)idx;

/* Convenience wrappers for the index-based selection accessors. */

@property(nonatomic, copy) NSArray *selectedImages;
@property(nonatomic, retain) PDImage *primarySelectedImage;
- (void)setSelectedImages:(NSArray *)array primary:(PDImage *)im;

- (void)selectImage:(PDImage *)image withEvent:(NSEvent *)e;

- (void)movePrimarySelectionRight:(NSInteger)delta
    byExtendingSelection:(BOOL)extend;
- (void)movePrimarySelectionDown:(NSInteger)delta rows:(NSInteger)rows
    columns:(NSInteger)cols byExtendingSelection:(BOOL)extend;

- (void)selectAll:(id)sender;
- (void)deselectAll:(id)sender;

- (void)selectFirstByExtendingSelection:(BOOL)flag;
- (void)selectLastByExtendingSelection:(BOOL)flag;

- (void)selectLibrary:(PDImageLibrary *)lib directory:(NSString *)dir;

- (IBAction)nextLibraryItemAction:(id)sender;
- (IBAction)previousLibraryItemAction:(id)sender;
- (IBAction)parentLibraryItemAction:(id)sender;
- (IBAction)firstLibraryChildItemAction:(id)sender;
- (IBAction)expandLibraryItemAction:(id)sender;
- (IBAction)collapseLibraryItemAction:(id)sender;
- (IBAction)expandCollapseLibraryItemAction:(id)sender;

- (void)foreachSelectedImage:(void (^)(PDImage *))block;

@property(nonatomic, assign) BOOL importMode;

- (void)setImportDestinationLibrary:(PDImageLibrary *)lib
    directory:(NSString *)dir;

- (PDViewController *)viewControllerWithClass:(Class)cls;

- (void)contentKeyDown:(NSEvent *)e makeKey:(BOOL)flag;

- (void)synchronize;

- (void)saveWindowState;
- (void)applySavedWindowState;

- (IBAction)toggleSidebarAction:(id)sender;
@property(nonatomic, assign, readonly, getter=isSidebarVisible) BOOL sidebarVisible;

- (IBAction)setSidebarModeAction:(id)sender;
- (IBAction)cycleSidebarModeAction:(id)sender;

- (IBAction)setContentModeAction:(id)sender;
- (IBAction)cycleContentModeAction:(id)sender;

- (IBAction)toggleListMetadata:(id)sender;
- (IBAction)toggleImageMetadata:(id)sender;

- (BOOL)displaysListMetadata;
- (BOOL)displaysImageMetadata;

- (IBAction)toggleShowsHiddenImages:(id)sender;

- (IBAction)showPredicatePanel:(id)sender;

- (IBAction)setImageRatingAction:(id)sender;
- (IBAction)addImageRatingAction:(id)sender;

- (IBAction)setRatingPredicateAction:(id)sender;

- (IBAction)toggleFlaggedAction:(id)sender;
- (NSInteger)flaggedState;

- (IBAction)toggleHiddenAction:(id)sender;
- (NSInteger)hiddenState;

- (IBAction)copy:(id)sender;
- (IBAction)cut:(id)sender;

- (IBAction)delete:(id)sender;
- (IBAction)toggleDeletedAction:(id)sender;
- (NSInteger)deletedState;

- (IBAction)toggleRawAction:(id)sender;
- (NSInteger)rawState;

@property(nonatomic, assign, readonly, getter=isToggleRawSupported) BOOL toggleRawSupported;

- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomActualSize:(id)sender;
- (IBAction)zoomToFill:(id)sender;

- (IBAction)rotateLeft:(id)sender;
- (IBAction)rotateRight:(id)sender;

- (IBAction)addLibraryAction:(id)sender;
- (IBAction)newFolderAction:(id)sender;
- (IBAction)newAlbumAction:(id)sender;
- (IBAction)newSmartAlbumAction:(id)sender;
- (IBAction)importAction:(id)sender;

- (IBAction)emptyTrashAction:(id)sender;

- (IBAction)reloadLibraries:(id)sender;

@property(nonatomic, assign, readonly, getter=isTrashEmpty) BOOL trashEmpty;

@end
