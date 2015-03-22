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

#import "PDImageUUID.h"

#import "PDImage.h"
#import "PDImageLibrary.h"

NSString *const PDImageUUIDType = @"org.unfactored.Phod.PDImageUUID";

@implementation PDImageUUID

@synthesize UUID = _uuid;

+ (PDImageUUID *)imageUUIDWithUUID:(NSUUID *)uuid
{
  return [[PDImageUUID alloc] initWithUUID:uuid];
}

+ (PDImageUUID *)imageUUIDWithPropertyList:(id)obj
{
  return [[PDImageUUID alloc] initWithPropertyList:obj];
}

- (id)initWithUUID:(NSUUID *)uuid
{
  self = [super init];
  if (self != nil)
    _uuid = [uuid copy];
  return self;
}

- (id)initWithPropertyList:(id)obj
{
  self = [super init];
  if (self != nil)
    {
      if (![obj isKindOfClass:[NSString class]])
	return nil;
      _uuid = [[NSUUID alloc] initWithUUIDString:obj];
    }
  return self;
}

- (BOOL)isEqual:(id)obj
{
  if ([obj isKindOfClass:[PDImageUUID class]])
    return [_uuid isEqual:((PDImageUUID *)obj)->_uuid];
  else
    return NO;
}

- (NSUInteger)hash
{
  return [_uuid hash];
}

- (id)propertyList
{
  return _uuid.UUIDString;
}

- (id)copyWithZone:(NSZone *)zone
{
  return self;
}

// NSPasteboardWriting methods

- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pboard
{
  return @[PDImageUUIDType];
}

- (id)pasteboardPropertyListForType:(NSString *)type
{
  if ([type isEqualToString:PDImageUUIDType])
    return [self propertyList];
  else
    return nil;
}

// NSPasteboardReading methods

+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pboard
{
  return @[PDImageUUIDType];
}

+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type
    pasteboard:(NSPasteboard *)pboard
{
  if ([type isEqualToString:PDImageUUIDType])
    return NSPasteboardReadingAsPropertyList;
  else
    return 0;
}

- (id)initWithPasteboardPropertyList:(id)obj ofType:(NSString *)type
{
  if ([type isEqualToString:PDImageUUIDType])
    return [self initWithPropertyList:obj];
  else
    return nil;
}

@end
