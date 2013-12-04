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

#import <Foundation/Foundation.h>

extern NSString * const PDLibraryItemSubimagesDidChange;

@interface PDLibraryItem : NSObject
{
  PDLibraryItem *_parent;
  BOOL _hidden;
}

@property(nonatomic, assign) PDLibraryItem *parent;

@property(nonatomic, getter=isHidden) BOOL hidden;

/* Returns true if item or any subitem matches 'str'. */

- (BOOL)applySearchString:(NSString *)str;

- (void)resetSearchState;

/* Array of PDLibraryItem. Includes hidden items. */

- (NSArray *)subitems;

/* Array of PDImage, all images recursively under self. */

- (NSArray *)subimages;

- (NSInteger)numberOfSubimages;

/* For outline view. */

- (NSString *)titleString;

- (NSImage *)titleImage;
- (BOOL)hasTitleImage;

- (BOOL)isExpandable;

- (BOOL)hasBadge;
- (NSInteger)badgeValue;

/* For saving view state. */

- (NSString *)identifier;

/* Should [recursively] check if anything has changed, return YES if
   something has. */

- (BOOL)needsUpdate;

@end
