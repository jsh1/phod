// -*- c-style: gnu -*-

#import <AppKit/Appkit.h>

@class PDWindowController;

@interface PDAppDelegate : NSObject <NSApplicationDelegate>
{
  IBOutlet PDWindowController *_windowController;
}

@property(readonly) PDWindowController *windowController;

- (IBAction)showWindow:(id)sender;

@end
