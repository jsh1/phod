
## Photo App Project

This is a work-in-progress Mac photo management app.

### Manifesto

1. Remove the "photo database as opaque bundle" concept. The database
is the union of one or more image libraries (directory hierarchies of
image files). Metadata is stored alongside each image. Image libraries
can be edited externally, caches will be rebuilt as needed.

2. Adjustment algorithms will be published. Any edits made today should
be able to reproduced in thirty years time.

3. Handle large images quickly. (My use case is 20MP JPEG+RAW files on
a 3-year-old macbook air. Currently focusing on JPEG.)

4. Use standard Mac graphics frameworks wherever possible.

### Screenshot

![Screenshot](http://unfactored.org/images/phod-screen-2013-12-17.png)
