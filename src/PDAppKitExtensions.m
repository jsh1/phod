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

#import "PDAppKitExtensions.h"

@implementation NSView (PDAppKitExtensions)

/* -[NSView scrollRectToVisible:] seems to randomly pick animated or
   non-animated, I can't figure out how to control it.. */

- (void)scrollRectToVisible:(NSRect)rect animated:(BOOL)flag
{
  NSScrollView *scrollView = [self enclosingScrollView];
  NSClipView *clipView = [scrollView contentView];

  NSRect bounds = [clipView bounds];

  if (rect.origin.x < bounds.origin.x)
    bounds.origin.x = rect.origin.x;
  else if (rect.origin.x + rect.size.width > bounds.origin.x + bounds.size.width)
    bounds.origin.x = rect.origin.x + rect.size.width - bounds.size.width;

  if (rect.origin.y < bounds.origin.y)
    bounds.origin.y = rect.origin.y;
  else if (rect.origin.y + rect.size.height > bounds.origin.y + bounds.size.height)
    bounds.origin.y = rect.origin.y + rect.size.height - bounds.size.height;

  bounds = [clipView constrainBoundsRect:bounds];

  if (flag)
    [[clipView animator] setBounds:bounds];
  else
    [clipView setBounds:bounds];

  [scrollView reflectScrolledClipView:clipView];
}

- (void)flashScrollersIfNeeded
{
  NSScrollView *scrollView = [self enclosingScrollView];

  if ([self frame].size.height > [scrollView bounds].size.height)
    [scrollView flashScrollers];
}

@end

@implementation NSCell (PDAppKitExtensions)

// vCentered is private, but it's impossible to resist..

- (BOOL)isVerticallyCentered
{
  return _cFlags.vCentered;
}

- (void)setVerticallyCentered:(BOOL)flag
{
  _cFlags.vCentered = flag ? YES : NO;
}

@end


@implementation NSTableView (PDAppKitExtensions)

- (void)reloadDataForRow:(NSInteger)row
{
  NSIndexSet *rows = [NSIndexSet indexSetWithIndex:row];
  NSIndexSet *cols = [NSIndexSet indexSetWithIndexesInRange:
		      NSMakeRange(0, [[self tableColumns] count])];

  [self reloadDataForRowIndexes:rows columnIndexes:cols];
}

@end

@implementation NSOutlineView (PDAppKitExtensions)

- (NSArray *)selectedItems
{
  NSIndexSet *sel = [self selectedRowIndexes];

  if ([sel count] == 0)
    return [NSArray array];

  NSMutableArray *array = [NSMutableArray array];

  NSInteger idx;
  for (idx = [sel firstIndex]; idx != NSNotFound;
       idx = [sel indexGreaterThanIndex:idx])
    {
      [array addObject:[self itemAtRow:idx]];
    }

  return array;
}

- (void)setSelectedItems:(NSArray *)array
{
  if ([array count] == 0)
    {
      [self selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
      return;
    }

  NSMutableIndexSet *sel = [NSMutableIndexSet indexSet];

  for (id item in array)
    {
      NSInteger idx = [self rowForItem:item];
      if (idx >= 0)
	[sel addIndex:idx];
    }

  [self selectRowIndexes:sel byExtendingSelection:NO];
}

- (void)callPreservingSelectedRows:(void (^)(void))thunk;
{
  NSArray *sel = [self selectedItems];

  thunk();

  [self setSelectedItems:sel];
}

- (void)reloadDataPreservingSelectedRows
{
  [self callPreservingSelectedRows:^{
    [self reloadData];
  }];
}

@end

NSImage *
PDImageWithName(NSInteger name)
{
  static NSImage *_images[PDImageCount];

  if (name >= 0 && name < PDImageCount)
    {
      if (_images[name] == nil)
	{
	  NSString *imageName = nil;
	  OSType typeCode = 0;

	  switch (name)
	    {
	    case PDImage_Computer:
	      typeCode = kComputerIcon;
	      break;

	    case PDImage_GenericFolder:
	      imageName = NSImageNameFolder;
	      break;

	    case PDImage_GenericHardDisk:
	      typeCode = kGenericHardDiskIcon;
	      break;

	    case PDImage_GenericRemovableDisk:
	      typeCode = kGenericRemovableMediaIcon;
	      break;

	    case PDImage_SmartFolder:
	      imageName = NSImageNameFolderSmart;
	      break;

	    case PDImage_ImportFolder:
	      imageName = @"import-icon";
	      break;
	    }

	  if (imageName != nil)
	    _images[name] = [[NSImage imageNamed:imageName] retain];
	  else if (typeCode != 0)
	    _images[name] = [[[NSWorkspace sharedWorkspace] iconForFileType:
			      NSFileTypeForHFSTypeCode(typeCode)] retain];
	}

      return _images[name];
    }

  return nil;
}
