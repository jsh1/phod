// -*- c-style: gnu -*-

#import "PDLibraryItem.h"

@interface PDLibraryImage : NSObject
{
  NSString *_path;
}

- (id)initWithPath:(NSString *)path;

@property(nonatomic, readonly) NSString *path;

- (void)drawInContext:(CGContextRef)ctx rect:(CGRect)r
    options:(NSDictionary *)dict;

- (void)defineContentsOfLayer:(CALayer *)layer options:(NSDictionary *)dict;

@end
