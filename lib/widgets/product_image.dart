import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'local_image_source.dart';
import 'mv_icon.dart';

/// Whether [value] points at a remote image rather than a file on this device.
bool isRemoteImage(String value) => value.startsWith('http://') || value.startsWith('https://');

/// Resolves a product picture to an [ImageProvider], or null when neither
/// reference is usable so the caller can show its placeholder instead.
///
/// A product carries two independent references, because they come from two
/// different places:
/// * [url] — `media.mainImage` from the backend, always an http(s) URL.
/// * [localPath] — a photo the supplier picked off their own device.
///
/// [localPath] wins when it resolves: it is the picture they just chose, and
/// it is the only one the app can render without a network round-trip. When it
/// does not resolve — a cleared file, a stale reference — the backend URL is
/// used instead, and failing that the caller gets the placeholder.
///
/// The device-local lookup is delegated to [localImageProvider] because how a
/// local photo is read is platform-specific: a file on mobile, a blob URL on
/// the web.
ImageProvider? productImageProvider({String? url, String? localPath}) {
  final local = productLocalProvider(localPath);
  if (local != null) return local;

  final remote = url?.trim() ?? '';
  if (remote.isNotEmpty && isRemoteImage(remote)) return NetworkImage(remote);
  return null;
}

/// [productImageProvider] for the device-local reference alone.
ImageProvider? productLocalProvider(String? localPath) => localImageProvider(localPath ?? '');

/// Product picture for a supplier surface, falling back to the brand placeholder.
///
/// Both thumbnail sizes and the product detail modal use this, so a picked
/// device photo looks the same everywhere a catalogue image is shown.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.url, this.localPath, this.size = 46, this.radius = 9, this.fallbackIcon = 'box'});

  final String? url;
  final String? localPath;
  final double size;
  final double radius;
  final String fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final provider = productImageProvider(url: url, localPath: localPath);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: _fit(context, provider, size)),
    );
  }

  /// A photo that cannot be decoded must not take the whole row down with it,
  /// so it degrades to the same placeholder an image-less product gets.
  Widget _fit(BuildContext context, ImageProvider? provider, double extent) =>
      provider == null
          ? _placeholder(context, extent)
          : Image(image: provider, fit: BoxFit.cover, errorBuilder: (context, _, _) => _placeholder(context, extent));

  Widget _placeholder(BuildContext context, double extent) => ColoredBox(
    color: context.mv.surfaceMuted,
    child: Center(child: MvIcon(fallbackIcon, size: extent * .44, color: context.mv.accentDeep)),
  );
}

/// Product picture sized for the detail modal, where the supplier is actually
/// looking at what they uploaded.
class ProductImagePreview extends StatelessWidget {
  const ProductImagePreview({super.key, this.url, this.localPath});

  final String? url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final provider = productImageProvider(url: url, localPath: localPath);
    Widget placeholder() => ColoredBox(
      color: context.mv.surfaceMuted,
      child: Center(child: MvIcon('box', size: 34, color: context.mv.accentDeep)),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child:
            provider == null
                ? placeholder()
                : Image(image: provider, fit: BoxFit.cover, errorBuilder: (context, _, _) => placeholder()),
      ),
    );
  }
}
