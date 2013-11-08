// -*- c-style: gnu -*-

#import <AppKit/AppKit.h>

@class PDWindowController;

@interface PDViewController : NSViewController
{
  PDWindowController *_controller;

@private
  NSMutableArray *_subviewControllers;
  BOOL _viewHasBeenLoaded;
}

+ (NSString *)viewNibName;
- (NSString *)identifier;

- (id)initWithController:(PDWindowController *)controller;

@property(nonatomic, readonly) BOOL viewHasBeenLoaded;

- (void)viewDidLoad;

@property(nonatomic, readonly) PDWindowController *controller;

- (PDViewController *)viewControllerWithClass:(Class)cls;

@property(nonatomic, copy) NSArray *subviewControllers;

- (void)addSubviewController:(PDViewController *)controller;
- (void)removeSubviewController:(PDViewController *)controller;

@property(nonatomic, readonly) NSView *initialFirstResponder;

- (NSDictionary *)savedViewState;
- (void)applySavedViewState:(NSDictionary *)dict;

- (void)addToContainerView:(NSView *)view;
- (void)removeFromContainer;

@end
