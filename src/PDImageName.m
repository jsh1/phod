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

#import "PDImageName.h"

#import "PDImage.h"
#import "PDImageLibrary.h"

NSString *const PDImageNameType = @"org.unfactored.Phod.PDImageName";

@implementation PDImageName

@synthesize libraryId = _libraryId;
@synthesize imageId = _imageId;

+ (PDImageName *)nameOfImage:(PDImage *)image
{
  PDImageName *name = [[PDImageName alloc] init];
  name->_libraryId = [[image library] libraryId];
  name->_imageId = [image imageId];
  return [name autorelease];
}

- (BOOL)isEqual:(id)obj
{
  if ([obj class] != [self class])
    return NO;

  PDImageName *rhs = obj;
  return _libraryId == rhs->_libraryId && _imageId == rhs->_imageId;
}

- (NSUInteger)hash
{
  return _libraryId + (_imageId * 33);
}

- (BOOL)matchesImage:(PDImage *)image
{
  return (_libraryId == [[image library] libraryId]
	  && _imageId == [image imageIdIfDefined]);
}

- (id)propertyList
{
  return @{
    @"libraryId": @(_libraryId),
    @"imageId": @(_imageId),
  };
}

- (id)initWithPropertyList:(id)obj
{
  self = [self init];
  if (self == nil)
    return nil;

  _libraryId = [[obj objectForKey:@"libraryId"] unsignedIntValue];
  _imageId = [[obj objectForKey:@"imageId"] unsignedIntValue];

  return self;
}

+ (PDImageName *)imageNameFromPropertyList:(id)obj
{
  return [[[PDImageName alloc] initWithPropertyList:obj] autorelease];
}

- (id)copyWithZone:(NSZone *)zone
{
  PDImageName *name = [[PDImageName alloc] init];
  name->_libraryId = _libraryId;
  name->_imageId = _imageId;
  return name;
}

// NSPasteboardWriting methods

- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pboard
{
  return @[PDImageNameType];
}

- (id)pasteboardPropertyListForType:(NSString *)type
{
  if ([type isEqualToString:PDImageNameType])
    return [self propertyList];
  else
    return nil;
}

// NSPasteboardReading methods

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pboard
{
  return @[PDImageNameType];
}

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type
    pasteboard:(NSPasteboard *)pboard
{
  if ([type isEqualToString:PDImageNameType])
    return NSPasteboardReadingAsPropertyList;
  else
    return 0;
}

- (id)initWithPasteboardPropertyList:(id)obj ofType:(NSString *)type
{
  if ([type isEqualToString:PDImageNameType])
    return [self initWithPropertyList:obj];

  [self release];
  return nil;
}

@end
