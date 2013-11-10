// -*- c-style: gnu -*-

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
    color = [[NSColor colorWithCalibratedHue:BG_HUE saturation:.03 brightness:.5 alpha:1] retain];

  return color;
}

@end
