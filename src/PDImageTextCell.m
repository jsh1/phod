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

#import "PDImageTextCell.h"

#define BORDER 1
#define SPACING 2

@implementation PDImageTextCell
{
  NSImage *_image;
}

@synthesize image = _image;

- (CGFloat)imageWidthForHeight:(CGFloat)h
{
  NSSize size = [_image size];
  return size.width * (h / size.height);
}

- (NSSize)cellSize
{
  NSSize size = [super cellSize];
  if (_image != nil)
    size.width += BORDER + [self imageWidthForHeight:size.height] + SPACING;
  return size;
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
  if (_image != nil)
    {
      NSRect imageFrame = frame;
      CGFloat width = [self imageWidthForHeight:frame.size.height];
      imageFrame.origin.x += BORDER;
      imageFrame.size.width = fmin(width, imageFrame.size.width);
      frame.origin.x += BORDER + width + SPACING;
      frame.size.width -= width + SPACING;
      [_image drawInRect:imageFrame fromRect:NSZeroRect operation:
       NSCompositeSourceOver fraction:1 respectFlipped:YES hints:nil];
    }

  if (frame.size.width > 0)
    [super drawWithFrame:frame inView:view];
}

@end
