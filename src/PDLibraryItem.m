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

#import "PDLibraryItem.h"

NSString * const PDLibraryItemSubimagesDidChange = @"PDLibraryItemSubimagesDidChange";

@implementation PDLibraryItem

@synthesize parent = _parent;
@synthesize hidden = _hidden;

- (BOOL)applySearchString:(NSString *)str
{
  BOOL matches = NO;

  for (PDLibraryItem *item in [self subitems])
    {
      if ([item applySearchString:str])
	matches = YES;
    }

  return matches;
}

- (void)resetSearchState
{
  [self setHidden:NO];

  for (PDLibraryItem *item in [self subitems])
    [item resetSearchState];
}

- (void)recursivelyClearHiddenState
{
  [self setHidden:NO];

  for (PDLibraryItem *item in [self subitems])
    [item recursivelyClearHiddenState];
}

- (NSArray *)subitems
{
  return [NSArray array];
}

- (BOOL)foreachSubitem:(void (^)(PDLibraryItem *item, BOOL *stop))thunk
{
  BOOL stop = NO;
  thunk(self, &stop);
  if (stop)
    return NO;

  for (PDLibraryItem *subitem in [self subitems])
    {
      if (![subitem foreachSubitem:thunk])
	return NO;
    }

  return YES;
}

- (BOOL)foreachSubimage:(void (^)(PDImage *im, BOOL *stop))thunk
{
  for (PDLibraryItem *subitem in [self subitems])
    {
      if (![subitem isHidden])
	{
	  if (![subitem foreachSubimage:thunk])
	    return NO;
	}
    }

  return YES;
}

- (BOOL)isTrashcan
{
  return NO;
}

- (BOOL)nilPredicateIncludesRejected
{
  return NO;
}

- (BOOL)hasTitleImage
{
  return [self titleImage] != nil;
}

- (NSImage *)titleImage
{
  return nil;
}

- (NSString *)titleString
{
  return nil;
}

- (BOOL)isExpandable
{
  return NO;
}

- (BOOL)hasBadge
{
  return NO;
}

- (NSInteger)badgeValue
{
  return 0;
}

- (BOOL)badgeValueIsNumberOfSubimages
{
  return NO;
}

- (NSString *)identifier
{
  return [self titleString];
}

- (void)unmount
{
}

- (BOOL)isDescendantOf:(PDLibraryItem *)item
{
  for (PDLibraryItem *tem = self; tem != nil; tem = [tem parent])
    {
      if (tem == item)
	return YES;
    }

  return NO;
}

- (void)setNeedsUpdate
{
}

@end
