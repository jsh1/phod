// -*- c-style: gnu -*-

#import "PDImageViewController.h"

#import "PDWindowController.h"

@implementation PDImageViewController

- (NSString *)viewNibName
{
  return @"PDImageView";
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
