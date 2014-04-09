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

#import "PDSplitView.h"

@implementation PDSplitView
{
  NSInteger _indexOfResizableSubview;
  NSView *_collapsingSubview;
}

@synthesize indexOfResizableSubview = _indexOfResizableSubview;

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  _indexOfResizableSubview = -1;

  return self;
}

- (id)initWithCoder:(NSCoder *)coder
{
  self = [super initWithCoder:coder];
  if (self == nil)
    return nil;

  _indexOfResizableSubview = -1;

  return self;
}

- (NSDictionary *)savedViewState
{
  NSArray *subviews = [self subviews];
  NSRect bounds = [self bounds];
  BOOL vertical = [self isVertical];
  CGFloat size = vertical ? bounds.size.width : bounds.size.height;

  NSMutableArray *data = [NSMutableArray array];

  for (NSView *subview in subviews)
    {
      NSRect frame = [subview frame];
      CGFloat x = vertical ? frame.origin.x : frame.origin.y;
      CGFloat w = vertical ? frame.size.width : frame.size.height;
      [data addObject:[NSNumber numberWithDouble:x / size]];
      [data addObject:[NSNumber numberWithDouble:w / size]];
      [data addObject:[NSNumber numberWithBool:[subview isHidden]]];
    }

   return @{@"values": data};
}

- (void)applySavedViewState:(NSDictionary *)dict
{
  NSArray *data = [dict objectForKey:@"values"];

  NSArray *subviews = [self subviews];
  NSInteger count = [subviews count];

  if ([data count] != count * 3)
    return;

  NSRect bounds = [self bounds];
  BOOL vertical = [self isVertical];
  CGFloat size = vertical ? bounds.size.width : bounds.size.height;

  for (NSInteger i = 0; i < count; i++)
    {
      CGFloat x = [[data objectAtIndex:i*3+0] doubleValue] * size;
      CGFloat w = [[data objectAtIndex:i*3+1] doubleValue] * size;
      BOOL flag = [[data objectAtIndex:i*3+2] boolValue];

      NSView *subview = [subviews objectAtIndex:i];
      NSRect frame = bounds;

      if (vertical)
	{
	  frame.origin.x = x;
	  frame.size.width = w;
	}
      else
	{
	  frame.origin.y = x;
	  frame.size.height = w;
	}

      [subview setHidden:flag];
      [subview setFrame:frame];
    }

  [self adjustSubviews];
}

- (void)setSubview:(NSView *)subview collapsed:(BOOL)flag
{
  if (flag != [subview isHidden])
    {
      [subview setHidden:flag];

      _collapsingSubview = subview;
      [self adjustSubviews];
      _collapsingSubview = nil;
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)sz
{
  NSArray *subviews = [self subviews];

  if (_indexOfResizableSubview < 0
      || _indexOfResizableSubview >= [subviews count])
    {
      [self adjustSubviews];
      return;
    }

  NSRect bounds = [self bounds];
  NSInteger count = [subviews count];
  BOOL vertical = [self isVertical];
  CGFloat thick = [self dividerThickness];
  CGFloat p = vertical ? bounds.origin.x : bounds.origin.y;

  for (NSInteger idx = 0; idx < count; idx++)
    {
      NSView *view = [subviews objectAtIndex:idx];
      if ([view isHidden])
	continue;

      NSRect frame = [view frame];

      if (vertical)
	frame.origin.y = bounds.origin.y, frame.size.height=bounds.size.height;
      else
	frame.origin.x = bounds.origin.x, frame.size.width = bounds.size.width;

      if (vertical)
	frame.origin.x = p;
      else
	frame.origin.y = p;

      if (idx == _indexOfResizableSubview)
	{
	  if (vertical)
	    frame.size.width += bounds.size.width - sz.width;
	  else
	    frame.size.height += bounds.size.height - sz.height;
	}

      [view setFrame:frame];

      if (vertical)
	p += frame.size.width + thick;
      else
	p += frame.size.height + thick;
    }
}

- (BOOL)shouldAdjustSizeOfSubview:(NSView *)subview
{
  if (_collapsingSubview != nil)
    {
      if (subview == _collapsingSubview)
	return NO;

      // If more than two subviews, only move those adjacent to the
      // [un]collapsing view.

      NSArray *subviews = [self subviews];
      NSInteger idx1 = [subviews indexOfObjectIdenticalTo:_collapsingSubview];
      NSInteger idx2 = [subviews indexOfObjectIdenticalTo:subview];

      if (abs(idx1 - idx2) > 1)
	return NO;
    }

  return YES;
}

- (CGFloat)minimumSizeOfSubview:(NSView *)subview
{
  id delegate = [self delegate];

  if ([delegate respondsToSelector:@selector(splitView:minimumSizeOfSubview:)])
    return [delegate splitView:self minimumSizeOfSubview:subview];
  else
    return 100;
}

@end
