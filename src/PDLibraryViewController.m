// -*- c-style: gnu -*-

#import "PDLibraryViewController.h"

#import "PDColor.h"
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
    }
}

@end
