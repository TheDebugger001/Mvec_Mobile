import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/utils.dart';
import 'common.dart';
import 'local_image_source.dart';
import 'mv_icon.dart';
import 'product_image.dart';

/// Where a product photo is picked from on the device.
///
/// [ImageSource] only knows about the camera and the photo library, so the
/// "browse files" route is modelled here rather than faked into it.
enum ProductImageSource { gallery, files }

/// The image types the device browser is allowed to return.
///
/// `mimeTypes` is what Android's system file browser filters on; `extensions`
/// is what the iOS document picker maps onto UTIs. Supplying both means neither
/// platform falls back to "any file".
const _images = XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'], mimeTypes: ['image/*']);

/// Tracks the photo files one edit of a product touched, so the copies that
/// ended up unused can be cleaned up at the right moment.
///
/// The moment matters. Every pick claims a new photo, but the product only
/// starts pointing at it once the form is saved — releasing the old reference
/// at pick time would leave a product that was dismissed unsaved pointing at a
/// photo that no longer exists. So the references are collected, not released,
/// and the caller settles them once the outcome is known.
class ProductImageDraft {
  ProductImageDraft(this.initialPath) : _touched = [if (initialPath.isNotEmpty) initialPath];

  /// The photo the product had before this edit started.
  final String initialPath;

  /// Every file this edit has used, in order.
  final List<String> _touched;

  /// The photo the form is leaving with; empty when the picture was removed.
  String current = '';

  /// Records [path] as the newly chosen photo.
  void recorded(String path) {
    current = path;
    if (path.isNotEmpty && !_touched.contains(path)) _touched.add(path);
  }

  /// Deletes the copies this edit replaced.
  ///
  /// [saved] decides which file the product still points at: the chosen one
  /// when the edit was saved, otherwise the original one — in which case
  /// nothing about the product changed and only the abandoned picks are removed.
  Future<void> resolve({required bool saved}) async {
    final keep = saved ? current : initialPath;
    final stale = _touched.where((path) => path != keep).toList(growable: false);
    _touched.clear();
    for (final path in stale) {
      await releaseLocalImage(path);
    }
  }
}

/// Product-photo input for a supplier form.
///
/// The supplier picks a picture off the device — gallery or files — rather
/// than pasting a link, so the field is a preview plus two pick buttons and no
/// text box. The chosen photo is handed to [retainLocalImage] and the returned
/// reference is passed back through [onChanged]; pass null to clear the picture.
///
/// [url] is only used to preview a picture that arrived from the backend, so
/// editing a product does not start blank when it already has one.
class ProductImageField extends StatefulWidget {
  const ProductImageField({super.key, required this.draft, this.url, this.onChanged});

  /// Collects the files this edit touches so the form can settle them once it
  /// knows whether the product was saved.
  final ProductImageDraft draft;

  final String? url;
  final ValueChanged<String?>? onChanged;

  @override
  State<ProductImageField> createState() => _ProductImageFieldState();
}

class _ProductImageFieldState extends State<ProductImageField> {
  late String _localPath = widget.draft.current = widget.draft.initialPath;
  bool _busy = false;

  bool get _hasImage => _localPath.isNotEmpty || (widget.url ?? '').isNotEmpty;

  Future<void> _pick(ProductImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked =
          source == ProductImageSource.files
              ? await _pickFromFiles()
              : await ImagePicker().pickImage(
                source: ImageSource.gallery,
                // Re-encode at a sane size: it caps what gets copied into app
                // storage and turns Android's content URI into a real file.
                maxWidth: 1600,
                maxHeight: 1600,
                imageQuality: 85,
              );
      // A cancelled picker returns null and must leave the field untouched.
      if (picked == null || !mounted) return;

      final stored = await retainLocalImage(picked);
      if (!mounted) return;
      setState(() => _localPath = stored);
      widget.draft.recorded(stored);
      widget.onChanged?.call(stored);
    } catch (e) {
      if (mounted) showMvSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<XFile?> _pickFromFiles() => openFile(acceptedTypeGroups: const [_images]);

  void _clear() {
    setState(() => _localPath = '');
    widget.draft.recorded('');
    widget.onChanged?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductImage(url: widget.url, localPath: _localPath, size: 64, radius: 12, fallbackIcon: 'image'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Product image', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Pick a photo from your gallery or files.', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlineMvButton(
              label: 'Gallery',
              icon: 'image',
              onPressed: _busy ? null : () => _pick(ProductImageSource.gallery),
            ),
            OutlineMvButton(
              label: 'Files',
              icon: 'folder',
              onPressed: _busy ? null : () => _pick(ProductImageSource.files),
            ),
            if (_hasImage)
              TextButton.icon(
                onPressed: _busy ? null : _clear,
                icon: const MvIcon('trash', size: 14),
                label: const Text('Remove photo'),
              ),
          ],
        ),
      ],
    );
  }
}
