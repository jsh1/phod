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

#import "PDImageHash.h"

#import "md5.h"

/* This is lazy, we're only going to hash the first 16KB of each image
   file, and hope that that gives us enough variation to avoid clashes..

   Note: changing this would require the proxy cache to be rebuilt. */

#define HASH_BLOCK 4096
#define HASH_BLOCKS 4

@interface PDImageHash ()
- (id)initWithHash:(const uint8_t *)ptr;
@end

@implementation PDImageHash

+ (PDImageHash *)fileHash:(NSString *)path
{
  int fd = open([path fileSystemRepresentation], O_RDONLY);
  if (fd < 0)
    return nil;

  uint8_t buf[HASH_BLOCK];

  MD5Context md5;
  MD5Init(&md5);

  size_t i;
  for (i = 0; i < HASH_BLOCKS; i++)
    {
      ssize_t len = read(fd, buf, sizeof(buf));
      if (len < 0)
	return nil;
      else if (len == 0)
	break;

      MD5Update(&md5, buf, (uint32_t) len);
    }

  uint8_t digest[16];
  MD5Final(digest, &md5);

  close(fd);

  return [[[self alloc] initWithHash:digest] autorelease];
}

- (id)initWithHash:(const uint8_t *)ptr
{
  self = [super init];
  if (self == nil)
    return nil;

  memcpy(_hash, ptr, 16);

  return self;
}

- (void)dealloc
{
  [_str release];
  [super dealloc];
}

- (NSString *)hashString
{
  if (_str == nil)
    {
      char buf[33];
      size_t i;

      buf[32] = 0;
      for (i = 0; i < 16; i++)
	{
	  buf[31 - (i*2+0)] = "0123456789ABCDEF"[_hash[i] & 15];
	  buf[31 - (i*2+1)] = "0123456789ABCDEF"[_hash[i] >> 4];
	}

      _str = [[NSString alloc] initWithUTF8String:buf];
    }

  return _str;
}

- (NSUInteger)hash
{
  if (_hash1 == 0)
    {
      size_t i;
      for (i = 0; i < 16; i++)
	_hash1 = _hash1 * 33 + _hash[i];

      if (_hash1 == 0)
	_hash1 = 1;
    }

  return _hash1;
}

- (BOOL)isEqual:(id)obj
{
  if (![obj isKindOfClass:[self class]])
    return NO;

  PDImageHash *rhs = obj;
  return (_hash[0] == rhs->_hash[0]
	  && _hash[1] == rhs->_hash[1]
	  && _hash[2] == rhs->_hash[2]
	  && _hash[3] == rhs->_hash[3]);
}

@end
