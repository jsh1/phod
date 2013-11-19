
## Photo App Project

This is a work-in-progress Mac photo management app.

### Manifesto

1. Remove the "photo database as opaque bundle" concept. The database
is implicit from a dynamic set of file system folders. Metadata storage
will be per-image, and trivially copyable between hosts.

2. Image adjustment algorithms will be published. Any edits made today
should be able to reproduced in thirty years time.

3. Handle large images quickly. (My use case is 20MP JPEG+RAW files on
a 3-year-old macbook air. But currently focusing on JPEG only.)

4. Use standard Mac graphics frameworks wherever possible.
