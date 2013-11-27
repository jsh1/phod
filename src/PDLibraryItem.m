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

@implementation PDLibraryItem

@synthesize hidden = _hidden;

- (BOOL)applySearchString:(NSString *)str
{
  BOOL matches = NO;

  for (PDLibraryItem *item in [self subitems])
    {
      if ([item applySearchString:str])
	matches = YES;
    }

  NSString *title = [self titleString];

  if (title != nil)
    {
      if ([title rangeOfString:str options:NSCaseInsensitiveSearch].length > 0)
	matches = YES;
    }

  [self setHidden:!matches];

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

- (NSArray *)subimages
{
  return [NSArray array];
}

- (NSInteger)numberOfSubimages
{
  return [[self subimages] count];
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

- (NSString *)identifier
{
  return [self titleString];
}

- (BOOL)needsUpdate
{
  return NO;
}

@end
