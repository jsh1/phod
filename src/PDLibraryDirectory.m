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
{
  PDImageLibrary *_library;
  NSString *_libraryDirectory;
  NSArray *_subitems;
  NSMutableArray *_subimages;
  BOOL _subitemsNeedUpdate;
  BOOL _subimagesNeedUpdate;
  BOOL _marked;
}

@synthesize library = _library;
@synthesize marked = _marked;

+ (BOOL)flattensSubdirectories
{
  return NO;
}

- (id)initWithLibrary:(PDImageLibrary *)lib directory:(NSString *)dir;
{
  self = [super init];
  if (self == nil)
    return nil;

  _library = [lib retain];
  _libraryDirectory = [dir copy];
  _subitemsNeedUpdate = YES;
  _subimagesNeedUpdate = YES;

  return self;
}

- (PDLibraryDirectory *)newItemForSubdirectory:(NSString *)dir
{
  return [[[self class] alloc] initWithLibrary:_library directory:dir];
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

- (NSString *)libraryDirectory
{
  return _libraryDirectory;
}

- (void)setLibraryDirectory:(NSString *)dir
{
  if (![_libraryDirectory isEqualToString:dir])
    {
      [_libraryDirectory release];
      _libraryDirectory = [dir copy];

      [self setNeedsUpdate];
    }
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
  static NSOperationQueue *queue;
  static dispatch_once_t once;

  dispatch_once(&once, ^
    {
      queue = [[NSOperationQueue alloc] init];
      [queue setName:@"PDLibraryDirectory"];
      [queue setMaxConcurrentOperationCount:4];
    });

  /* If this is the first time we're loading the images for this
     directory, feed them piecemeal to the main thread for display. But
     if we've already loaded something and are just updating, don't
     update the UI until everything's finished, to avoid making images
     disappear and then reappear. */

  BOOL update_immediately = _subimages == nil;

  NSMutableArray *new_subimages = [NSMutableArray array];

  [queue addOperation:[NSBlockOperation blockOperationWithBlock:^
    {
      NSMutableArray *local_subimages = [[NSMutableArray alloc] init];
      __block CFTimeInterval last_t = CACurrentMediaTime();

      void (^add_image)(PDImage *image) = ^(PDImage *image)
        {
	  [local_subimages addObject:image];

	  if (update_immediately && CACurrentMediaTime() - last_t > .5)
	    {
	      /* Feed whatever we've read in the last .5s to the UI. */

	      last_t = CACurrentMediaTime();
	      dispatch_async(dispatch_get_main_queue(), ^
		{
		  [new_subimages addObjectsFromArray:local_subimages];
		  [local_subimages removeAllObjects];
		  [[NSNotificationCenter defaultCenter] postNotificationName:
		   PDLibraryItemSubimagesDidChange object:self];
		});
	    }
	};

      [_library loadImagesInSubdirectory:_libraryDirectory
       recursively:[[self class] flattensSubdirectories] handler:add_image];

      if (update_immediately && [local_subimages count] != 0)
	{
	  /* Push remainder to the UI. */

	  dispatch_async(dispatch_get_main_queue(), ^
	    {
	      [new_subimages addObjectsFromArray:local_subimages];
	      [local_subimages removeAllObjects];
	      [[NSNotificationCenter defaultCenter] postNotificationName:
	       PDLibraryItemSubimagesDidChange object:self];
	    });
	}
      else
	{
	  /* Swap our entire array back to the UI. */

	  dispatch_async(dispatch_get_main_queue(), ^
	    {
	      [_subimages release];
	      _subimages = [local_subimages retain];
	      [[NSNotificationCenter defaultCenter] postNotificationName:
	       PDLibraryItemSubimagesDidChange object:self];
	    });
	}

      [local_subimages release];
    }]];

  if (update_immediately)
    {
      [_subimages release];
      _subimages = [new_subimages retain];
    }

  _subimagesNeedUpdate = NO;
}

- (void)updateSubitems
{
  NSMutableArray *new_subitems = [_subitems mutableCopy];
  if (new_subitems == nil)
    new_subitems = [[NSMutableArray alloc] init];

  if (![[self class] flattensSubdirectories])
    {
      /* Rebuild the subitems array nondestructively. */

      for (PDLibraryDirectory *item in new_subitems)
	[item setMarked:YES];

      [_library foreachSubdirectoryOfDirectory:_libraryDirectory
       handler:^(NSString *file)
        {
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
	      PDLibraryDirectory *item = [self newItemForSubdirectory:subdir];

	      if (item != nil)
		{
		  [item setParent:self];
		  [new_subitems addObject:item];
		  [item release];
		}
	    }
	}];

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
    }

  _subitems = [new_subitems sortedArrayUsingComparator:^
    NSComparisonResult (id obj1, id obj2)
    {
      NSString *str1 = [(PDLibraryItem *)obj1 titleString];
      NSString *str2 = [(PDLibraryItem *)obj2 titleString];
      return [str1 compare:str2];
    }];
  [_subitems retain];

  [new_subitems release];

  _subitemsNeedUpdate = NO;
}

- (NSArray *)subitems
{
  if (_subitemsNeedUpdate)
    [self updateSubitems];

  return _subitems;
}

- (BOOL)foreachSubimage:(void (^)(PDImage *im, BOOL *stop))thunk
{
  if (_subimagesNeedUpdate)
    [self updateSubimages];

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
  if ([_libraryDirectory length] == 0)
    return [_library name];

  NSString *title = [_libraryDirectory lastPathComponent];

  if ([title length] == 0)
    title = _libraryDirectory;

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

- (BOOL)badgeValueIsNumberOfSubimages
{
  return YES;
}

- (PDLibraryDirectory *)subitemContainingDirectory:(NSString *)dir
{
  if (![dir hasPathPrefix:_libraryDirectory])
    return nil;

  if ([[self class] flattensSubdirectories]
      || [_libraryDirectory isEqualToString:dir])
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

- (void)setNeedsUpdate
{
  _subitemsNeedUpdate = YES;
  _subimagesNeedUpdate = YES;
}

@end
