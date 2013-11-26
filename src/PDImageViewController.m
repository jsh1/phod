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

#import "PDImageViewController.h"

#import "PDColor.h"
#import "PDImage.h"
#import "PDImageView.h"
#import "PDWindowController.h"

@implementation PDImageViewController

+ (NSString *)viewNibName
{
  return @"PDImageView";
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
   addObserver:self selector:@selector(selectionDidChange:)
   name:PDSelectionDidChange object:_controller];

  return self;
}

- (void)updateImage
{
  NSInteger idx = [_controller primarySelectionIndex];
  NSArray *images = [_controller imageList];
  NSInteger count = [images count];

  if (idx >= 0 && idx < count)
    {
      PDImage *image = [images objectAtIndex:idx];

      if ([_imageView image] != image)
	{
	  [_imageView setImage:image];

	  /* Scale of zero will get replaced by -scaleToFitScale by
	     -[PDImageView updateLayer]. Using zero here avoids issues
	     if the view size changes before then. */

	  [_imageView setImageScale:0];
	}

      /* Prefetch images either side of this one. */

      if (idx > 0)
	[[images objectAtIndex:idx-1] startPrefetching];
      if (idx + 1 < count)
	[[images objectAtIndex:idx+1] startPrefetching];

      static NSString *em_dash;
      if (em_dash == nil)
	{
	  unichar c = 0x2014;
	  em_dash = [[NSString alloc] initWithCharacters:&c length:1];
	}

      NSString *dir = [[image lastLibraryPathComponent]
		       stringByReplacingOccurrencesOfString:@":"
		       withString:@"/"];
      NSString *title = [image title];

      [_titleLabel setStringValue:
       [NSString stringWithFormat:@"%@ %@ %@", dir, em_dash, title]];
    }
  else
    {
      [_imageView setImage:nil];
      [_titleLabel setStringValue:@""];
    }
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [_imageView setPostsFrameChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imageViewBoundsDidChange:)
   name:NSViewFrameDidChangeNotification object:_imageView];

  [_titleLabel setTextColor:[PDColor controlTextColor]];
  [_titleLabel setStringValue:@""];

  [self updateImage];
}

- (NSView *)initialFirstResponder
{
  return _imageView;
}

- (void)viewDidDisappear
{
  [_imageView viewDidDisappear];
}

- (void)imageListDidChange:(NSNotification *)note
{
  [self updateImage];
}

- (void)selectionDidChange:(NSNotification *)note
{
  [self updateImage];
}

- (void)imageViewBoundsDidChange:(NSNotification *)note
{
  [_imageView setNeedsDisplay:YES];
}

- (BOOL)displaysMetadata
{
  return [_imageView displaysMetadata];
}

- (void)setDisplaysMetadata:(BOOL)x
{
  if (_imageView == nil)
    [self loadView];

  [_imageView setDisplaysMetadata:x];
}

- (IBAction)toggleMetadata:(id)sender
{
  [self setDisplaysMetadata:![self displaysMetadata]];
}

- (IBAction)zoomIn:(id)sender
{
  CGFloat scale = [_imageView imageScale];

  CGFloat x;
  for (x = 2;; x = x + 1)
    {
      if (scale < 1 && scale > 1/(x+.5))
	{
	  scale = 1/(x-1);
	  break;
	}
      else if (!(scale < 1) && scale < x-.5)
	{
	  scale = x;
	  break;
	}
    }

  [_imageView setImageScale:scale preserveOrigin:YES];
}

- (IBAction)zoomOut:(id)sender
{
  CGFloat scale = [_imageView imageScale];

  CGFloat x;
  for (x = 2;; x = x + 1)
    {
      if (!(scale > 1) && scale > 1/(x-.5))
	{
	  scale = 1/x;
	  break;
	}
      else if (scale > 1 && scale < x+.5)
	{
	  scale = x-1;
	  break;
	}
    }

  [_imageView setImageScale:scale preserveOrigin:YES];
}

- (IBAction)zoomActualSize:(id)sender
{
  CGFloat scale = [_imageView imageScale];
  CGFloat fitScale = [_imageView scaleToFitScale];

  scale = fabs(scale - fitScale) > .001 ? fitScale : 1;

  [_imageView setImageScale:scale preserveOrigin:YES];
}

- (IBAction)controlAction:(id)sender
{
}

// CALayerDelegate methods

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)key
{
  return [NSNull null];
}

@end
