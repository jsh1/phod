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

#import "PDViewController.h"

@class PDImageViewController, PDImage, PDImageLayer, CALayer;

@interface PDImageView : NSView

@property(nonatomic, weak) IBOutlet PDImageViewController *controller;

@property(nonatomic, strong) PDImage *image;
@property(nonatomic, assign) CGFloat imageScale;
@property(nonatomic, assign) CGPoint imageOrigin;
@property(nonatomic, assign) BOOL displaysMetadata;

@property(nonatomic, assign, readonly) CGFloat scaleToFitScale;
@property(nonatomic, assign, readonly) CGFloat scaleToFillScale;
@property(nonatomic, assign, readonly) CGFloat scaleToActualScale;

- (void)setImageScale:(CGFloat)scale preserveOrigin:(BOOL)flag;

- (void)viewDidDisappear;

@end
