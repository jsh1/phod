// -*- c-style: gnu -*-

#import <Foundation/Foundation.h>

@interface PDLibraryItem : NSObject

// Array of PDLibraryItem

- (NSArray *)subitems;

- (NSInteger)numberOfSubitems;

// Array of PDLibraryImage, all images recursively under self.

- (NSArray *)subimages;

- (NSInteger)numberOfSubimages;

// For outline view

- (NSImage *)titleImage;
- (NSString *)titleString;

- (BOOL)isExpandable;

- (BOOL)hasBadge;
- (NSInteger)badgeValue;

// Should [recursively] check if anything has changed, return YES if
// something has.

- (BOOL)needsUpdate;

@end
