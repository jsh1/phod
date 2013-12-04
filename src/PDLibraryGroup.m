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

#import "PDLibraryGroup.h"

@implementation PDLibraryGroup

@synthesize name = _name;

- (void)dealloc
{
  [_name release];
  for (PDLibraryItem *item in _subitems)
    [item setParent:nil];
  [_subitems release];
  [super dealloc];
}

- (NSArray *)subitems
{
  return _subitems != nil ? _subitems : [NSArray array];
}

- (void)setSubitems:(NSArray *)array
{
  if (_subitems != array)
    {
      for (PDLibraryItem *item in _subitems)
	[item setParent:nil];

      [_subitems release];
      _subitems = [array mutableCopy];

      for (PDLibraryItem *item in _subitems)
	[item setParent:self];
    }
}

- (void)addSubitem:(PDLibraryItem *)item
{
  if (_subitems == nil
      || [_subitems indexOfObjectIdenticalTo:item] == NSNotFound)
    {
      if (_subitems == nil)
	_subitems = [[NSMutableArray alloc] init];
      [_subitems addObject:item];
      [item setParent:self];
    }
}

- (void)removeSubitem:(PDLibraryItem *)item
{
  if (_subitems != nil)
    {
      NSInteger idx = [_subitems indexOfObjectIdenticalTo:item];
      if (idx != NSNotFound)
	{
	  [item setParent:nil];
	  [_subitems removeObjectAtIndex:idx];
	}
    }
}

- (NSString *)titleString
{
  return _name;
}

- (BOOL)isExpandable
{
  return YES;
}

@end
