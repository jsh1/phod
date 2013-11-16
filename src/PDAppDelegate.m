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

#import "PDAppDelegate.h"

#import "PDWindowController.h"

@implementation PDAppDelegate

@synthesize windowController = _windowController;

- (void)dealloc
{
  [_windowController release];

  [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  NSString *path;
  NSData *data;
  NSDictionary *dict;

  path = [[NSBundle mainBundle] pathForResource:@"defaults" ofType:@"plist"];

  if (path != nil)
    {
      data = [NSData dataWithContentsOfFile:path];

      if (data != nil)
	{
	  dict = [NSPropertyListSerialization propertyListWithData:data
		  options:NSPropertyListImmutable format:nil error:nil];

	  if (dict != nil)
	    [[NSUserDefaults standardUserDefaults] registerDefaults:dict];
	}
    }

  [self showWindow:self];
}

- (IBAction)showWindow:(id)sender
{
  [[self windowController] showWindow:sender];
}

// NSMenuDelegate methods

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu == _viewMenu)
    {
      NSInteger sidebarMode = [_windowController sidebarMode];
      NSInteger contentMode = [_windowController contentMode];

      for (NSMenuItem *item in [menu itemArray])
	{
	  SEL sel = [item action];
	  if (sel == @selector(setSidebarModeAction:))
	    [item setState:sidebarMode == [item tag]];
	  else if (sel == @selector(setContentModeAction:))
	    [item setState:contentMode == [item tag]];
	}
    }
}

@end
