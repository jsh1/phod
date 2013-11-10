// -*- c-style: gnu -*-

#import "PDInfoViewController.h"

#import "PDWindowController.h"

@implementation PDInfoViewController

+ (NSString *)viewNibName
{
  return @"PDInfoView";
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
