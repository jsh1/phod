// -*- c-style: gnu -*-

#import "PDViewController.h"

@interface PDLibraryViewController : PDViewController
    <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
  IBOutlet NSOutlineView *_outlineView;

  NSMutableArray *_items;
}

@end
