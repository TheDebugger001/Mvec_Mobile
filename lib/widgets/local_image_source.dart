/// Device-local product photos, split by platform.
///
/// The browser has no file system to copy a picked photo into, so the two
/// implementations differ: mobile copies into app storage and renders the file
/// directly, while web keeps the blob URL the picker hands back and renders it
/// through the network stack. Both expose the same three operations so
/// `ProductImageField` and `ProductImage` never have to know which one they are
/// on — importing `dart:io` unconditionally is what makes the web build throw
/// `Unsupported operation: _Namespace`.
///
/// `dart.library.js_interop` is the current marker for a web target, and the
/// same guard `file_selector` uses.
library;

export 'local_image_io.dart' if (dart.library.js_interop) 'local_image_web.dart';
