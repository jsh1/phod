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

#import "PDMetadataView.h"

#import "PDInfoViewController.h"
#import "PDMetadataItemView.h"
#import "PDWindowController.h"

#define ITEM_Y_SPACING 2
#define X_INSET 8
#define Y_INSET 8

@implementation PDMetadataView

@synthesize controller = _controller;

- (NSArray *)imageProperties
{
  NSMutableArray *array = [NSMutableArray array];

  for (PDMetadataItemView *item in self.subviews)
    {
      NSString *name = item.imageProperty;
      if ([name length] != 0)
	[array addObject:name];
    }

  return array;
}

- (void)setImageProperties:(NSArray *)array
{
  NSMutableArray *old_subviews = [[self subviews] mutableCopy];
  NSMutableArray *new_subviews = [NSMutableArray array];

  for (NSString *key in array)
    {
      PDMetadataItemView *new_subview = nil;

      NSInteger old_idx = 0;
      for (PDMetadataItemView *old_subview in old_subviews)
	{
	  if ([old_subview.imageProperty isEqualToString:key])
	    {
	      new_subview = old_subview;
	      [old_subviews removeObjectAtIndex:old_idx];
	      break;
	    }
	  old_idx++;
	}

      if (new_subview == nil)
	{
	  new_subview = [[PDMetadataItemView alloc] initWithFrame:NSZeroRect];
	  new_subview.metadataView = self;
	  new_subview.imageProperty = key;
	  new_subview.autoresizingMask = NSViewWidthSizable;
	}

      [new_subviews addObject:new_subview];
    }

  self.subviews = new_subviews;

  CGRect frame = self.frame;
  frame.size.height = [self heightForWidth:frame.size.width];
  [self setFrameSize:frame.size];
  [self layoutSubviews];

  for (PDMetadataItemView *subview in self.subviews)
    [subview update];
}

- (void)update
{
  for (PDMetadataItemView *subview in self.subviews)
    [subview update];
}

- (CGFloat)heightForWidth:(CGFloat)width
{
  CGFloat h = 0;

  for (PDMetadataItemView *item in self.subviews)
    {
      if (h != 0)
	h += ITEM_Y_SPACING;
      h += [item preferredHeight];
    }

  return h + Y_INSET * 2;
}

- (void)layoutSubviews
{
  CGRect bounds = CGRectInset(self.bounds, X_INSET, Y_INSET);
  CGFloat y = 0;

  for (PDMetadataItemView *item in self.subviews)
    {
      CGRect frame;
      CGFloat h = [item preferredHeight];
      frame.origin.x = bounds.origin.x;
      frame.origin.y = bounds.origin.y + y;
      frame.size.width = bounds.size.width;
      frame.size.height = h;
      item.frame = frame;
      [item layoutSubviews];
      y += h + ITEM_Y_SPACING;
    }
}

- (NSString *)localizedImagePropertyForKey:(NSString *)key
{
  return [_controller localizedImagePropertyForKey:key];
}

- (void)setLocalizedImageProperty:(NSString *)str forKey:(NSString *)key
{
  [_controller setLocalizedImageProperty:str forKey:key];
}

- (IBAction)controlAction:(id)sender
{
}

- (BOOL)isFlipped
{
  return YES;
}

@end
