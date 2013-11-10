// -*- c-style: gnu -*-

#import "PDViewController.h"

@class PDImageGridView;

@interface PDImageListViewController : PDViewController
{
  IBOutlet NSScrollView *_scrollView;
  IBOutlet PDImageGridView *_gridView;
  IBOutlet NSSlider *_scaleSlider;
}

- (IBAction)controlAction:(id)sender;

@end

@interface PDImageGridView : NSView
{
  IBOutlet PDImageListViewController *_controller;

  NSArray *_images;
  NSIndexSet *_selection;
  CGFloat _scale;

  CGFloat _size;
  NSInteger _columns;
  NSInteger _rows;
}

@property(nonatomic, copy) NSArray *images;
@property(nonatomic, copy) NSIndexSet *selection;
@property(nonatomic) CGFloat scale;

@end
