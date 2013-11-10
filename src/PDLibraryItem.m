// -*- c-style: gnu -*-

#import "PDLibraryItem.h"

#import "PDLibraryImage.h"

@implementation PDLibraryItem

- (NSArray *)subitems
{
  return [NSArray array];
}

- (NSInteger)numberOfSubitems
{
  return [[self subitems] count];
}

- (NSArray *)subimages
{
  return [NSArray array];
}

- (NSInteger)numberOfSubimages
{
  return [[self subimages] count];
}

- (NSImage *)titleImage
{
  return nil;
}

- (NSString *)titleString
{
  return nil;
}

- (BOOL)isExpandable
{
  return NO;
}

- (BOOL)hasBadge
{
  return NO;
}

- (NSInteger)badgeValue
{
  return 0;
}

- (BOOL)needsUpdate
{
  return NO;
}

@end
