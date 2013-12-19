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

#import "PDAppDelegate.h"
#import "PDImage.h"
#import "PDImageProperty.h"

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

  [_predicateEditor setRowTemplates:PDImagePredicateEditorRowTemplates()];
  [_predicateEditor setObjectValue:_predicate];
}

- (NSPredicate *)predicate
{
  return _predicate;
}

- (void)setPredicate:(NSPredicate *)obj
{
  /* Make sure it's always compound, else it can't be edited. */

  if (obj == nil)
    obj = [NSCompoundPredicate andPredicateWithSubpredicates:@[]];
  else if(![obj isKindOfClass:[NSCompoundPredicate class]])
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
  if ([str length] == 0)
    return nil;

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

- (IBAction)newSmartAlbumAction:(id)sender
{
  [[(PDAppDelegate *)[NSApp delegate] windowController]
   newSmartAlbumAction:sender];
}

@end
