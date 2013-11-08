// -*- c-style: gnu -*-

#import "PDAppDelegate.h"

#import "PDWindowController.h"

@implementation PDAppDelegate

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

@end
