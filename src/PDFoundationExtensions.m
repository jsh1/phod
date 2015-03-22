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

#if __has_feature(objc_arc)
#error "Must be compiled with -fno-objc-arc"
#endif

#import "PDFoundationExtensions.h"

#import "PDMacros.h"

@implementation NSObject (PDFoundationExtensions)

- (void)performVoidSelector:(SEL)sel withObject:(id)arg
{
  [self performSelector:sel withObject:arg];
}

@end

@implementation NSArray (PDFoundationExtensions)

- (NSArray *)mappedArray:(id (^)(id))f
{
  NSInteger count = self.count;
  if (count == 0)
    return @[];

  id *objects = STACK_ALLOC(id, count);

  NSInteger i = 0;
  for (id obj in self)
    objects[i++] = f(obj);

  NSArray *ret = [NSArray arrayWithObjects:objects count:count];

  STACK_FREE(id, count, objects);

  return ret;
}

- (NSArray *)filteredArray:(BOOL (^)(id))f
{
  NSInteger count = self.count;
  if (count == 0)
    return @[];
  
  id *objects = STACK_ALLOC(id, count);

  NSInteger idx = 0;
  for (id obj in self)
    {
      if (f(obj))
	objects[idx++] = obj;
    }

  NSArray *ret;
  if (idx == 0)
    ret = @[];
  else
    ret = [NSArray arrayWithObjects:objects count:idx];

  STACK_FREE(id, count, objects);

  return ret;
}

@end


@implementation NSString (PDFoundationExtensions)

- (BOOL)hasPathPrefix:(NSString *)path
{
  NSInteger l1 = self.length;
  NSInteger l2 = path.length;

  if (l2 == 0)
    return YES;
  else if (l1 == l2)
    return [self isEqualToString:path];
  else if (l2 > l1)
    return NO;
  else
    return [self characterAtIndex:l2] == '/' && [self hasPrefix:path];
}

- (NSString *)stringByRemovingPathPrefix:(NSString *)path
{
  NSInteger l1 = self.length;
  NSInteger l2 = path.length;

  if (l2 == 0)
    return self;
  else if (l1 == l2)
    return [self isEqualToString:path] ? @"" : self;
  else if (l2 > l1)
    return self;
  else
    return ([self characterAtIndex:l2] == '/' && [self hasPrefix:path]
	    ? [self substringFromIndex:l2+1] : self);
}

@end
