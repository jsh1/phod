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
  NSDictionary *_metadataGroups;
  NSArray *_metadataGroupOrder;
  NSString *_activeGroup;
}

@synthesize metadataView = _metadataView;
@synthesize popupButton = _popupButton;
@synthesize popupMenu = _popupMenu;

+ (NSString *)viewNibName
{
  return @"PDInfoView";
}

- (id)initWithController:(PDWindowController *)controller
{
  return [super initWithController:controller];
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
	  item.target = self;
	  item.representedObject = name;
	  [_popupMenu addItem:item];
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
  _activeGroup = [name copy];

  [_metadataView setImageProperties:_metadataGroups[name]];

  [_popupButton selectItemAtIndex:
   [_popupMenu indexOfItemWithRepresentedObject:name]];
}

- (void)selectionChanged:(NSNotification *)note
{
  [_metadataView update];
}

- (void)imagePropertyChanged:(NSNotification *)note
{
  if (note.object == _controller.primarySelectedImage)
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
  id value = dict[@"ActiveGroup"];
  if (value != nil)
    [self setActiveGroup:value];
}

- (NSString *)localizedImagePropertyForKey:(NSString *)key
{
  return [_controller.primarySelectedImage localizedImagePropertyForKey:key];
}

- (void)setLocalizedImageProperty:(NSString *)str forKey:(NSString *)key
{
  [_controller.primarySelectedImage setLocalizedImageProperty:str forKey:key];
}

- (IBAction)controlAction:(id)sender
{
}

- (IBAction)popupMenuAction:(NSMenuItem *)sender
{
  self.activeGroup = sender.representedObject;
}

@end
