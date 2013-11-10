// -*- c-style: gnu -*-

#import "PDAdjustmentsViewController.h"

#import "PDWindowController.h"

@implementation PDAdjustmentsViewController

+ (NSString *)viewNibName
{
  return @"PDAdjustmentsView";
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
