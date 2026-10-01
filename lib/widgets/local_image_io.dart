import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Folder inside the app documents directory that holds the copies this app
/// owns, so [releaseLocalImage] can tell "ours" from "the picker's cache".
const _folder = 'product_images';

/// Takes ownership of [picked] and returns the reference to keep.
///
/// The gallery and file pickers both hand back files that live in a
/// platform-owned cache directory, which Android is free to clear at any time —
/// a product added last week would silently lose its picture. Copying into the
/// app's own documents directory is what makes the reference durable, so it
/// survives a restart the way a backend URL would.
Future<String> retainLocalImage(XFile picked) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    final target =
        '${dir.path}/product_${DateTime.now().microsecondsSinceEpoch}'
        '${_extensionOf(picked.path)}';
    return (await File(picked.path).copy(target)).path;
  } catch (_) {
    // With no writable documents directory the picker's own path is the best
    // reference left, and it still previews for the rest of the session.
    return picked.path;
  }
}

/// Resolves a retained reference, or null when the file is gone — a photo can
/// be cleared by the user, or invalidated by a reinstall.
ImageProvider? localImageProvider(String reference) {
  final target = reference.trim();
  if (target.isEmpty) return null;
  return File(target).existsSync() ? FileImage(File(target)) : null;
}

/// Deletes a copy this app made. Best-effort: anything outside the app's own
/// folder was never ours to remove, so it is left alone.
Future<void> releaseLocalImage(String reference) async {
  final target = reference.trim();
  if (target.isEmpty || !target.contains(_folder)) return;
  try {
    final file = File(target);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Nothing to do — the reference is about to be dropped either way.
  }
}

String _extensionOf(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '.jpg' : name.substring(dot).toLowerCase();
}
