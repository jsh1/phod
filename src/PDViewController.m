// -*- c-style: gnu -*-

#import "PDViewController.h"

#import "PDWindowController.h"

@implementation PDViewController

@synthesize controller = _controller;
@synthesize viewHasBeenLoaded = _viewHasBeenLoaded;

+ (NSString *)viewNibName
{
  return nil;
}

- (NSString *)identifier
{
  return NSStringFromClass([self class]);
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithNibName:[[self class] viewNibName]
	  bundle:[NSBundle mainBundle]];
  if (self == nil)
    return nil;

  _controller = controller;
  _subviewControllers = [[NSMutableArray alloc] init];

  return self;
}

- (void)dealloc
{
  [_subviewControllers release];
  [super dealloc];
}

- (PDViewController *)viewControllerWithClass:(Class)cls
{
  if ([self class] == cls)
    return self;

  for (PDViewController *obj in _subviewControllers)
    {
      obj = [obj viewControllerWithClass:cls];
      if (obj != nil)
	return obj;
    }

  return nil;
}

- (NSArray *)subviewControllers
{
  return _subviewControllers;
}

- (void)setSubviewControllers:(NSArray *)array
{
  [_subviewControllers release];
  _subviewControllers = [array mutableCopy];
}

- (void)addSubviewController:(PDViewController *)controller
{
  [_subviewControllers addObject:controller];
}

- (void)removeSubviewController:(PDViewController *)controller
{
  NSInteger idx = [_subviewControllers indexOfObjectIdenticalTo:controller];

  if (idx != NSNotFound)
    [_subviewControllers removeObjectAtIndex:idx];
}

- (NSView *)initialFirstResponder
{
  return nil;
}

- (void)viewDidLoad
{
}

- (void)loadView
{
  [super loadView];

  _viewHasBeenLoaded = YES;

  if ([self view] != nil)
    [self viewDidLoad];
}

- (NSDictionary *)savedViewState
{
  if ([_subviewControllers count] == 0)
    return [NSDictionary dictionary];

  NSMutableDictionary *controllers = [NSMutableDictionary dictionary];

  for (PDViewController *controller in _subviewControllers)
    {
      NSDictionary *sub = [controller savedViewState];
      if ([sub count] != 0)
	[controllers setObject:sub forKey:[controller identifier]];
    }

  return [NSDictionary dictionaryWithObjectsAndKeys:
	  controllers, @"PDViewControllers",
	  nil];
}

- (void)applySavedViewState:(NSDictionary *)state
{
  NSDictionary *dict, *sub;

  dict = [state objectForKey:@"PDViewControllers"];

  if (dict != nil)
    {
      for (PDViewController *controller in _subviewControllers)
	{
	  sub = [dict objectForKey:[controller identifier]];
	  if (sub != nil)
	    [controller applySavedViewState:sub];
	}
    }
}

- (void)addToContainerView:(NSView *)superview
{
  NSView *view;

  view = [self view];
  assert([view superview] == nil);
  [view setFrame:[superview bounds]];
  [superview addSubview:view];
}

- (void)removeFromContainer
{
  [[self view] removeFromSuperview];
}

@end
