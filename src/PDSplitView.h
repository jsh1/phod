// -*- c-style: gnu -*-

#import <AppKit/AppKit.h>

@interface PDSplitView : NSSplitView
{
@private
  NSInteger _indexOfResizableSubview;
  NSView *_collapsingSubview;
}

@property NSInteger indexOfResizableSubview;

- (NSDictionary *)savedViewState;
- (void)applySavedViewState:(NSDictionary *)dict;

- (void)setSubview:(NSView *)subview collapsed:(BOOL)flag;

- (BOOL)shouldAdjustSizeOfSubview:(NSView *)subview;

- (CGFloat)minimumSizeOfSubview:(NSView *)subview;

@end

@interface NSView (PDSplitView)

- (CGFloat)minSize;

@end
