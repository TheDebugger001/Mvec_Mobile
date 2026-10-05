import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

/// Takes ownership of [picked] and returns the reference to keep.
///
/// There is no app-writable directory on the web: the pickers return a blob /
/// object URL that the browser keeps alive for the lifetime of the document, so
/// that URL *is* the reference. It survives navigation within the app, which is
/// exactly the lifetime an app session needs.
Future<String> retainLocalImage(XFile picked) async => picked.path;

/// Resolves a retained reference.
///
/// A blob URL is not a file, so it is fetched through the network stack rather
/// than `FileImage` — `Image.file` on the web is precisely what throws
/// `Unsupported operation: _Namespace`.
ImageProvider? localImageProvider(String reference) {
  final target = reference.trim();
  return target.isEmpty ? null : NetworkImage(target);
}

/// Nothing to release: the browser reclaims the blob URL when the document
/// goes away, and there is no file this app ever created.
Future<void> releaseLocalImage(String reference) async {}
