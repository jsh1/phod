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

#import "PDInfoViewController.h"

#import "PDImage.h"
#import "PDMetadataView.h"
#import "PDWindowController.h"

@implementation PDInfoViewController
{
  IBOutlet PDMetadataView *_metadataView;
  IBOutlet NSPopUpButton *_popupButton;
  IBOutlet NSMenu *_popupMenu;

  NSDictionary *_metadataGroups;
  NSArray *_metadataGroupOrder;
  NSString *_activeGroup;
}

+ (NSString *)viewNibName
{
  return @"PDInfoView";
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  return self;
}

- (void)dealloc
{
  [_metadataGroups release];
  [_metadataGroupOrder release];
  [_activeGroup release];
  [super dealloc];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(selectionChanged:)
   name:PDImageListDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(selectionChanged:)
   name:PDSelectionDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imagePropertyChanged:)
   name:PDImagePropertyDidChange object:nil];

  _metadataGroups = [[[NSUserDefaults standardUserDefaults]
		      objectForKey:@"PDMetadataGroups"] copy];
  _metadataGroupOrder = [[[NSUserDefaults standardUserDefaults]
			  objectForKey:@"PDMetadataGroupOrder"] copy];

  if ([_metadataGroupOrder count] > 0)
    {
      [_popupMenu removeAllItems];

      for (NSString *name in _metadataGroupOrder)
	{
	  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name
		action:@selector(popupMenuAction:) keyEquivalent:@""];
	  [item setTarget:self];
	  [item setRepresentedObject:name];
	  [_popupMenu addItem:item];
	  [item release];
	}

      if (_activeGroup == nil)
	[self setActiveGroup:[_metadataGroupOrder firstObject]];
      else
	[self setActiveGroup:_activeGroup];
    }
}

- (NSString *)activeGroup
{
  return _activeGroup;
}

- (void)setActiveGroup:(NSString *)name
{
  [_activeGroup release];
  _activeGroup = [name copy];

  [_metadataView setImageProperties:[_metadataGroups objectForKey:name]];

  [_popupButton selectItemAtIndex:
   [_popupMenu indexOfItemWithRepresentedObject:name]];
}

- (void)selectionChanged:(NSNotification *)note
{
  [_metadataView update];
}

- (void)imagePropertyChanged:(NSNotification *)note
{
  if ([note object] == [_controller primarySelectedImage])
    [_metadataView update];
}

- (NSDictionary *)savedViewState
{
  if (_activeGroup != nil)
    return @{@"ActiveGroup": _activeGroup};
  else
    return nil;
}

- (void)applySavedViewState:(NSDictionary *)dict
{
  id value = [dict objectForKey:@"ActiveGroup"];
  if (value != nil)
    [self setActiveGroup:value];
}

- (NSString *)localizedImagePropertyForKey:(NSString *)key
{
  return [[_controller primarySelectedImage]
	  localizedImagePropertyForKey:key];
}

- (void)setLocalizedImageProperty:(NSString *)str forKey:(NSString *)key
{
  [[_controller primarySelectedImage]
   setLocalizedImageProperty:str forKey:key];
}

- (IBAction)controlAction:(id)sender
{
}

- (IBAction)popupMenuAction:(id)sender
{
  [self setActiveGroup:[sender representedObject]];
}

@end
