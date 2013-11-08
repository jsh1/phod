// -*- c-style: gnu -*-

#import <AppKit/AppKit.h>

extern NSString *const PDImageListDidChange;
extern NSString *const PDSelectedImagesDidChange;

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

@class PDViewController, PDSplitView;

@interface PDWindowController : NSWindowController <NSSplitViewDelegate>
{
  IBOutlet NSToolbar *_toolbar;
  IBOutlet PDSplitView *_splitView;
  IBOutlet NSSegmentedControl *_sidebarControl;
  IBOutlet NSView *_sidebarView;
  IBOutlet NSView *_contentView;

  NSMutableArray *_viewControllers;

  NSInteger _sidebarMode;
  NSInteger _contentMode;

  NSArray *_imageList;
  NSArray *_selectedImages;
}

@property(nonatomic) NSInteger sidebarMode;
@property(nonatomic) NSInteger contentMode;

@property(nonatomic, copy) NSArray *imageList;
@property(nonatomic, copy) NSArray *selectedImages;

- (PDViewController *)viewControllerWithClass:(Class)cls;

- (void)saveWindowState;
- (void)applySavedWindowState;

- (IBAction)setSidebarModeAction:(id)sender;
- (IBAction)setContentModeAction:(id)sender;

@end
