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

#import "PDLibraryItem.h"

@interface PDLibraryDirectory : PDLibraryItem
{
  NSString *_libraryPath;
  NSString *_libraryDirectory;
  NSArray *_subitems;
  NSArray *_images;
  NSInteger _imageCount;
  NSMutableArray *_subimages;
  BOOL _toplevel;
  NSInteger _titleImageName;
}

- (id)initWithLibraryPath:(NSString *)path directory:(NSString *)dir;

@property(nonatomic, readonly) NSString *libraryPath;
@property(nonatomic, readonly) NSString *libraryDirectory;

/* convenience that appends libraryDirectory onto libraryPath. */
@property(nonatomic, readonly) NSString *path;

@property(nonatomic) NSInteger titleImageName;

@end
