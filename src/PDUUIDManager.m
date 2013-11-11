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

#import "PDUUIDManager.h"

#import <sqlite3.h>
#import <sys/stat.h>

#define TRY(x)								\
  do {									\
    int err = x;							\
    if (x != SQLITE_OK)							\
      {									\
	NSLog(@"SQLite error: %d: %s", err, sqlite3_errmsg(_handle));	\
	abort();							\
      }									\
  } while(0)

@implementation PDUUIDManager

+ (PDUUIDManager *)sharedManager
{
  static PDUUIDManager *manager;
  NSString *path;

  if (manager == nil)
    {
      path = [[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
				NSUserDomainMask, YES) lastObject]
	       stringByAppendingPathComponent:
		 [[NSBundle mainBundle] bundleIdentifier]]
	      stringByAppendingPathComponent:@"PDUUIDCache"];
      if (path == nil)
	return nil;

      manager = [[PDUUIDManager alloc] initWithPath:path];
    }

  return manager;
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  if (self == nil)
    return nil;

  _path = [path copy];

  NSString *dir = [_path stringByDeletingLastPathComponent];
  
  NSFileManager *fm = [NSFileManager defaultManager];

  BOOL isdir = NO;
  if (![fm fileExistsAtPath:dir isDirectory:&isdir])
    {
      if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES
	    attributes:nil error:nil])
	{
	  [self release];
	  return nil;
	}
    }
  else if (!isdir)
    {
      [self release];
      return nil;
    }

  sqlite3_open_v2([_path UTF8String], (sqlite3**)&_handle,
		  SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);

  if (_handle == NULL)
    {
      [self release];
      return nil;
    }

  sqlite3_exec(_handle, "CREATE TABLE IF NOT EXISTS cache "
	       "(name TEXT PRIMARY KEY, size INTEGER,"
	       "uuid BLOB)", NULL, NULL, NULL);

  return self;
}

- (void)dealloc
{
  [_path release];

  sqlite3_close(_handle);

  [super dealloc];
}

static size_t
file_size(const char *path)
{
  struct stat st;

  if (stat(path, &st) == 0)
    return st.st_size;
  else
    return 0;
}

- (NSUUID *)UUIDOfFileAtPath:(NSString *)path
{
  NSUUID *ret = nil;

  if (_queryStmt == NULL)
    {
      sqlite3_prepare_v2(_handle, "SELECT uuid FROM cache"
			 " WHERE name = ? AND size = ?", -1,
			 (sqlite3_stmt **) &_queryStmt, NULL);
    }

  const char *namestr = [[path lastPathComponent] UTF8String];
  int filesize = (int)file_size([path UTF8String]);

  sqlite3_bind_text(_queryStmt, 1, namestr, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int(_queryStmt, 2, filesize);

  if (sqlite3_step(_queryStmt) == SQLITE_ROW)
    {
      const void *data = sqlite3_column_blob(_queryStmt, 0);
      if (data != NULL)
	ret = [[NSUUID alloc] initWithUUIDBytes:data];
    }
  else
    {
      ret = [[NSUUID alloc] init];

      if (_insertStmt == NULL)
	{
	  sqlite3_prepare_v2(_handle, "INSERT INTO cache VALUES(?, ?, ?)",
			     -1, (sqlite3_stmt **) &_insertStmt, NULL);
	}

      uuid_t uuid;
      [ret getUUIDBytes:uuid];

      sqlite3_bind_text(_insertStmt, 1, namestr, -1, SQLITE_TRANSIENT);
      sqlite3_bind_int(_insertStmt, 2, filesize);
      sqlite3_bind_blob(_insertStmt, 3, uuid, 16, SQLITE_TRANSIENT);

      if (sqlite3_step(_insertStmt) != SQLITE_DONE)
	NSLog(@"SQL error: couldn't insert new UUID");
      
      sqlite3_reset(_insertStmt);
      sqlite3_clear_bindings(_insertStmt);
    }

  sqlite3_reset(_queryStmt);
  sqlite3_clear_bindings(_queryStmt);

  return ret;
}

@end
