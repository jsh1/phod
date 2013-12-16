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

#import "PDLibraryAlbum.h"

#import "PDAppDelegate.h"
#import "PDAppKitExtensions.h"
#import "PDImage.h"
#import "PDWindowController.h"

#import "PDMacros.h"

@implementation PDLibraryAlbum

- (id)init
{
  self = [super init];
  if (self == nil)
    return nil;

  _imageUUIDs = [[NSMutableArray alloc] init];
  _allUUIDs = [[NSMutableSet alloc] init];

  return self;
}

- (void)dealloc
{
  [_imageUUIDs release];
  [_allUUIDs release];
  [super dealloc];
}

- (NSArray *)imageUUIDs
{
  return _imageUUIDs;
}

- (void)setImageUUIDs:(NSArray *)obj
{
  if (_imageUUIDs != obj)
    {
      [_imageUUIDs release];
      _imageUUIDs = [obj mutableCopy];

      [_allUUIDs removeAllObjects];

      for (NSUUID *uuid in _imageUUIDs)
	[_allUUIDs addObject:uuid];
    }
}

- (void)addImageWithUUID:(NSUUID *)uuid
{
  if (![_allUUIDs containsObject:uuid])
    {
      [_imageUUIDs addObject:uuid];
      [_allUUIDs addObject:uuid];
    }
}

- (void)removeImageWithUUID:(NSUUID *)uuid
{
  [_allUUIDs removeObject:uuid];
  [_imageUUIDs removeObject:uuid];
}

- (void)foreachSubimage:(void (^)(PDImage *))thunk
{
  PDWindowController *controller
    = [(PDAppDelegate *)[NSApp delegate] windowController];

  [controller foreachImage:^(PDImage *im) {
    NSUUID *uuid = [im UUIDIfDefined];
    if (uuid != nil && [_allUUIDs containsObject:uuid])
      thunk(im);
  }];
}

- (BOOL)hasTitleImage
{
  return YES;
}

- (NSImage *)titleImage
{
  NSImage *image = [super titleImage];
  return image != nil ? image : PDImageWithName(PDImage_GenericFolder);
}

- (BOOL)hasBadge
{
  return YES;
}

- (NSInteger)badgeValue
{
  return [_imageUUIDs count];
}

@end
