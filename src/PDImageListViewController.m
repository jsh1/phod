// -*- c-style: gnu -*-

#import "PDImageListViewController.h"

#import "PDWindowController.h"

@implementation PDImageListViewController

+ (NSString *)viewNibName
{
  return @"PDImageListView";
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
