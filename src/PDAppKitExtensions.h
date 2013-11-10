// -*- c-style: gnu -*-

#import <AppKit/AppKit.h>

@interface NSCell (PDAppKitExtensions)

@property(getter=isVerticallyCentered) BOOL verticallyCentered;
  
@end


@interface NSTableView (PDAppKitExtensions)

- (void)reloadDataForRow:(NSInteger)row;

@end
