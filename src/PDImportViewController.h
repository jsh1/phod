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

@class PDImageLibrary;

@interface PDImportViewController : PDViewController

- (void)setImportDestinationLibrary:(PDImageLibrary *)lib
    directory:(NSString *)dir;

@property(nonatomic, weak) IBOutlet NSPopUpButton *libraryButton;
@property(nonatomic, weak) IBOutlet NSTextField *directoryField;
@property(nonatomic, weak) IBOutlet NSTextField *nameField;
@property(nonatomic, weak) IBOutlet NSButton *renameButton;
@property(nonatomic, weak) IBOutlet NSTextField *renameField;
@property(nonatomic, weak) IBOutlet NSTextField *renameFieldLabel;
@property(nonatomic, weak) IBOutlet NSPopUpButton *importButton;
@property(nonatomic, weak) IBOutlet NSPopUpButton *activeTypeButton;
@property(nonatomic, weak) IBOutlet NSTextField *keywordsField;
@property(nonatomic, weak) IBOutlet NSButton *deleteAfterButton;
@property(nonatomic, weak) IBOutlet NSTextField *descriptionLabel;
@property(nonatomic, weak) IBOutlet NSButton *okButton;
@property(nonatomic, weak) IBOutlet NSButton *cancelButton;

- (IBAction)controlAction:(id)sender;

@end
