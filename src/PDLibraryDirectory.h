// -*- c-style: gnu -*-

#import "PDLibraryItem.h"

@interface PDLibraryDirectory : PDLibraryItem
{
  NSString *_path;
  NSArray *_subitems;
  NSArray *_images;
  NSInteger _imageCount;
  NSArray *_subimages;
}

- (id)initWithPath:(NSString *)path;

@property(nonatomic, readonly) NSString *path;

@end
