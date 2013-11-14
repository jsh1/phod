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

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  [super dealloc];
}

- (void)updateImage
{
  NSInteger idx = [_controller primarySelectionIndex];
  NSArray *images = [_controller imageList];

  if (idx >= 0 && idx < [images count])
    {
      PDLibraryImage *image = [images objectAtIndex:idx];

      if ([_imageView libraryImage] != image)
	{
	  [_imageView setLibraryImage:image];
	  [_imageView setImageScale:[_imageView scaleToFitScale]];
	  [_imageView setImageOrigin:CGPointZero];
	}
    }
  else
    [_imageView setLibraryImage:nil];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  [[NSNotificationCenter defaultCenter]
   addObserver:self selector:@selector(imageViewBoundsDidChange:)
   name:NSViewBoundsDidChangeNotification object:_imageView];

  [_imageView setPostsBoundsChangedNotifications:YES];

  /* FIXME: too soon -- bounds isn't final, and we don't notice when
     it later changes, despite the code above. */

  [self updateImage];
}

- (NSView *)initialFirstResponder
{
  return _imageView;
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

- (IBAction)controlAction:(id)sender
{
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
  CGFloat fitScale = [_imageView scaleToFitScale];

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

  if (scale < fitScale)
    scale = fitScale;

  [_imageView setImageScale:scale preserveOrigin:YES];
}

- (IBAction)zoomActualSize:(id)sender
{
  CGFloat scale = [_imageView imageScale];
  CGFloat fitScale = [_imageView scaleToFitScale];

  scale = scale > fitScale ? fitScale : 1;

  [_imageView setImageScale:scale preserveOrigin:YES];
}

// CALayerDelegate methods

- (id)actionForLayer:(CALayer *)layer forKey:(NSString *)key
{
  return [NSNull null];
}

@end
