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

#import <AppKit/AppKit.h>

extern NSString * const PDPredicateDidChange;

@interface PDPredicatePanelController : NSWindowController
{
  IBOutlet NSPredicateEditor *_predicateEditor;
  IBOutlet NSButton *_addSmartFolderButton;
  IBOutlet NSButton *_cancelButton;
  IBOutlet NSButton *_okButton;

  NSPredicate *_predicate;
}

- (id)init;

@property(nonatomic, retain) NSPredicate *predicate;

- (NSPredicate *)predicateWithFormat:(NSString *)str;

- (IBAction)controlAction:(id)sender;

- (IBAction)newSmartAlbumAction:(id)sender;

@end
