// -*- c-style: gnu -*-

#import "PDLibraryViewController.h"

#import "PDWindowController.h"

@implementation PDLibraryViewController

- (NSString *)viewNibName
{
  return @"PDLibraryView";
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
}

@end
