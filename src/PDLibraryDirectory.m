// -*- c-style: gnu -*-

#import "PDLibraryDirectory.h"

#import "PDLibraryImage.h"

@implementation PDLibraryDirectory

@synthesize path = _path;

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];

  return self;
}

- (void)dealloc
{
  [_path release];
  [_subitems release];
  [_images release];
  [_subimages release];
  [super dealloc];
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

      for (NSString *file in [fm contentsOfDirectoryAtPath:_path error:nil])
	{
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  path = [_path stringByAppendingPathComponent:file];
	  dir = NO;
	  if (![fm fileExistsAtPath:path isDirectory:&dir])
	    continue;

	  if (dir)
	    {
	      subitem = [[PDLibraryDirectory alloc] initWithPath:path];

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
  NSFileManager *fm;
  NSMutableArray *array;
  NSString *path;
  BOOL dir;
  PDLibraryImage *image;

  if (_subimages == nil)
    {
      fm = [NSFileManager defaultManager];
      array = [[NSMutableArray alloc] init];

      for (NSString *file in [fm contentsOfDirectoryAtPath:_path error:nil])
	{
	  if ([file characterAtIndex:0] == '.')
	    continue;

	  path = [_path stringByAppendingPathComponent:file];
	  dir = NO;
	  if (![fm fileExistsAtPath:path isDirectory:&dir])
	    continue;

	  if (!dir)
	    {
	      image = [[PDLibraryImage alloc] initWithPath:path];

	      if (image != nil)
		{
		  [array addObject:image];
		  [image release];
		}
	    }
	}

      for (PDLibraryDirectory *item in [self subitems])
	[array addObjectsFromArray:[item subimages]];

      _subimages = [array copy];
      [array release];
    }

  return _subimages;
}

- (NSString *)titleString
{
  return [_path lastPathComponent];
}

- (BOOL)isExpandable
{
  return [self numberOfSubitems] != 0;
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
