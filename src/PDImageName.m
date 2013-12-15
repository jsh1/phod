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
@synthesize name = _name;
@synthesize directory = _directory;

+ (PDImageName *)nameOfImage:(PDImage *)image
{
  PDImageName *name = [[PDImageName alloc] init];
  name->_libraryId = [[image library] libraryId];
  name->_name = [[image name] copy];
  name->_directory = [[image libraryDirectory] copy];
  return [name autorelease];
}

- (void)dealloc
{
  [_name release];
  [_directory release];
  [super dealloc];
}

- (BOOL)isEqual:(id)obj
{
  if ([obj class] != [self class])
    return NO;

  PDImageName *rhs = obj;
  return (_libraryId == rhs->_libraryId
	  && [_name isEqualToString:rhs->_name]
	  && [_directory isEqualToString:rhs->_directory]);
}

- (NSUInteger)hash
{
  return [_name hash];
}

- (BOOL)matchesImage:(PDImage *)image
{
  return (_libraryId == [[image library] libraryId]
	  && [_name isEqualToString:[image name]]
	  && [_directory isEqualToString:[image libraryDirectory]]);
}

- (id)propertyList
{
  return @{
    @"libraryId": @(_libraryId),
    @"name": _name,
    @"directory": _directory,
  };
}

- (id)initWithPropertyList:(id)obj
{
  self = [self init];
  if (self == nil)
    return nil;

  _libraryId = [[obj objectForKey:@"libraryId"] unsignedIntValue];
  _name = [[obj objectForKey:@"name"] copy];
  _directory = [[obj objectForKey:@"directory"] copy];

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
  name->_name = [_name retain];
  name->_directory = [_directory retain];
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
    {
      return [self initWithPropertyList:obj];
    }

  [self release];
  return nil;
}

@end
