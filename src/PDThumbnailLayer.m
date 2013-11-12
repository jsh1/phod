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

#import "PDThumbnailLayer.h"

#import "PDLibraryImage.h"

#import <QuartzCore/QuartzCore.h>

@implementation PDThumbnailLayer

- (id)initWithLayer:(PDThumbnailLayer *)src
{
  self = [super initWithLayer:src];
  if (self == nil)
    return nil;

  _libraryImage = [src->_libraryImage retain];

  return self;
}

- (void)invalidate
{
  if (_addedThumbnail)
    {
      [_libraryImage removeThumbnail:self];
      _addedThumbnail = NO;
    }
}

- (void)dealloc
{
  [self invalidate];
  [_libraryImage release];

  [super dealloc];
}

- (PDLibraryImage *)libraryImage
{
  return _libraryImage;
}

- (void)setLibraryImage:(PDLibraryImage *)im
{
  if (_libraryImage != im)
    {
      if (_addedThumbnail)
	{
	  [_libraryImage removeThumbnail:self];
	  _addedThumbnail = NO;
	}

      [_libraryImage release];
      _libraryImage = [im retain];

      [self setNeedsLayout];
    }
}

- (void)layoutSublayers
{
  if (_libraryImage == nil)
    [self setContents:nil];
  else
    {
      CGRect bounds = [self bounds];
      CGFloat scale = [self contentsScale];

      CGSize size = CGSizeMake(ceil(bounds.size.width * scale),
			       ceil(bounds.size.height * scale));

      if (!_addedThumbnail)
	{
	  _thumbnailSize = size;
	  [_libraryImage addThumbnail:self];
	  _addedThumbnail = YES;
	}
      else if (!CGSizeEqualToSize(_thumbnailSize, size))
	{
	  [_libraryImage updateThumbnail:self];
	}
    }
}

- (CGSize)thumbnailSize
{
  return _thumbnailSize;
}

- (void)setThumbnailImage:(CGImageRef)im
{
  // Rotate layer to match image orientation.

  unsigned int orientation = [(id)[_libraryImage imagePropertyForKey:
				   kCGImagePropertyOrientation]
			      unsignedIntValue];
  if (orientation > 1)
    {
      CGAffineTransform m = CGAffineTransformIdentity;

      if (orientation > 4)
	{
	  m = CGAffineTransformRotate(m, -M_PI_2);
	  orientation -= 4;
	}

      if (orientation == 2)
	m = CGAffineTransformScale(m, -1, 1);
      else if (orientation == 3)
	m = CGAffineTransformScale(m, -1, -1);
      else if (orientation == 4)
	m = CGAffineTransformScale(m, 1, -1);

      [self setAffineTransform:m];
    }

  // Move image decompression onto background thread.

  CGImageRetain(im);

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self setContents:(id)im];
    [self setBackgroundColor:NULL];
    CGImageRelease(im);
    [CATransaction flush];
  });
}

@end
