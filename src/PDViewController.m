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

#import "PDViewController.h"

#import "PDAppDelegate.h"
#import "PDWindowController.h"

@implementation PDViewController
{
  NSMutableArray *_subviewControllers;
  BOOL _pendingProgressUpdate;
}

@synthesize controller = _controller;

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
  if (self != nil)
    {
      _controller = controller;
      _subviewControllers = [[NSMutableArray alloc] init];
    }
  return self;
}

- (void)invalidate
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  for (PDViewController *controller in _subviewControllers)
    [controller invalidate];
}

- (void)dealloc
{
  [self invalidate];
}

- (PDViewController *)viewControllerWithClass:(Class)cls
{
  if ([self class] == cls)
    return self;

  for (PDViewController *obj in _subviewControllers)
    {
      PDViewController *tem = [obj viewControllerWithClass:cls];
      if (tem != nil)
	return tem;
    }

  return nil;
}

- (NSArray *)subviewControllers
{
  return _subviewControllers;
}

- (void)setSubviewControllers:(NSArray *)array
{
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
  NSView *view = [self view];
  return [view acceptsFirstResponder] ? view : nil;
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  if (_progressIndicator != nil)
    {
      [[NSNotificationCenter defaultCenter]
       addObserver:self selector:@selector(_backgroundActivityDidChange:)
       name:PDBackgroundActivityDidChange object:[NSApp delegate]];
    }
}

- (void)viewWillAppear
{
}

- (void)viewDidAppear
{
}

- (void)viewWillDisappear
{
}

- (void)viewDidDisappear
{
}

- (void)synchronize
{
  for (PDViewController *controller in _subviewControllers)
    [controller synchronize];
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
	controllers[controller.identifier] = sub;
    }

  return @{
    @"PDViewControllers": controllers
  };
}

- (void)applySavedViewState:(NSDictionary *)state
{
  NSDictionary *dict = state[@"PDViewControllers"];
  if (dict != nil)
    {
      for (PDViewController *controller in _subviewControllers)
	{
	  NSDictionary *sub = dict[controller.identifier];
	  if (sub != nil)
	    [controller applySavedViewState:sub];
	}
    }
}

- (void)addToContainerView:(NSView *)superview
{
  NSView *view = [self view];
  assert([view superview] == nil);

  view.frame = superview.bounds;

  [self viewWillAppear];

  [superview addSubview:view];

  [self viewDidAppear];
}

- (void)removeFromContainer
{
  [self viewWillDisappear];

  [self.view removeFromSuperview];

  [self viewDidDisappear];
}

- (void)_backgroundActivityDidChange:(NSNotification *)note
{
  PDAppDelegate *delegate = (id)[NSApp delegate];

  BOOL state = delegate.backgroundActivity;

  if (!state)
    {
      [_progressIndicator stopAnimation:self];
    }
  else
    {
      if (!_pendingProgressUpdate)
	{
	  dispatch_time_t t
	    = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4);

	  dispatch_after(t, dispatch_get_main_queue(), ^
	    {
	      _pendingProgressUpdate = NO;

	      if (delegate.backgroundActivity)
		[_progressIndicator startAnimation:self];
	      else
		[_progressIndicator stopAnimation:self];
	    });

	  _pendingProgressUpdate = YES;
	}
    }
}

@end
