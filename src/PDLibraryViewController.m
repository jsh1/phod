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

#import "PDLibraryViewController.h"

#import "PDLibraryDirectory.h"
#import "PDLibraryImage.h"
#import "PDLibraryItem.h"
#import "PDWindowController.h"

@implementation PDLibraryViewController

+ (NSString *)viewNibName
{
  return @"PDLibraryView";
}

- (id)initWithController:(PDWindowController *)controller
{
  PDLibraryItem *item;

  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  _items = [[NSMutableArray alloc] init];

  item = [[PDLibraryDirectory alloc] initWithPath:
	  [@"~/Pictures/Photos" stringByExpandingTildeInPath]];
  [_items addObject:item];
  [item release];

  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [_outlineView setDataSource:nil];
  [_outlineView setDelegate:nil];

  [_items release];

  [super dealloc];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  for (NSTableColumn *col in [_outlineView tableColumns])
    [[col dataCell] setVerticallyCentered:YES];
}

- (NSView *)initialFirstResponder
{
  return _outlineView;
}

// NSOutlineViewDataSource methods

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
  if (item == nil)
    return [_items count];
  else
    return [(PDLibraryItem *)item numberOfSubitems];
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
  if (item == nil)
    return [_items objectAtIndex:index];
  else
    return [[(PDLibraryItem *)item subitems] objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
  return [(PDLibraryItem *)item isExpandable];
}

- (id)outlineView:(NSOutlineView *)ov
    objectValueForTableColumn:(NSTableColumn *)col byItem:(id)item
{
  NSString *ident = [col identifier];

  if ([ident isEqualToString:@"name"])
    return [item titleString];
  else if ([ident isEqualToString:@"badge"])
    return [item hasBadge] ? [NSString stringWithFormat:@"%d", (int)[item badgeValue]] : nil;

  return nil;
}

- (void)outlineView:(NSOutlineView *)ov setObjectValue:(id)object
    forTableColumn:(NSTableColumn *)col byItem:(id)item
{
}

// NSOutlineViewDelegate methods

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
  NSIndexSet *sel;
  NSMutableArray *array;

  sel = [_outlineView selectedRowIndexes];
  if (sel == nil)
    [_controller setImageList:[NSArray array]];
  else
    {
      array = [NSMutableArray array];

      for (NSInteger row = [sel firstIndex];
	   row != NSNotFound; row = [sel indexGreaterThanIndex:row])
	{
	  [array addObjectsFromArray:[[_outlineView itemAtRow:row] subimages]];
	}

      [_controller setImageList:array];

      if ([array count] > 0)
	[_controller setSelectedImageIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
}

@end
