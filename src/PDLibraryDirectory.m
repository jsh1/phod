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
#import "PDFoundationExtensions.h"
#import "PDImage.h"
#import "PDImageLibrary.h"

@interface PDLibraryDirectory ()
@property(nonatomic, getter=isMarked) BOOL marked;
@end

@implementation PDLibraryDirectory

@synthesize library = _library;
@synthesize libraryDirectory = _libraryDirectory;
@synthesize titleImageName = _titleImageName;
@synthesize marked = _marked;

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir;
{
  self = [super init];
  if (self == nil)
    return nil;

  _library = [lib retain];
  _libraryDirectory = [dir copy];
  _titleImageName = PDImage_GenericFolder;
  _subitemsNeedUpdate = YES;
  _subimagesNeedUpdate = YES;

  return self;
}

- (void)dealloc
{
  [_library release];
  [_libraryDirectory release];
  for (PDLibraryItem *item in _subitems)
    [item setParent:nil];
  [_subitems release];
  [_subimages release];
  [super dealloc];
}

- (BOOL)applySearchString:(NSString *)str
{
  BOOL matches = [super applySearchString:str];

  NSString *title = [self titleString];

  if (title != nil)
    {
      if ([title rangeOfString:str options:NSCaseInsensitiveSearch].length > 0)
	matches = YES;
    }

  [self setHidden:!matches];

  return matches;
}

- (void)updateSubimages
{
  static dispatch_queue_t queue;
  static dispatch_once_t once;

  dispatch_once(&once, ^{
    queue = dispatch_queue_create("PDLibraryDirectory",
				  DISPATCH_QUEUE_SERIAL);
  });

  NSMutableArray *subimages = [NSMutableArray array];

  [_subimages release];
  _subimages = [subimages retain];

  dispatch_async(queue, ^{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    __block CFTimeInterval last_t = CACurrentMediaTime();

    [_library loadImagesInSubdirectory:_libraryDirectory recursively:NO
     handler:^(PDImage *im) {
       [array addObject:im];

       CFTimeInterval t = CACurrentMediaTime();
       if (t - last_t > .5)
	 {
	   last_t = t;
	   dispatch_async(dispatch_get_main_queue(), ^{
	     [subimages addObjectsFromArray:array];
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
	  [subimages addObjectsFromArray:array];
	  [[NSNotificationCenter defaultCenter]
	   postNotificationName:PDLibraryItemSubimagesDidChange
	   object:self];
	});
      }
      
    [array release];
  });

  _subimagesNeedUpdate = NO;
}

- (NSString *)path
{
  return [[_library path] stringByAppendingPathComponent:_libraryDirectory];
}

/* Returns true if contents of _subitems array was changed. */

- (BOOL)updateSubitems
{
  BOOL changed = NO;

  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir_path = [self path];

  /* Rebuild the subitems array nondestructively. */

  NSMutableArray *new_subitems = [_subitems mutableCopy];
  if (new_subitems == nil)
    new_subitems = [[NSMutableArray alloc] init];

  for (PDLibraryDirectory *item in new_subitems)
    [item setMarked:YES];

  for (NSString *file in [fm contentsOfDirectoryAtPath:dir_path error:nil])
    {
      if ([file characterAtIndex:0] == '.')
	continue;

      BOOL is_dir = NO;
      NSString *path = [dir_path stringByAppendingPathComponent:file];
      if (![fm fileExistsAtPath:path isDirectory:&is_dir] || !is_dir)
	continue;

      NSString *subdir = [_libraryDirectory
			  stringByAppendingPathComponent:file];

      BOOL found = NO;

      for (PDLibraryDirectory *item in new_subitems)
	{
	  if ([[item libraryDirectory] isEqualToString:subdir])
	    {
	      [item setMarked:NO];
	      found = YES;
	      break;
	    }
	}

      if (!found)
	{
	  PDLibraryDirectory *item = [[PDLibraryDirectory alloc]
				      initWithLibrary:_library
				      directory:subdir];
	  if (item != nil)
	    {
	      [item setParent:self];
	      [new_subitems addObject:item];
	      [item release];
	      changed = YES;
	    }
	}
    }

  NSInteger count = [new_subitems count];
  for (NSInteger i = 0; i < count;)
    {
      PDLibraryDirectory *item = [new_subitems objectAtIndex:i];
      if ([item isMarked])
	{
	  [new_subitems removeObjectAtIndex:i];
	  [item setParent:nil];
	  count--;
	}
      else
	i++;
    }

  _subitems = [new_subitems copy];
  [new_subitems release];

  _subitemsNeedUpdate = NO;

  return changed;
}

- (NSArray *)subitems
{
  if (_subitemsNeedUpdate)
    [self updateSubitems];

  return _subitems;
}

- (NSArray *)subimages
{
  if (_subimagesNeedUpdate)
    [self updateSubimages];

  NSMutableArray *images = [NSMutableArray array];

  [images addObjectsFromArray:_subimages];

  for (PDLibraryDirectory *item in [self subitems])
    {
      if (![item isHidden])
	[images addObjectsFromArray:[item subimages]];
    }

  return images;
}

- (NSString *)titleString
{
  if ([_libraryDirectory length] == 0)
    return [_library name];

  NSString *title = [_libraryDirectory lastPathComponent];

  if ([title length] == 0)
    title = _libraryDirectory;

  return [title stringByReplacingOccurrencesOfString:@":" withString:@"/"];
}

- (BOOL)hasTitleImage
{
  return YES;
}

- (NSImage *)titleImage
{
  return PDImageWithName(_titleImageName);
}

- (BOOL)isExpandable
{
  return [[self subitems] count] != 0;
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
  return ([_libraryDirectory length] == 0
	  ? [[_library path] stringByAbbreviatingWithTildeInPath]
	  : [_libraryDirectory lastPathComponent]);
}

- (PDLibraryDirectory *)subitemContainingDirectory:(NSString *)dir
{
  if (![dir hasPathPrefix:_libraryDirectory])
    return nil;

  if ([_libraryDirectory isEqualToString:dir])
    return self;

  for (PDLibraryDirectory *item in [self subitems])
    {
      item = [item subitemContainingDirectory:dir];
      if (item != nil)
	return item;
    }

  /* Not an exact match, but we don't have a subitem for the actual
     directory requested (yet). */

  return self;
}

- (void)invalidateContents
{
  _subitemsNeedUpdate = YES;
  _subimagesNeedUpdate = YES;
}

- (BOOL)needsUpdate
{
  BOOL ret = [super needsUpdate];

  if ([self updateSubitems])
    ret = YES;

  /* FIXME: should also rescan subimages somehow, but don't need to
     return YES from here if they have changed (as they don't affect
     the source list structure). */

  return ret;
}

@end
