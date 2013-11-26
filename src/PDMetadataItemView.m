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

#import "PDMetadataItemView.h"

#import "PDColor.h"
#import "PDImage.h"
#import "PDMetadataView.h"

#define LABEL_WIDTH 120
#define LABEL_HEIGHT 14
#define SPACING 8

#define CONTROL_HEIGHT LABEL_HEIGHT

@implementation PDMetadataItemView

@synthesize metadataView = _metadataView;

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  NSFont *font1 = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];

  _labelField = [[NSTextField alloc] initWithFrame:
		 NSMakeRect(0, 0, LABEL_WIDTH, LABEL_HEIGHT)];
  [_labelField setTarget:self];
  [_labelField setAction:@selector(controlAction:)];
  [_labelField setDelegate:self];
  [_labelField setDrawsBackground:NO];
  [_labelField setEditable:NO];
  [_labelField setAlignment:NSRightTextAlignment];
  [[_labelField cell] setBordered:NO];
  [[_labelField cell] setFont:font];
  [[_labelField cell] setTextColor:[PDColor controlTextColor]];
  [self addSubview:_labelField];
  [_labelField release];

  _valueField = [[NSTextField alloc] initWithFrame:
		 NSMakeRect(LABEL_WIDTH + SPACING, 0, frame.size.width
			    - LABEL_WIDTH, CONTROL_HEIGHT)];
  [_valueField setTarget:self];
  [_valueField setAction:@selector(controlAction:)];
  [_valueField setDelegate:self];
  [_valueField setDrawsBackground:NO];
  [_valueField setEditable:NO];
  [[_valueField cell] setBordered:NO];
  [[_valueField cell] setFont:font1];
  [[_valueField cell] setTextColor:[PDColor controlTextColor]];
  [self addSubview:_valueField];
  [_valueField release];

  return self;
}

- (void)dealloc
{
  [_labelField setDelegate:nil];
  [_valueField setDelegate:nil];

  [_imageProperty release];

  [super dealloc];
}

- (NSString *)imageProperty
{
  return _imageProperty;
}

- (void)_updateImageProperty
{
  [_labelField setStringValue:
   [PDImage localizedNameOfImageProperty:_imageProperty]];
  [[_labelField cell] setTruncatesLastVisibleLine:YES];

  [[_valueField cell] setTextColor:[PDColor controlTextColor]];
  [[_valueField cell] setTruncatesLastVisibleLine:YES];
}

- (void)setImageProperty:(NSString *)name
{
  if (_imageProperty != name)
    {
      [_imageProperty release];
      _imageProperty = [name copy];

      [self _updateImageProperty];
    }
}

- (NSString *)fieldString
{
  if ([_imageProperty isEqualToString:@"PixelSize"])
    {
      double w = [[_metadataView localizedImagePropertyForKey:PDImage_PixelWidth] doubleValue];
      double h = [[_metadataView localizedImagePropertyForKey:PDImage_PixelHeight] doubleValue];
      double mp = w * h * 1e-6;

      return [NSString stringWithFormat:@"%g x %g (%.1f MP)", w, h, mp];
    }

  return [_metadataView localizedImagePropertyForKey:_imageProperty];
}

- (void)update
{
  // reload everything in case of dependent fields (pace, etc)

  [self _updateImageProperty];

  NSString *value = [self fieldString];
  if (value == nil)
    value = @"";

  [_valueField setStringValue:value];
}

- (CGFloat)preferredHeight
{
  return CONTROL_HEIGHT;
}

- (void)layoutSubviews
{
  NSRect bounds = [self bounds];
  NSRect frame = bounds;

  frame.size.width = LABEL_WIDTH;
  [_labelField setFrame:frame];

  frame.origin.x += frame.size.width + SPACING;
  frame.size.width = bounds.size.width - frame.origin.x;
  [_valueField setFrame:frame];
}

- (IBAction)controlAction:(id)sender
{
}

@end
