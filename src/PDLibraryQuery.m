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

#import "PDAppDelegate.h"
#import "PDAppKitExtensions.h"
#import "PDImage.h"
#import "PDWindowController.h"

@implementation PDLibraryQuery

@synthesize name = _name;
@synthesize iconImage = _iconImage;
@synthesize predicate = _predicate;

- (void)dealloc
{
  [_name release];
  [_iconImage release];
  [_predicate release];
  [super dealloc];
}

- (void)foreachSubimage:(void (^)(PDImage *))thunk
{
  if (_predicate != nil)
    {
      PDWindowController *controller
	= [(PDAppDelegate *)[NSApp delegate] windowController];

      [controller foreachImage:^(PDImage *im) {
	if ([_predicate evaluateWithObject:[im expressionValues]])
	  thunk(im);
      }];
    }
}

- (NSString *)titleString
{
  return _name;
}

- (BOOL)hasTitleImage
{
  return YES;
}

- (NSImage *)titleImage
{
  return _iconImage != nil ? _iconImage : PDImageWithName(PDImage_SmartFolder);
}

- (BOOL)hasBadge
{
  return NO;
}

- (NSString *)identifier
{
  return _name;
}

@end
