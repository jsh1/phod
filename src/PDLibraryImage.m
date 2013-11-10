// -*- c-style: gnu -*-

#import "PDLibraryImage.h"

@implementation PDLibraryImage

@synthesize path = _path;

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];

  return self;
}

- (void)drawInContext:(CGContextRef)ctx rect:(CGRect)r
    options:(NSDictionary *)dict
{
}

- (void)defineContentsOfLayer:(CALayer *)layer options:(NSDictionary *)dict
{
}

@end
