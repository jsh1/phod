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

@class PDImage;

@interface PDLibraryItem : NSObject

@property(nonatomic, weak) PDLibraryItem *parent;

@property(nonatomic, assign, getter=isHidden) BOOL hidden;

/* Returns true if item or any subitem matches 'str'. */

- (BOOL)applySearchString:(NSString *)str;

- (void)resetSearchState;

/* Array of PDLibraryItem. Includes hidden items. */

@property(nonatomic, copy, readonly) NSArray *subitems;

/* Iterates 'thunk' recursively over the receiver and all subitems. */

- (BOOL)foreachSubitem:(void (^)(PDLibraryItem *item, BOOL *stop))thunk;

/* Iterates over all images recursively under self. Returns YES if saw
   all images (i.e. wasn't stopped prematurely). */

- (BOOL)foreachSubimage:(void (^)(PDImage *im, BOOL *stop))thunk;

@property(nonatomic, assign, readonly, getter=isTrashcan) BOOL trashcan;
@property(nonatomic, assign, readonly) BOOL nilPredicateIncludesRejected;

@property(nonatomic, copy, readonly) NSString *titleString;

@property(nonatomic, strong, readonly) NSImage *titleImage;

@property(nonatomic, assign, readonly) BOOL hasTitleImage;

@property(nonatomic, assign, readonly, getter=isExpandable)  BOOL expandable;

@property(nonatomic, assign, readonly) BOOL hasBadge;

@property(nonatomic, assign, readonly) NSInteger badgeValue;

@property(nonatomic, assign, readonly) BOOL badgeValueIsNumberOfSubimages;

/* For saving view state. */

@property(nonatomic, copy, readonly) NSString *identifier;

/* For removable devices, unmounts the volume. */

- (void)unmount;

/* Mark any cached state as needing reloading. */

- (void)setNeedsUpdate;

- (BOOL)isDescendantOf:(PDLibraryItem *)item;

@end
