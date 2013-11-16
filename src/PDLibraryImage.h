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

#import "PDLibraryItem.h"

@protocol PDLibraryImageHost;

@class PDLibraryImagePrefetchOperation;

@interface PDLibraryImage : NSObject
{
  NSString *_path;
  NSUUID *_uuid;

  CGImageSourceRef _imageSource;
  CFDictionaryRef _imageProperties;

  NSMapTable *_imageHosts;

  PDLibraryImagePrefetchOperation *_prefetchOp;
}

- (id)initWithPath:(NSString *)path;

@property(nonatomic, readonly) NSString *path;

@property(nonatomic, readonly) NSUUID *UUID;

@property(nonatomic, readonly) NSString *title;

- (NSDictionary *)imageProperties;
- (id)imagePropertyForKey:(CFStringRef)key;

/* Convenience accessors image properties. */

@property(nonatomic, readonly) CGSize pixelSize;
@property(nonatomic, readonly) unsigned int orientation;
@property(nonatomic, readonly) CGSize orientedPixelSize;

- (void)startPrefetching;
- (void)stopPrefetching;

- (void)addImageHost:(id<PDLibraryImageHost>)obj;
- (void)removeImageHost:(id<PDLibraryImageHost>)obj;
- (void)updateImageHost:(id<PDLibraryImageHost>)obj;

@end

@protocol PDLibraryImageHost <NSObject>

- (NSDictionary *)imageHostOptions;

- (void)setHostedImage:(CGImageRef)im;

@end

// Hosted image options

extern NSString * const PDLibraryImageHost_Size;	// NSValue<Size>
extern NSString * const PDLibraryImageHost_Thumbnail;	// NSNumber<bool>
