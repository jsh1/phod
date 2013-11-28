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

#import <AppKit/Appkit.h>

extern NSString *const PDBackgroundActivityDidChange;

@class PDWindowController;

@interface PDAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
{
  IBOutlet PDWindowController *_windowController;
  IBOutlet NSMenu *_photosMenu;
  IBOutlet NSMenu *_imageContextMenu;
  IBOutlet NSMenu *_viewMenu;
  IBOutlet NSMenu *_windowMenu;

  NSMutableSet *_backgroundActivity;
}

@property(nonatomic, readonly) PDWindowController *windowController;

- (IBAction)showWindow:(id)sender;

@property(nonatomic, readonly) BOOL backgroundActivity;

- (void)addBackgroundActivity:(NSString *)name;
- (void)removeBackgroundActivity:(NSString *)name;

- (void)popUpImageContextMenuWithEvent:(NSEvent *)e forView:(NSView *)view;

@end
