// -*- c-style: gnu -*-

#import "PDImageListViewController.h"

#import "PDColor.h"
#import "PDWindowController.h"

#define GRID_MARGIN 20
#define GRID_SPACING 30
#define IMAGE_MIN_SIZE 80
#define IMAGE_MAX_SIZE 300

@implementation PDImageListViewController

+ (NSString *)viewNibName
{
  return @"PDImageListView";
}

- (id)initWithController:(PDWindowController *)controller
{
  self = [super initWithController:controller];
  if (self == nil)
    return nil;

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imageListDidChange:)
   name:PDImageListDidChange object:_controller];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(selectedImageIndexesDidChange:)
   name:PDSelectedImageIndexesDidChange object:_controller];

  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [super dealloc];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [_scrollView setBackgroundColor:[PDColor imageGridBackgroundColor]];

  [_gridView setPostsBoundsChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(gridBoundsDidChange:)
   name:NSViewBoundsDidChangeNotification object:[_gridView superview]];

  [_scaleSlider setDoubleValue:[_gridView scale]];
}

- (void)imageListDidChange:(NSNotification *)note
{
  [_gridView setImages:[_controller imageList]];
  [_gridView scrollPoint:NSZeroPoint];
  [_gridView setNeedsDisplay:YES];
}

- (void)selectedImageIndexesDidChange:(NSNotification *)note
{
  [_gridView setSelection:[_controller selectedImageIndexes]];
  [_gridView setNeedsDisplay:YES];
}

- (void)gridBoundsDidChange:(NSNotification *)note
{
  [_gridView setNeedsDisplay:YES];
}

- (IBAction)controlAction:(id)sender
{
  if (sender == _scaleSlider)
    [_gridView setScale:[sender doubleValue]];
}

@end

@implementation PDImageGridView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self == nil)
    return nil;

  _scale = .2;

  return self;
}

- (BOOL)wantsUpdateLayer
{
  return YES;
}

- (void)updateLayer
{
  NSRect frame = [self frame];

  CGFloat width = frame.size.width - GRID_MARGIN*2;
  CGFloat ideal = IMAGE_MIN_SIZE + _scale * (IMAGE_MAX_SIZE - IMAGE_MIN_SIZE);

  _columns = floor(width / ideal);
  _rows = ([_images count] + (_columns - 1) / _columns);
  _size = (width - GRID_SPACING * (_columns - 1)) / _columns;

  CGFloat height = GRID_MARGIN*2 + _size * _rows + GRID_SPACING * (_rows - 1);

  if (height != frame.size.height)
    {
      [self setFrameSize:NSMakeSize(frame.size.width, height)];

      NSScrollView *scrollView = [self enclosingScrollView];
      if (height > [scrollView bounds].size.height)
	[scrollView flashScrollers];
    }

  NSRect rect = [self visibleRect];

  // FIXME: create and layout image layers in rect.

  [self setPreparedContentRect:rect];
}

- (BOOL)isFlipped
{
  return YES;
}

@end
