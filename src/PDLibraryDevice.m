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

#import "PDLibraryDevice.h"

#import "PDAppKitExtensions.h"
#import "PDImage.h"
#import "PDImageLibrary.h"

@implementation PDLibraryDevice

@synthesize library = _library;

- (id)initWithLibrary:(PDImageLibrary *)lib
{
  self = [super init];
  if (self == nil)
    return nil;

  _library = [lib retain];

  return self;
}

- (void)dealloc
{
  [_library release];
  [_subimages release];
  [_icon release];
  [super dealloc];
}

/* FIXME: copied from -[PDLibraryDirectory loadSubimages]. */

- (void)loadSubimages
{
  if (_subimages == nil)
    {
      static dispatch_queue_t queue;
      static dispatch_once_t once;

      dispatch_once(&once, ^{
	queue = dispatch_queue_create("PDLibraryDevice",
				      DISPATCH_QUEUE_SERIAL);
      });

      _subimages = [[NSMutableArray alloc] init];

      dispatch_async(queue, ^{
	NSMutableArray *array = [[NSMutableArray alloc] init];
	__block CFTimeInterval last_t = CACurrentMediaTime();

	[_library loadImagesInSubdirectory:@"" recursively:YES
	 handler:^(PDImage *im) {
	   [array addObject:im];

	   CFTimeInterval t = CACurrentMediaTime();
	   if (t - last_t > .5)
	     {
	       last_t = t;
	       dispatch_async(dispatch_get_main_queue(), ^{
		 [_subimages addObjectsFromArray:array];
		 [array removeAllObjects];
		 [[NSNotificationCenter defaultCenter]
		  postNotificationName:PDLibraryItemSubimagesDidChange
		  object:self];
	       });
	     }
	 }];

	if ([array count] != 0)
	  {
	    dispatch_async(dispatch_get_main_queue(), ^{
	      [_subimages addObjectsFromArray:array];
	      [[NSNotificationCenter defaultCenter]
	       postNotificationName:PDLibraryItemSubimagesDidChange
	       object:self];
	    });
	  }
	  
	[array release];
      });
    }
}

- (BOOL)foreachSubimage:(void (^)(PDImage *im, BOOL *stop))thunk
{
  if (_subimages == nil)
    [self loadSubimages];

  for (PDImage *im in _subimages)
    {
      BOOL stop = NO;
      thunk(im, &stop);
      if (stop)
	return NO;
    }

  return [super foreachSubimage:thunk];
}

- (NSString *)titleString
{
  return [[[_library path] stringByDeletingLastPathComponent]
	  lastPathComponent];
}

- (BOOL)hasTitleImage
{
  return YES;
}

- (NSImage *)titleImage
{
  if (_icon == nil)
    {
      _icon = [[NSWorkspace sharedWorkspace] iconForFile:
	       [[_library path] stringByDeletingLastPathComponent]];
      if (_icon == nil)
	_icon = PDImageWithName(PDImage_GenericRemovableDisk);
      [_icon retain];
    }

  return _icon;
}

- (BOOL)hasBadge
{
  return YES;
}

- (BOOL)badgeValueIsNumberOfSubimages
{
  return YES;
}

- (NSString *)identifier
{
  return nil;
}

- (void)invalidateContents
{
  [_subimages release];
  _subimages = nil;
}

- (BOOL)needsUpdate
{
  // FIXME: do this correctly.

  return [super needsUpdate];
}

@end
