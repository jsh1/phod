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

#import "PDFileCatalog.h"

@implementation PDFileCatalog

- (id)init
{
  self = [super init];
  if (self == nil)
    return nil;

  _queue = dispatch_queue_create("PDFileCatalog",
					DISPATCH_QUEUE_SERIAL);

  _dict[1] = [[NSMutableDictionary alloc] init];

  return self;
}

- (id)initWithContentsOfFile:(NSString *)path
{
  self = [self init];
  if (self == nil)
    return nil;

  NSData *data = [[NSData alloc] initWithContentsOfFile:path];
  if (data != nil)
    {
      id obj = [NSJSONSerialization
		JSONObjectWithData:data options:0 error:nil];

      if ([obj isKindOfClass:[NSDictionary class]])
	_dict[0] = [[obj objectForKey:@"catalog"] mutableCopy];

      _lastFileId = [[obj objectForKey:@"lastFileId"] unsignedIntValue];

      [data release];
    }

  return self;
}

- (void)dealloc
{
  dispatch_sync(_queue, ^{});
  dispatch_release(_queue);
  [_dict[0] release];
  [_dict[1] release];
  [super dealloc];
}

- (void)synchronizeWithContentsOfFile:(NSString *)path
{
  /* _dirty is only set when files are renamed or new ids are added to
     _dict[1]. So we also check if _dict[0] is non-empty, in that case
     the current state is different to what was read from the file
     system.

     Note: this could be async, except we don't wait for it to finish
     before terminating the app!? */

  dispatch_sync(_queue, ^
    {
      if (_dirty || [_dict[0] count] != 0)
	{
	  NSDictionary *obj = @{@"catalog": _dict[1],
				@"lastFileId": @(_lastFileId)};

	  NSData *data = [NSJSONSerialization
			  dataWithJSONObject:obj options:0 error:nil];

	  if ([data writeToFile:path atomically:YES])
	    {
	      _dirty = NO;

	      [_dict[0] release];
	      _dict[0] = nil;
	    }
	  else
	    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	}
    });
}

- (void)renameDirectory:(NSString *)oldName to:(NSString *)newName
{
  /* Calling this method is preferred but optional. If directories are
     renamed without doing so we'd just recreate the caches under the
     new names and purge the old state after relaunching a couple of
     times. */

  dispatch_async(_queue, ^
    {
      NSInteger old_len = [oldName length];

      for (int pass = 0; pass < 2; pass++)
	{
	  NSMutableDictionary *catalog = _dict[pass];

	  /* Cons up the list of known files under the moved directory
	     (can't modify the dictionary while iterating over its keys). */

	  NSMutableArray *matches = [[NSMutableArray alloc] init];

	  NSString *oldDir = [oldName stringByAppendingString:@"/"];

	  for (NSString *key in catalog)
	    {
	      if ([key hasPrefix:oldDir])
		[matches addObject:key];
	    }

	  if ([matches count] != 0)
	    {
	      for (NSString *key in matches)
		{
		  NSString *new_key = [newName stringByAppendingPathComponent:
				       [key substringFromIndex:old_len + 1]];
		  [catalog setObject:[catalog objectForKey:key]
		   forKey:new_key];
		  [catalog removeObjectForKey:key];
		}

	      _dirty = YES;
	    }

	  [matches release];
	}
    });
}

- (void)renameFile:(NSString *)oldName to:(NSString *)newName
{
  dispatch_async(_queue, ^
    {
      for (int pass = 0; pass < 2; pass++)
	{
	  NSMutableDictionary *catalog = _dict[pass];

	  id value = [catalog objectForKey:oldName];
	  if (value != nil)
	    {
	      [catalog setObject:value forKey:newName];
	      [catalog removeObjectForKey:oldName];
	    }
	}
    });
}

- (void)removeFileWithPath:(NSString *)path
{
  dispatch_async(_queue, ^
    {
      for (int pass = 0; pass < 2; pass++)
	{
	  NSMutableDictionary *catalog = _dict[pass];

	  if (!_dirty && [catalog objectForKey:path] != nil)
	    _dirty = YES;

	  [catalog removeObjectForKey:path];

	  /* FIXME: also remove anything in the cache for these ids? */
	}
    });
}

- (uint32_t)fileIdForPath:(NSString *)path
{
  __block uint32_t fid = 0;

  dispatch_sync(_queue, ^
    {
      NSNumber *obj = [_dict[1] objectForKey:path];

      if (obj == nil)
	{
	  obj = [_dict[0] objectForKey:path];

	  /* We place the deserialized dictionary in _dict[0], and the
	     current dictionary in _dict[1]. We know that all extant
	     files will have their ids queried at least once when the
	     library is scanned on startup, so by moving entries from
	     the old to new dictionaries we effectively remove stale
	     entries from the current version. */

	  if (obj != nil)
	    {
	      [_dict[1] setObject:obj forKey:path];
	      [_dict[0] removeObjectForKey:path];
	    }
	}

      if (obj != nil)
	fid = [obj unsignedIntValue];
      else
	{
	  fid = ++_lastFileId;

	  [_dict[1] setObject:
	   [NSNumber numberWithUnsignedInt:fid] forKey:path];
	  _dirty = YES;
	}
    });

  return fid;
}

- (NSIndexSet *)allFileIds
{
  __block NSIndexSet *ret = nil;

  dispatch_sync(_queue, ^
    {
      NSMutableIndexSet *catalog = [NSMutableIndexSet indexSet];

      for (int i = 0; i < 2; i++)
	for (NSString *key in _dict[i])
	  [catalog addIndex:[[_dict[i] objectForKey:key] unsignedIntValue]];

      ret = catalog;
    });

  return ret;
}

@end
