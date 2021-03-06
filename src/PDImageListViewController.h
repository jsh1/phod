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

#import "PDViewController.h"

@class PDImageGridView;

@interface PDImageListViewController : PDViewController

@property(nonatomic) BOOL displaysMetadata;

@property(nonatomic, weak) IBOutlet NSScrollView *scrollView;
@property(nonatomic, weak) IBOutlet PDImageGridView *gridView;
@property(nonatomic, weak) IBOutlet NSPopUpButton *sortButton;
@property(nonatomic, weak) IBOutlet NSMenu *sortMenu;
@property(nonatomic, weak) IBOutlet NSTextField *titleLabel;
@property(nonatomic, weak) IBOutlet NSSearchField *searchField;
@property(nonatomic, weak) IBOutlet NSMenu *searchMenu;
@property(nonatomic, weak) IBOutlet NSButton *predicateButton;
@property(nonatomic, weak) IBOutlet NSButton *rotateLeftButton;
@property(nonatomic, weak) IBOutlet NSButton *rotateRightButton;
@property(nonatomic, weak) IBOutlet NSSlider *scaleSlider;

- (IBAction)toggleMetadata:(id)sender;

- (IBAction)sortKeyAction:(id)sender;
- (IBAction)sortOrderAction:(id)sender;

- (IBAction)controlAction:(id)sender;

- (BOOL)performKeyEquivalent:(NSEvent *)e;

@end
