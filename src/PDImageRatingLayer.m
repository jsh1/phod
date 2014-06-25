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

#import "PDImageRatingLayer.h"

#import <QuartzCore/QuartzCore.h>

@implementation PDImageRatingLayer

@dynamic rating, flagged, hiddenState;

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"font"])
    return [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
  else if ([key isEqualToString:@"fontSize"])
    return [NSNumber numberWithDouble:[NSFont systemFontSize]];
  else if ([key isEqualToString:@"truncationMode"])
    return @"start";
  else if ([key isEqualToString:@"anchorPoint"])
    return [NSValue valueWithPoint:NSMakePoint(0, 1)];
  else if ([key isEqualToString:@"backgroundColor"])
    return (id)[[NSColor colorWithDeviceWhite:0 alpha:.3] CGColor];
  else
    return [super defaultValueForKey:key];
}

- (void)didChangeValueForKey:(NSString *)key
{
  [super didChangeValueForKey:key];

  if ([key isEqualToString:@"rating"]
      || [key isEqualToString:@"flagged"]
      || [key isEqualToString:@"hiddenState"])
    {
      [self setNeedsLayout];
    }
}

- (void)layoutSublayers
{
  int rating = [self rating];
  BOOL flagged = [self isFlagged];
  BOOL hiddenState = [self hiddenState];

  unichar buf[8];
  size_t len = 0;

  if (rating > 0)
    {
      rating = rating <= 5 ? rating : 5;

      int i;
      for (i = 0; i < rating; i++)
	buf[len++] = 0x2605;		/* BLACK STAR */
    }
  else if (rating < 0)
    {
      buf[len++] = 0x2716;		/* HEAVY MULTIPLICATION X */
    }

  if (flagged)
    {
      if (len != 0)
	buf[len++] = ' ';
      buf[len++] = 0x2691;		/* BLACK FLAG */
    }

  if (hiddenState)
    {
      if (len != 0)
	buf[len++] = ' ';
      buf[len++] = 0x272a;		/* CIRCLED WHITE STAR */
    }

  if (len != 0)
    [self setString:[NSString stringWithCharacters:buf length:len]];
  else
    [self setString:nil];
}

- (CGSize)preferredFrameSize
{
  [self layoutIfNeeded];
  return [super preferredFrameSize];
}

@end
