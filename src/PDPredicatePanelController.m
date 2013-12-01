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

#import "PDPredicatePanelController.h"

#import "PDImage.h"

NSString * const PDPredicateDidChange = @"PDPredicateDidChange";

@implementation PDPredicatePanelController

- (NSString *)windowNibName
{
  return @"PDPredicatePanel";
}

- (id)init
{
  self = [super initWithWindow:nil];
  if (self == nil)
    return nil;

  _predicate = [[NSCompoundPredicate andPredicateWithSubpredicates:
		@[[NSPredicate predicateWithFormat:@"%K >= %@",
		   PDImage_Rating, @0]]] retain];

  return self;
}

- (void)dealloc
{
  [_predicate release];
  [super dealloc];
}

- (void)windowDidLoad
{
  /* Setting up templates in IB is painful, so do it by hand. */

  NSArray *compound_types = @[@(NSNotPredicateType),
			     @(NSAndPredicateType),
			     @(NSOrPredicateType)];
  NSPredicateEditorRowTemplate *compound_template
   = [[NSPredicateEditorRowTemplate alloc]
      initWithCompoundTypes:compound_types];

  NSMutableArray *string_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_Name, PDImage_ActiveType, PDImage_FileTypes,
			  PDImage_ColorModel, PDImage_ProfileName,
			  PDImage_Title, PDImage_Caption, PDImage_Keywords,
			  PDImage_Copyright, PDImage_CameraMake,
			  PDImage_CameraModel, PDImage_CameraSoftware,
			  PDImage_Orientation, PDImage_ExposureMode,
			  PDImage_ExposureProgram, PDImage_Flash,
			  PDImage_ImageStabilization, PDImage_LightSource,
			  PDImage_MeteringMode, PDImage_SceneCaptureType,
			  PDImage_SceneType, PDImage_WhiteBalance])
    {
      [string_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *string_ops = @[@(NSEqualToPredicateOperatorType),
			  @(NSNotEqualToPredicateOperatorType),
			  @(NSBeginsWithPredicateOperatorType),
			  @(NSEndsWithPredicateOperatorType),
			  @(NSContainsPredicateOperatorType)];

  NSPredicateEditorRowTemplate *string_template
    = [[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:string_keys
       rightExpressionAttributeType:NSStringAttributeType
       modifier:NSDirectPredicateModifier operators:string_ops
       options:(NSCaseInsensitivePredicateOption
		| NSDiacriticInsensitivePredicateOption)];

  NSMutableArray *numeric_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_FileSize, PDImage_PixelWidth,
			  PDImage_PixelHeight, PDImage_Rating,
			  PDImage_Altitude,
			  PDImage_Contrast, PDImage_Direction,
			  PDImage_ExposureBias, PDImage_ExposureLength,
			  PDImage_FNumber, PDImage_FocalLength,
			  PDImage_FocalLength35mm, PDImage_ISOSpeed,
			  PDImage_Latitude, PDImage_Longitude,
			  PDImage_MaxAperture, PDImage_Saturation,
			  PDImage_Sharpness])
    {
      [numeric_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *numeric_ops = @[@(NSEqualToPredicateOperatorType),
			   @(NSNotEqualToPredicateOperatorType),
			   @(NSLessThanPredicateOperatorType),
			   @(NSLessThanOrEqualToPredicateOperatorType),
			   @(NSGreaterThanPredicateOperatorType),
			   @(NSGreaterThanOrEqualToPredicateOperatorType)];

  NSPredicateEditorRowTemplate *numeric_template
    = [[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:
       numeric_keys rightExpressionAttributeType:NSDoubleAttributeType
       modifier:NSDirectPredicateModifier operators:numeric_ops options:0];

  NSMutableArray *bool_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_Flagged, PDImage_Rejected])
    {
      [bool_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *bool_values = @[[NSExpression expressionForConstantValue:
			    [NSNumber numberWithBool:NO]],
			   [NSExpression expressionForConstantValue:
			    [NSNumber numberWithBool:YES]]];

  NSArray *bool_ops = @[@(NSEqualToPredicateOperatorType),
			   @(NSNotEqualToPredicateOperatorType)];

  NSPredicateEditorRowTemplate *bool_template
    = [[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:bool_keys
       rightExpressions:bool_values modifier:NSDirectPredicateModifier
       operators:bool_ops options:0];

  NSMutableArray *date_keys = [NSMutableArray array];
  for (NSString *key in @[PDImage_FileDate, PDImage_OriginalDate,
			  PDImage_DigitizedDate])
    {
      [date_keys addObject:[NSExpression expressionForKeyPath:key]];
    }

  NSArray *date_ops = numeric_ops;

  NSPredicateEditorRowTemplate *date_template
    = [[NSPredicateEditorRowTemplate alloc] initWithLeftExpressions:date_keys
       rightExpressionAttributeType:NSDateAttributeType
       modifier:NSDirectPredicateModifier operators:date_ops options:0];

  [_predicateEditor setRowTemplates:
   @[compound_template, string_template, numeric_template, bool_template,
     date_template]];

  [compound_template release];
  [string_template release];
  [numeric_template release];
  [date_template release];

  [_predicateEditor setObjectValue:_predicate];
}

- (NSPredicate *)predicate
{
  return _predicate;
}

- (void)setPredicate:(NSPredicate *)obj
{
  /* Make sure it's always compound, else it can't be aggreated. */

  if (obj != nil && ![obj isKindOfClass:[NSCompoundPredicate class]])
    obj = [NSCompoundPredicate andPredicateWithSubpredicates:@[obj]];

  if (_predicate != obj)
    {
      [_predicate release];
      _predicate = [obj copy];

      [_predicateEditor setObjectValue:obj];
    }
}

- (NSPredicate *)predicateWithFormat:(NSString *)str
{
  @try {
    return [NSPredicate predicateWithFormat:str];
  } @catch (id exception) {
    return nil;
  }
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _predicateEditor)
    {
      [_predicate release];
      _predicate = [[_predicateEditor objectValue] copy];

      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDPredicateDidChange object:self];
    }
  else if (sender == _okButton)
    {
      [self close];
    }
  else if (sender == _cancelButton)
    {
      [_predicate release];
      _predicate = nil;
      [[NSNotificationCenter defaultCenter]
       postNotificationName:PDPredicateDidChange object:self];

      [self close];
    }
  else if (sender == _addSmartFolderButton)
    {
      /* FIXME: implement this correctly. */

      NSBeep();
    }
}

@end
