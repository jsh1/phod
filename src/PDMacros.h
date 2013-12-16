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

/* Useful macros. */

#undef N_ELEMENTS
#define N_ELEMENTS(x) (sizeof(x) / sizeof((x)[0]))

#undef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))

#undef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))

#undef CLAMP
#define CLAMP(a, b, c) MIN(MAX(a, b), c)

#undef ABS
#define ABS(x) ((a) > 0 ? (a) : -(a))

#undef MIX
#define MIX(a, b, c) ((a) + ((b) - (a)) * (f))

#define POINTER_TO_INT(x) ((intptr_t)(x))
#define INT_TO_POINTER(x) ((void *)(intptr_t)(x))

#define POINTER_TO_UINT(x) ((uintptr_t)(x))
#define UINT_TO_POINTER(x) ((void *)(uintptr_t)(x))

/* Will use alloca() if safe, else malloc(). */

#define STACK_ALLOC(type, count) 		\
  (sizeof(type) * (count) <= 4096 		\
   ? (type *)alloca(sizeof(type) * (count)) 	\
   : (type *)malloc(sizeof(type) * (count)))

#define STACK_FREE(type, count, ptr) 		\
  do {						\
    if (sizeof(type) * (count) > 4096)		\
      free(ptr);				\
  } while (0)
