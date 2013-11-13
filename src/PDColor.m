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

#import "PDColor.h"

#define BG_HUE (202./360.)

@implementation PDColor

+ (NSColor *)windowBackgroundColor
{
  return [NSColor colorWithDeviceWhite:.85 alpha:1];
}

+ (NSColor *)controlTextColor
{
  static NSColor *color;

  if (color == nil)
    color = [[NSColor colorWithDeviceWhite:.25 alpha:1] retain];

  return color;
}

+ (NSColor *)disabledControlTextColor
{
  static NSColor *color;

  if (color == nil)
    color = [[NSColor colorWithDeviceWhite:.45 alpha:1] retain];

  return color;
}

+ (NSColor *)controlTextColor:(BOOL)disabled
{
  return !disabled ? [self controlTextColor] : [self disabledControlTextColor];
}

+ (NSColor *)controlDetailTextColor
{
  static NSColor *color;

  if (color == nil)
    {
      color = [[NSColor colorWithDeviceRed:197/255. green:56/255.
		blue:51/255. alpha:1] retain];
    }

  return color;
}

+ (NSColor *)disabledControlDetailTextColor
{
  static NSColor *color;

  if (color == nil)
    {
      color = [[NSColor colorWithDeviceRed:197/255. green:121/255.
		blue:118/255. alpha:1] retain];
    }

  return color;
}

+ (NSColor *)controlDetailTextColor:(BOOL)disabled
{
  return !disabled ? [self controlDetailTextColor] : [self disabledControlDetailTextColor];
}

+ (NSColor *)controlBackgroundColor
{
  static NSColor *color;

  if (color == nil)
    color = [[NSColor colorWithCalibratedHue:BG_HUE saturation:.01 brightness:.96 alpha:1] retain];

  return color;
}

+ (NSColor *)darkControlBackgroundColor
{
  static NSColor *color;

  if (color == nil)
    color = [[NSColor colorWithCalibratedHue:BG_HUE saturation:.03 brightness:.91 alpha:1] retain];

  return color;
}

+ (NSArray *)controlAlternatingRowBackgroundColors
{
  static NSArray *colors;

  if (colors == nil)
    {
      colors = [[NSArray alloc] initWithObjects:
		[self controlBackgroundColor],
		[self darkControlBackgroundColor],
		nil];
    }

  return colors;
}

+ (NSColor *)imageGridBackgroundColor
{
  static NSColor *color;

  if (color == nil)
    color = [[NSColor colorWithCalibratedHue:BG_HUE saturation:.03 brightness:.4 alpha:1] retain];

  return color;
}

@end
