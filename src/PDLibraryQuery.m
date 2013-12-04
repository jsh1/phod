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

#import "PDLibraryQuery.h"

#import "PDAppKitExtensions.h"

@implementation PDLibraryQuery

@synthesize name = _name;
@synthesize predicate = _predicate;

- (void)dealloc
{
  [_name release];
  [_predicate release];
  [super dealloc];
}

- (NSArray *)subimages
{
  /* FIXME: need to implement this somehow. */

  return [NSArray array];
}

- (NSImage *)titleImage
{
  return PDImageWithName(PDImage_SmartFolder);
}

- (NSString *)titleString
{
  return _name;
}

- (BOOL)hasBadge
{
  return YES;
}

- (NSInteger)badgeValue
{
  return [self numberOfSubimages];
}

- (NSString *)identifier
{
  return _name;
}

@end
