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
extern NSString *const PDImagePredicateDidChange;
extern NSString *const PDImageSortOptionsDidChange;

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

@class PDViewController, PDPredicatePanelController;
@class PDSplitView, PDImage;

@interface PDWindowController : NSWindowController <NSSplitViewDelegate>
{
  IBOutlet PDSplitView *_splitView;
  IBOutlet NSSegmentedControl *_sidebarControl;
  IBOutlet NSView *_sidebarView;
  IBOutlet NSView *_contentView;

  PDPredicatePanelController *_predicatePanelController;

  NSMutableArray *_viewControllers;

  NSInteger _sidebarMode;
  NSInteger _contentMode;

  int _imageSortKey;
  BOOL _imageSortReversed;

  NSString *_imageListTitle;

  NSArray *_imageList;

  NSPredicate *_imagePredicate;
  NSArray *_filteredImageList;

  NSIndexSet *_selectedImageIndexes;
  NSInteger _primarySelectionIndex;
}

@property(nonatomic) NSInteger sidebarMode;
@property(nonatomic) NSInteger contentMode;

@property(nonatomic, readonly) NSArray *allImages;

@property(nonatomic, copy) NSArray *imageList;

@property(nonatomic, copy) NSString *imageListTitle;

- (NSPredicate *)imagePredicateWithFormat:(NSString *)str;

@property(nonatomic, copy) NSPredicate *imagePredicate;

@property(nonatomic) int imageSortKey;
@property(nonatomic, getter=isImageSortReversed) BOOL imageSortReversed;

@property(nonatomic, readonly) NSArray *filteredImageList;

/* Setting the sort key or image predicate does not change the result
   of filteredImageList, this method must be called explicitly. (But
   setting imageList does filter and sort the new array.) */

- (void)rebuildImageList;

@property(nonatomic, copy) NSIndexSet *selectedImageIndexes;
@property NSInteger primarySelectionIndex;
- (void)setSelectedImageIndexes:(NSIndexSet *)set primary:(NSInteger)idx;

/* Convenience wrappers for the index-based selection accessors. */

@property(nonatomic, copy) NSArray *selectedImages;
@property(nonatomic, retain) PDImage *primarySelectedImage;
- (void)setSelectedImages:(NSArray *)array primary:(PDImage *)im;

- (void)clearSelection;
- (void)selectImage:(PDImage *)image withEvent:(NSEvent *)e;

- (void)movePrimarySelectionRight:(NSInteger)delta
    byExtendingSelection:(BOOL)extend;
- (void)movePrimarySelectionDown:(NSInteger)delta rows:(NSInteger)rows
    columns:(NSInteger)cols byExtendingSelection:(BOOL)extend;

- (void)foreachSelectedImage:(void (^)(PDImage *))block;

- (PDViewController *)viewControllerWithClass:(Class)cls;

- (void)saveWindowState;
- (void)applySavedWindowState;

- (IBAction)toggleSidebarAction:(id)sender;
- (BOOL)isSidebarVisible;

- (IBAction)setSidebarModeAction:(id)sender;
- (IBAction)cycleSidebarModeAction:(id)sender;

- (IBAction)setContentModeAction:(id)sender;
- (IBAction)cycleContentModeAction:(id)sender;

- (IBAction)toggleListMetadata:(id)sender;
- (IBAction)toggleImageMetadata:(id)sender;

- (BOOL)displaysListMetadata;
- (BOOL)displaysImageMetadata;

- (IBAction)showPredicatePanel:(id)sender;

- (IBAction)setImageRatingAction:(id)sender;
- (IBAction)addImageRatingAction:(id)sender;

- (IBAction)toggleFlaggedAction:(id)sender;
- (NSInteger)flaggedState;

- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)zoomActualSize:(id)sender;

- (IBAction)rotateLeft:(id)sender;
- (IBAction)rotateRight:(id)sender;

- (IBAction)newSmartFolderAction:(id)sender;

@end
