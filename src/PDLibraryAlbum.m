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
#import "PDImageName.h"
#import "PDWindowController.h"

@implementation PDLibraryAlbum

- (id)init
{
  self = [super init];
  if (self == nil)
    return nil;

  _imageNames = [[NSMutableArray alloc] init];
  _map = CFDictionaryCreateMutable(NULL, 0, NULL,
		&kCFTypeDictionaryValueCallBacks);

  return self;
}

- (void)dealloc
{
  [_imageNames release];
  if (_map != NULL)
    CFRelease(_map);
  [super dealloc];
}

- (NSArray *)imageNames
{
  return _imageNames;
}

- (void)setImageNames:(NSArray *)obj
{
  if (_imageNames != obj)
    {
      [_imageNames release];
      _imageNames = [obj mutableCopy];

      CFDictionaryRemoveAllValues(_map);

      for (PDImageName *name in _imageNames)
	{
	  uintptr_t ident = [name imageId];
	  CFDictionarySetValue(_map, (void *)ident, name);
	}
    }
}

- (void)addImageNamed:(PDImageName *)name
{
  uintptr_t ident = [name imageId];
  if (CFDictionaryGetValue(_map, (void *)ident) == NULL)
    {
      [_imageNames addObject:name];
      CFDictionarySetValue(_map, (void *)ident, name);
    }
}

- (void)removeImageNamed:(PDImageName *)name
{
  [_imageNames removeObject:name];
  CFDictionaryRemoveAllValues(_map);
}

- (void)foreachSubimage:(void (^)(PDImage *))thunk
{
  PDWindowController *controller
    = [(PDAppDelegate *)[NSApp delegate] windowController];

  [controller foreachImage:^(PDImage *im) {
    uintptr_t ident = [im imageIdIfDefined];
    if (ident != 0)
      {
	PDImageName *name = (id)CFDictionaryGetValue(_map, (void *)ident);
	if (name != nil && [name matchesImage:im])
	  thunk(im);
      }
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
  return [_imageNames count];
}

@end
