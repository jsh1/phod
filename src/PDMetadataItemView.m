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

#define LABEL_Y_OFFSET -4
#define LABEL_WIDTH 120
#define LABEL_HEIGHT 16
#define SPACING 8

#define CONTROL_HEIGHT 20

@implementation PDMetadataItemView
{
  NSTextField *_labelField;
  NSTextField *_valueField;

  NSString *_imageProperty;
}

@synthesize metadataView = _metadataView;

- (id)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  NSFont *font1 = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];

  _labelField = [[NSTextField alloc] initWithFrame:
		 NSMakeRect(0, LABEL_Y_OFFSET, LABEL_WIDTH, LABEL_HEIGHT)];
  _labelField.target = self;
  _labelField.action = @selector(controlAction:);
  _labelField.delegate = self;
  _labelField.drawsBackground = NO;
  _labelField.editable = NO;
  _labelField.alignment = NSRightTextAlignment;
  _labelField.autoresizingMask = NSViewMaxXMargin;
  NSTextFieldCell *label_cell = _labelField.cell;
  label_cell.bordered = NO;
  label_cell.font = font;
  label_cell.textColor = [PDColor controlTextColor];
  [self addSubview:_labelField];

  _valueField = [[NSTextField alloc] initWithFrame:
		 NSMakeRect(LABEL_WIDTH + SPACING, 0, frame.size.width
			    - LABEL_WIDTH, CONTROL_HEIGHT)];
  _valueField.target = self;
  _valueField.action = @selector(controlAction:);
  _valueField.delegate = self;
  _valueField.editable = NO;
  _valueField.selectable = YES;
  _valueField.autoresizingMask = NSViewWidthSizable;
  NSTextFieldCell *value_cell = _valueField.cell;
  value_cell.bordered = NO;
  value_cell.bezeled = YES;
  value_cell.font = font1;
  value_cell.textColor = [PDColor controlTextColor];
  value_cell.backgroundColor = [PDColor controlBackgroundColor];
  [self addSubview:_valueField];

  return self;
}

- (void)dealloc
{
  _labelField.delegate = nil;
  _valueField.delegate = nil;
}

- (NSString *)imageProperty
{
  return _imageProperty;
}

- (void)_updateImageProperty
{
  BOOL editable = [PDImage imagePropertyIsEditableInUI:_imageProperty];
  NSString *label = [PDImage localizedNameOfImageProperty:_imageProperty];

  _labelField.stringValue = label;
  ((NSTextFieldCell *)_labelField.cell).truncatesLastVisibleLine = YES;

  _valueField.editable = editable;
  _valueField.drawsBackground = editable;
  ((NSTextFieldCell *)_valueField.cell).bezeled = editable;
  ((NSTextFieldCell *)_valueField.cell).truncatesLastVisibleLine = YES;
}

- (void)setImageProperty:(NSString *)name
{
  if (_imageProperty != name)
    {
      _imageProperty = [name copy];
      [self _updateImageProperty];
    }
}

- (NSString *)fieldString
{
  if ([_imageProperty isEqualToString:@"pixel_size"])
    {
      double w = [[_metadataView localizedImagePropertyForKey:
		   PDImage_PixelWidth] doubleValue];
      double h = [[_metadataView localizedImagePropertyForKey:
		   PDImage_PixelHeight] doubleValue];

      if (w == 0 || h == 0)
	return nil;

      double mp = w * h * 1e-6;
      return [NSString stringWithFormat:@"%g x %g (%.1f MP)", w, h, mp];
    }

  return [_metadataView localizedImagePropertyForKey:_imageProperty];
}

- (void)update
{
  // reload everything in case of dependent fields (pace, etc)

  [self _updateImageProperty];

  NSString *value = self.fieldString;
  if (value == nil)
    value = @"";

  _valueField.stringValue = value;
}

- (CGFloat)preferredHeight
{
  return _valueField.editable ? CONTROL_HEIGHT : LABEL_HEIGHT;
}

- (void)layoutSubviews
{
  CGRect bounds = self.bounds;
  CGRect frame = bounds;
  BOOL editable = _valueField.editable;

  if (editable)
    frame.origin.y += LABEL_Y_OFFSET;
  frame.size.width = LABEL_WIDTH;
  _labelField.frame = frame;

  frame.origin.x += frame.size.width + SPACING;
  frame.origin.y = bounds.origin.y;
  frame.size.width = bounds.size.width - frame.origin.x;
  frame.size.height = editable ? CONTROL_HEIGHT : LABEL_HEIGHT;
  _valueField.frame = frame;
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _valueField)
    {
      [_metadataView setLocalizedImageProperty:
       _valueField.stringValue forKey:_imageProperty];
    }
}

@end
