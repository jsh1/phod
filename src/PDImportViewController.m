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

#import "PDImportViewController.h"

#import "PDImage.h"
#import "PDImageLibrary.h"
#import "PDFoundationExtensions.h"
#import "PDWindowController.h"

@interface PDImportViewController ()
- (void)updateControls;
- (void)updateDescription;
@end

@implementation PDImportViewController

+ (NSString *)viewNibName
{
  return @"PDImportView";
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(selectedImagesDidChange:)
   name:PDSelectionDidChange object:_controller];

  NSString *format = [[NSUserDefaults standardUserDefaults]
		      stringForKey:@"PDImportProjectNameTemplate"];
  if ([format length] != 0)
    {
      time_t date = time(NULL);
      struct tm tm = {0};
      localtime_r(&date, &tm);
      char buf[2048];
      strftime(buf, sizeof(buf), [format UTF8String], &tm);
      [_nameField setStringValue:[NSString stringWithUTF8String:buf]];
    }
}

- (void)viewWillAppear
{
  [self updateControls];
  [self updateDescription];
}

- (void)updateDescription
{
  if (![_okButton isEnabled])
    {
      [_descriptionLabel setStringValue:@""];
      return;
    }

  NSInteger count = [[_controller selectedImageIndexes] count];

  PDImageLibrary *lib = [[_libraryButton selectedItem] representedObject];

  NSString *folder = [_directoryField stringValue];
  NSString *name = [_nameField stringValue];

  NSString *dir = [folder stringByAppendingPathComponent:name];

  NSMutableString *desc = [NSMutableString string];

  if (count == 1)
    [desc appendString:@"Import 1 image"];
  else
    [desc appendFormat:@"Import %d images", (int)count];

  if ([dir length] == 0)
    [desc appendString:@" into root"];
  else
    [desc appendFormat:@" into folder \"%@\"", dir];

  [desc appendFormat:@" of library \"%@\".", [lib name]];

  [_descriptionLabel setStringValue:desc];
}

- (void)updateControls
{
  NSArray *all_libs = [PDImageLibrary allLibraries];
  NSArray *current_libs = [[_libraryButton itemArray] mappedArray:
			   ^id (id obj) {
			     return [(NSMenuItem *)obj representedObject];}];

  if (![current_libs isEqual:all_libs])
    {
      PDImageLibrary *selected_lib
        = [[_libraryButton selectedItem] representedObject];

      [_libraryButton removeAllItems];
      for (PDImageLibrary *lib in all_libs)
	{
	  if (![lib isTransient])
	    {
	      [_libraryButton addItemWithTitle:[lib name]];
	      NSMenuItem *item = [_libraryButton lastItem];
	      [item setRepresentedObject:lib];
	      if (lib == selected_lib)
		[_libraryButton selectItem:item];
	    }
	}
    }
}

- (void)setImportDestinationLibrary:(PDImageLibrary *)lib
    directory:(NSString *)dir
{
  NSInteger idx = [_libraryButton indexOfItemWithRepresentedObject:lib];

  if (idx >= 0)
    {
      [_libraryButton selectItemAtIndex:idx];
      [_directoryField setStringValue:dir];
    }
}

- (void)doImport
{
  PDImageLibrary *lib = [[_libraryButton selectedItem] representedObject];
  if (lib == nil)
    return;

  NSString *dir = [_directoryField stringValue];
  NSString *name = [_nameField stringValue];
  if ([dir length] != 0)
    dir = [dir stringByAppendingPathComponent:name];
  else
    dir = name;
  if ([dir length] == 0)
    return;

  NSMutableSet *types = [NSMutableSet set];
  switch ([_importButton indexOfSelectedItem])
    {
    case 0:
      [types addObject:(id)kUTTypeJPEG];
      [types addObject:(id)PDTypeRAWImage];
      break;
    case 1:
      [types addObject:(id)kUTTypeJPEG];
      break;
    case 2:
      [types addObject:(id)PDTypeRAWImage];
      break;
    }

  NSString *active_type = nil;
  switch ([_activeTypeButton indexOfSelectedItem])
    {
    case 0:
      active_type = (id)kUTTypeJPEG;
      break;
    case 1:
      active_type = (id)PDTypeRAWImage;
      break;
    }

  NSMutableDictionary *metadata = [NSMutableDictionary dictionary];

  NSString *keywords_str = [_keywordsField stringValue];
  if ([keywords_str length] != 0)
    {
      NSArray *keywords = [keywords_str componentsSeparatedByCharactersInSet:
			   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([keywords count] != 0)
	[metadata setObject:keywords forKey:PDImage_Keywords];
    }

  BOOL delete_sources = [_deleteAfterButton intValue] != 0;

  [lib importImages:[_controller selectedImages] toDirectory:dir
   fileTypes:types preferredType:active_type filenameMap:NULL
   properties:metadata deleteSourceImages:delete_sources];

  [_controller selectLibrary:lib directory:dir];
}

- (void)selectedImagesDidChange:(NSNotification *)note
{
  [_okButton setEnabled:[[_controller selectedImageIndexes] count] != 0];

  [self updateDescription];
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _okButton)
    {
      [self doImport];
      [_controller setImportMode:NO];
      return;
    }
  else if (sender == _cancelButton)
    {
      [_controller setImportMode:NO];
      return;
    }

  [self updateDescription];
}

@end
