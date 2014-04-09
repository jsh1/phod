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

@interface PDFileCatalog : NSObject

- (id)init;
- (id)initWithContentsOfFile:(NSString *)path;

- (void)invalidate;

/* Writes the current contents of the catalog to 'path'. If the
   receiver was initialized from the contents of a file, 'path' should
   be the same file (i.e. no data will be written if the receiver
   believes that it has not changed since being initialized). */

- (void)synchronizeWithContentsOfFile:(NSString *)path;

/* Returns the identifier of 'path'. The interpretation of 'path' is
   wholly defined by the caller, though if -renameDirectory:to: is
   later called, it should be formatted as a (possibly relative) file
   system path string, i.e. with components separated by the normal
   path separator string. */

- (uint32_t)fileIdForPath:(NSString *)path;

/* Returns the set of all ids currently stored in the catalog. */

- (NSIndexSet *)allFileIds;

/* Calling these methods is preferred but optional. If files are moved
   around and these methods are not called, new ids will be created for
   files when they are next seen. */

- (void)renameDirectory:(NSString *)oldName to:(NSString *)newName;
- (void)renameFile:(NSString *)oldName to:(NSString *)newName;
- (void)removeFileWithPath:(NSString *)path;

@end
