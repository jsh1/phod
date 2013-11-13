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

#import "PDImageView.h"

#import "PDAppKitExtensions.h"
#import "PDColor.h"
#import "PDImageViewController.h"
#import "PDLibraryImage.h"
#import "PDWindowController.h"

@implementation PDImageView

@synthesize image = _image;

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (void)updateLayer
{
  CALayer *layer = [self layer];

  [layer setBackgroundColor:[[PDColor imageGridBackgroundColor] CGColor]];

  /* FIXME: something */
}

- (BOOL)isFlipped
{
  return YES;
}

- (void)mouseDown:(NSEvent *)e
{
  switch ([e clickCount])
    {
    case 2:
      [[_controller controller] setContentMode:PDContentMode_List];
      break;
    }
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)keyDown:(NSEvent *)e
{
  NSString *chars = [e charactersIgnoringModifiers];
  if ([chars length] < 1)
    return;

  switch ([chars characterAtIndex:0])
    {
    case NSLeftArrowFunctionKey:
      [[_controller controller] movePrimarySelectionRight:-1
       byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
      break;

    case NSRightArrowFunctionKey:
      [[_controller controller] movePrimarySelectionRight:1
       byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
      break;

#if 0
    case NSUpArrowFunctionKey:
      [[_controller controller] movePrimarySelectionDown:-1
       rows:_rows columns:_columns
       byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
      break;

    case NSDownArrowFunctionKey:
      [[_controller controller] movePrimarySelectionDown:1
       rows:_rows columns:_columns
       byExtendingSelection:([e modifierFlags] & NSShiftKeyMask) != 0];
      break;
#endif

    default:
      [super keyDown:e];
    }
}

@end
