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

#import "PDLibraryDirectory.h"

#import "PDAppKitExtensions.h"
#import "PDImage.h"

@implementation PDLibraryDirectory

@synthesize libraryPath = _libraryPath;
@synthesize libraryDirectory = _libraryDirectory;
@synthesize titleImageName = _titleImageName;

- (id)initWithLibraryPath:(NSString *)path directory:(NSString *)dir;
{
  self = [super init];
  if (self == nil)
    return nil;

  _libraryPath = [path copy];
  _libraryDirectory = [dir copy];
  _titleImageName = PDImage_GenericFolder;

  return self;
}

- (void)dealloc
{
  [_libraryPath release];
  [_libraryDirectory release];
  [_subitems release];
  [_images release];
  [_subimages release];
  [super dealloc];
}

- (NSString *)path
{
  return [_libraryPath stringByAppendingPathComponent:_libraryDirectory];
}

- (NSArray *)subitems
{
  NSFileManager *fm;
  NSMutableArray *array;
  NSString *path;
  BOOL dir;
  PDLibraryDirectory *subitem;

  if (_subitems == nil)
    {
      fm = [NSFileManager defaultManager];
      array = [[NSMutableArray alloc] init];

      NSString *dir_path = [self path];

      for (NSString *file in [fm contentsOfDirectoryAtPath:dir_path error:nil])
	{
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  path = [dir_path stringByAppendingPathComponent:file];
	  dir = NO;
	  if (![fm fileExistsAtPath:path isDirectory:&dir])
	    continue;

	  if (dir)
	    {
	      NSString *subdir = [_libraryDirectory
				  stringByAppendingPathComponent:file];

	      subitem = [[PDLibraryDirectory alloc]
			 initWithLibraryPath:_libraryPath directory:subdir];

	      if (subitem != nil)
		{
		  [array addObject:subitem];
		  [subitem release];
		}
	    }
	}

      _subitems = [array copy];
      [array release];
    }

  return _subitems;
}

- (NSArray *)subimages
{
  if (_subimages == nil)
    {
      _subimages = [[PDImage imagesInLibrary:_libraryPath
		     directory:_libraryDirectory filter:nil] copy];
    }

  NSMutableArray *images = [NSMutableArray array];

  [images addObjectsFromArray:_subimages];

  for (PDLibraryDirectory *item in [self subitems])
    {
      if (![item isHidden])
	[images addObjectsFromArray:[item subimages]];
    }

  return images;
}

- (NSImage *)titleImage
{
  return PDImageWithName(_titleImageName);
}

- (NSString *)titleString
{
  NSString *title = [_libraryDirectory lastPathComponent];
  if ([title length] == 0)
    title = [_libraryPath lastPathComponent];
  return [title stringByReplacingOccurrencesOfString:@":" withString:@"/"];
}

- (BOOL)isExpandable
{
  return [[self subitems] count] != 0;
}

- (BOOL)hasBadge
{
  return YES;
}

- (NSInteger)badgeValue
{
  return [self numberOfSubimages];
}

- (BOOL)needsUpdate
{
  // FIXME: do this correctly.

  return [super needsUpdate];
}

@end
