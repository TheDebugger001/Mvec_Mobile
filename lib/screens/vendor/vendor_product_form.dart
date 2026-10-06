import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/catalog.dart';
import '../../models/vendor_product.dart';
import '../../providers/vendor_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/local_image_source.dart';
import '../../widgets/mv_icon.dart';
import '../../widgets/product_image.dart';
import '../../widgets/product_image_field.dart';
import '../../services/vendor_product_image_store.dart';

/// Opens the add / edit product sheet. [product] null creates a new listing.
Future<void> showVendorProductForm(
  BuildContext context, {
  VendorProduct? product,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => VendorProductFormSheet(product: product),
  );
}

/// Add / edit product form.
///
/// Four blocks, in the order a vendor fills them:
///  1. basic info — name, SKU, brand, category (with an inline creator), notes;
///  2. pricing & inventory — regular price, discount price, stock, reorder point;
///  3. variants — repeatable colour / size / weight rows;
///  4. media — device photos and gallery URLs;
///  5. availability — the listing status and a live toggle.
class VendorProductFormSheet extends ConsumerStatefulWidget {
  const VendorProductFormSheet({super.key, this.product});
  final VendorProduct? product;

  @override
  ConsumerState<VendorProductFormSheet> createState() =>
      _VendorProductFormSheetState();
}

class _VendorProductFormSheetState
    extends ConsumerState<VendorProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _brand;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _discountPrice;
  late final TextEditingController _stock;
  late final TextEditingController _lowStockAt;
  late final TextEditingController _thumbnail;
  late final List<TextEditingController> _gallery;
  late String _localImagePath = widget.product?.localImagePath ?? '';
  late final ProductImageDraft _imageDraft = ProductImageDraft(_localImagePath);
  late final List<String> _localGalleryPaths = [
    for (final path in widget.product?.localImagePaths ?? const <String>[])
      if (path != _localImagePath) path,
  ];
  late final ProductImageCollectionDraft _galleryImageDraft =
      ProductImageCollectionDraft(_localGalleryPaths);
  final _localImageStore = VendorProductImageStore();

  /// One editable spec row. Controllers live here so they can be disposed
  /// together with the row.
  final List<_VariantDraft> _variants = [];

  String? _categoryId;
  String _status = VendorProductStatus.draft;

  bool get _isEdit => widget.product?.id != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _sku = TextEditingController(text: p?.sku ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _price = TextEditingController(text: _num(p?.price));
    _discountPrice = TextEditingController(text: _num(p?.discountPrice));
    _stock = TextEditingController(text: p?.stockQuantity?.toString() ?? '');
    _lowStockAt = TextEditingController(
      text: (p?.lowStockThreshold ?? 5).toString(),
    );
    _thumbnail = TextEditingController(text: p?.thumbnail ?? '');

    final gallery = p?.gallery ?? const <String>[];
    // The thumbnail has its own field; keep only the extra images here.
    _gallery = [
      for (final url in gallery.where((u) => u != p?.thumbnail))
        TextEditingController(text: url),
    ];

    _variants.addAll([
      for (final v in p?.variantList ?? const <ProductVariant>[])
        _VariantDraft.of(v),
    ]);

    _categoryId = p?.categoryId;
    // A new listing starts as a draft so it is never published by accident.
    _status = p?.availability ?? VendorProductStatus.draft;
  }

  @override
  void dispose() {
    unawaited(_imageDraft.resolve(saved: false));
    unawaited(_galleryImageDraft.resolve(saved: false));
    for (final c in [
      _name,
      _sku,
      _brand,
      _description,
      _price,
      _discountPrice,
      _stock,
      _lowStockAt,
      _thumbnail,
      ..._gallery,
    ]) {
      c.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  static String _num(num? v) =>
      v == null
          ? ''
          : (v is int || v.toStringAsFixed(0) == v.toString()
              ? v.toString()
              : v.toString());

  /// Assembles the request body, dropping fields the vendor left blank.
  Map<String, dynamic> _body() {
    final p = widget.product;
    final price = num.tryParse(_price.text.trim());
    final discount = num.tryParse(_discountPrice.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final lowStockAt = int.tryParse(_lowStockAt.text.trim());
    final thumbnail = _blankToNull(_thumbnail.text);

    return {
      'name': _name.text.trim(),
      'price': price,
      'discountPrice': discount,
      'stockQuantity': stock,
      'lowStockThreshold': lowStockAt,
      'brand': _blankToNull(_brand.text),
      'sku': _blankToNull(_sku.text),
      'description': _blankToNull(_description.text),
      if (thumbnail != null)
        'media': {
          'mainImage': thumbnail,
          'gallery': [
            for (final c in _gallery)
              if (c.text.trim().isNotEmpty) c.text.trim(),
          ],
        },
      'category': _categoryId ?? _blankToNull(p?.categoryId ?? ''),
      'status': _status,
      'variants': [
        for (final v in _variants)
          if (!v.isEmpty) v.toJson(),
      ],
    };
  }

  static String? _blankToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final body = _body();
    final id = widget.product?.id;
    final ok =
        id == null
            ? await ref
                .read(vendorProductControllerProvider.notifier)
                .createProduct(body)
            : await ref
                .read(vendorProductControllerProvider.notifier)
                .updateProduct(id, body);
    if (!mounted) return;

    final state = ref.read(vendorProductControllerProvider);
    if (ok) {
      final productId = state.savedProduct?.id ?? id;
      String? imageWarning;
      var imageReferencesSaved = false;
      try {
        final localImages = [
          if (_localImagePath.isNotEmpty) _localImagePath,
          ..._localGalleryPaths,
        ];
        if (productId == null && localImages.isNotEmpty) {
          throw StateError(
            'The product was saved, but the API returned no product ID, '
            'so the device image could not be linked to it.',
          );
        }
        if (productId != null) {
          await _localImageStore.saveAll(productId, localImages);
        }
        imageReferencesSaved = true;
      } catch (e) {
        imageWarning =
            'Product saved, but the device image could not be '
            'saved on this device: ${friendlyError(e)}';
      }
      await _imageDraft.resolve(saved: imageReferencesSaved);
      await _galleryImageDraft.resolve(saved: imageReferencesSaved);
      if (!mounted) return;
      Navigator.pop(context);
      showMvSnack(
        context,
        imageWarning ?? state.success ?? 'Product saved',
        success: imageWarning == null,
      );
    } else {
      showMvSnack(context, state.error ?? 'Could not save the product');
    }
  }

  /// Keeps the draft's status aligned with its stock level.
  void _onStockChanged() {
    final qty = int.tryParse(_stock.text.trim());
    if (qty == null || qty > 0) return;
    if (_status == VendorProductStatus.active) {
      setState(() => _status = VendorProductStatus.outOfStock);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mutation = ref.watch(vendorProductControllerProvider);
    final categoriesAsync = ref.watch(vendorCategoriesProvider);
    final busy = mutation.busy;
    final stock = int.tryParse(_stock.text.trim());

    return Padding(
      // Lift the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .9,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(busy),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _basicInfo(categoriesAsync),
                      const SizedBox(height: 14),
                      _pricing(stock),
                      const SizedBox(height: 14),
                      _variantsCard(),
                      const SizedBox(height: 14),
                      _media(),
                      const SizedBox(height: 14),
                      _availability(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
            _footer(busy),
          ],
        ),
      ),
    );
  }

  Widget _header(bool busy) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEdit ? 'Edit product' : 'Add product',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isEdit
                          ? 'Update the details of this listing'
                          : 'List a new product in your store',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(bool busy) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: OutlineMvButton(
              label: 'Cancel',
              onPressed: busy ? null : () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GradientButton(
              label:
                  busy
                      ? 'Saving…'
                      : (_isEdit ? 'Update product' : 'Save product'),
              icon: 'check',
              expanded: true,
              onPressed: busy ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 1. BASIC INFO ──────────────────────────────────────────────────────
  Widget _basicInfo(AsyncValue<List<CategoryRecord>> categoriesAsync) {
    return DataCard(
      title: 'Basic information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text(_name, 'Product name *', required: true, maxLength: 120),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _text(_sku, 'SKU', hint: 'e.g. FRV-001')),
              const SizedBox(width: 12),
              Expanded(child: _text(_brand, 'Brand')),
            ],
          ),
          const SizedBox(height: 12),
          _categoryField(categoriesAsync),
          const SizedBox(height: 12),
          _text(
            _description,
            'Description *',
            hint: 'Materials, dimensions, care instructions…',
            required: true,
            maxLines: 3,
            maxLength: 1000,
          ),
        ],
      ),
    );
  }

  Widget _categoryField(AsyncValue<List<CategoryRecord>> categoriesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (categoriesAsync) {
          AsyncData(:final value) => DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category *'),
            hint: const Text('Select a category'),
            items: [
              for (final c in value)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    c.name ?? 'Untitled',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
            validator:
                (value) => value == null ? 'Select a category' : null,
          ),
          AsyncError(:final error) => _readOnlyCategory(friendlyError(error)),
          _ => const LinearProgressIndicator(minHeight: 2),
        },
      ],
    );
  }

  Widget _readOnlyCategory(String message) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Category',
        helperText: message,
        helperStyle: TextStyle(
          fontSize: 11,
          color: Theme.of(context).hintColor,
        ),
      ),
      child: Text(
        _categoryId == null
            ? 'Could not load categories'
            : (_categoryId ?? '—'),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  // ─── 2. PRICING & INVENTORY ─────────────────────────────────────────────
  Widget _pricing(int? stock) {
    return DataCard(
      title: 'Pricing & inventory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _text(
                  _price,
                  'Regular price *',
                  required: true,
                  numeric: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _text(_discountPrice, 'Discount price', numeric: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _priceLabel(),
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Stock quantity *',
                  ),
                  onChanged: (_) {
                    _onStockChanged();
                    setState(() {});
                  },
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) {
                      return 'Stock quantity is required';
                    }
                    if (int.tryParse(v!.trim()) == null) {
                      return 'Enter a whole number';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lowStockAt,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Low stock alert at',
                    helperText: 'Alerts you below this',
                  ),
                ),
              ),
            ],
          ),
          if (stock != null && stock > 0 && stock <= _lowStockThreshold()) ...[
            const SizedBox(height: 10),
            _note(
              'This product will be flagged as low stock until you restock above ${_lowStockThreshold()} units.',
              MvColors.warningText,
            ),
          ],
        ],
      ),
    );
  }

  int _lowStockThreshold() => int.tryParse(_lowStockAt.text.trim()) ?? 5;

  String _priceLabel() {
    final price = num.tryParse(_price.text.trim());
    final discount = num.tryParse(_discountPrice.text.trim());
    if (price == null || discount == null) {
      return 'Prices are in RWF. Leave the discount empty for no offer.';
    }
    if (discount >= price) {
      return 'The discount price must be lower than the regular price.';
    }
    return 'Buyers pay ${money(discount)} — ${(((price - discount) / price) * 100).round()}% off ${money(price)}';
  }

  // ─── 3. VARIANTS ────────────────────────────────────────────────────────
  Widget _variantsCard() {
    return DataCard(
      title: 'Variants',
      subtitle: 'Optional specs such as colour, size or weight.',
      trailing: TextButton.icon(
        onPressed: () => setState(() => _variants.add(_VariantDraft.empty())),
        icon: const MvIcon('plus', size: 14),
        label: const Text('Add'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _variants.length; i++) ...[
            _variantRow(_variants[i], i),
            if (i < _variants.length - 1) const Divider(height: 22),
          ],
          if (_variants.isEmpty)
            Text(
              'No variants — the product is sold as a single item.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _variantRow(_VariantDraft draft, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _text(draft.color, 'Colour')),
            const SizedBox(width: 10),
            Expanded(child: _text(draft.size, 'Size')),
            const SizedBox(width: 10),
            Expanded(child: _text(draft.weight, 'Weight')),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                setState(() {
                  draft.dispose();
                  _variants.removeAt(index);
                });
              },
              icon: const MvIcon('trash', size: 15, color: MvColors.dangerIcon),
              tooltip: 'Remove variant',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _text(draft.sku, 'Variant SKU')),
            const SizedBox(width: 12),
            Expanded(child: _text(draft.stock, 'Variant stock', numeric: true)),
          ],
        ),
      ],
    );
  }

  // ─── 4. MEDIA ───────────────────────────────────────────────────────────
  Widget _media() {
    return DataCard(
      title: 'Media',
      subtitle: 'The first image is used as the listing thumbnail.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductImageField(
            key: ValueKey(_localImagePath),
            draft: _imageDraft,
            url: widget.product?.thumbnail,
            onChanged: (path) => _localImagePath = path ?? '',
          ),
          const SizedBox(height: 8),
          Text(
            'Device photos are saved only on this device. Use a public URL below for an image shared with buyers.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          _thumbnailField(),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Gallery images', style: context.mvEyebrow),
              TextButton.icon(
                onPressed: _pickGalleryFiles,
                icon: const MvIcon('plus', size: 14),
                label: const Text('Add image files'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              TextButton.icon(
                onPressed:
                    () => setState(() => _gallery.add(TextEditingController())),
                icon: const MvIcon('plus', size: 14),
                label: const Text('Add image URL'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_localGalleryPaths.isNotEmpty) ...[
            for (var i = 0; i < _localGalleryPaths.length; i++) ...[
              _localGalleryImage(i),
              if (i < _localGalleryPaths.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
          ],
          for (var i = 0; i < _gallery.length; i++) ...[
            _text(_gallery[i], 'Image ${i + 2}', hint: 'https://…', url: true),
            if (i < _gallery.length - 1) const SizedBox(height: 10),
          ],
          if (_localGalleryPaths.isEmpty && _gallery.isEmpty)
            Text(
              'No gallery images yet.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickGalleryFiles() async {
    try {
      final files = await pickProductImageFiles();
      if (files.isEmpty || !mounted) return;

      final retained = <String>[];
      try {
        for (final file in files) {
          retained.add(await retainLocalImage(file));
        }
      } catch (_) {
        for (final path in retained) {
          await releaseLocalImage(path);
        }
        rethrow;
      }
      if (!mounted) {
        for (final path in retained) {
          await releaseLocalImage(path);
        }
        return;
      }

      setState(() {
        if (_localImagePath.isEmpty && retained.isNotEmpty) {
          _localImagePath = retained.removeAt(0);
          _imageDraft.recorded(_localImagePath);
        }
        _localGalleryPaths.addAll(retained);
        _galleryImageDraft.recorded(_localGalleryPaths);
      });
    } catch (e) {
      if (mounted) showMvSnack(context, friendlyError(e));
    }
  }

  Widget _localGalleryImage(int index) {
    final path = _localGalleryPaths[index];
    final isThumbnail = _localImagePath.isEmpty && index == 0;
    return Row(
      children: [
        ProductImage(
          url: null,
          localPath: path,
          size: 48,
          radius: 8,
          fallbackIcon: 'image',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isThumbnail
                ? 'Thumbnail (first image)'
                : 'Gallery image ${index + 1}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Remove image',
          onPressed: () {
            setState(() {
              _localGalleryPaths.removeAt(index);
              _galleryImageDraft.recorded(_localGalleryPaths);
            });
          },
          icon: const MvIcon('trash', size: 15, color: MvColors.dangerIcon),
        ),
      ],
    );
  }

  /// Thumbnail input with a live preview, mirroring the profile's logo field.
  Widget _thumbnailField() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _thumbnail,
      builder: (context, value, _) {
        final url = value.text.trim();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 58,
              height: 58,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: MvColors.metricIconBg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child:
                  url.isEmpty
                      ? const Center(
                        child: MvIcon(
                          'box',
                          size: 18,
                          color: MvColors.primaryDeep,
                        ),
                      )
                      : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => const Center(
                              child: MvIcon(
                                'box',
                                size: 18,
                                color: MvColors.dangerIcon,
                              ),
                            ),
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _thumbnail,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Thumbnail URL',
                  hintText: 'https://…',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'A public image URL is required by the backend';
                  }
                  return null;
                },
              ),
            ),
            if (url.isNotEmpty) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _thumbnail.clear(),
                icon: const Icon(Icons.close, size: 17),
                tooltip: 'Clear thumbnail',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        );
      },
    );
  }

  // ─── 5. AVAILABILITY ────────────────────────────────────────────────────
  Widget _availability() {
    final isLive = _status == VendorProductStatus.active;
    return DataCard(
      title: 'Availability & status',
      subtitle: 'Decides whether buyers can see and order this listing.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Product status'),
            items: [
              for (final s in VendorProductStatus.all)
                DropdownMenuItem(value: s, child: Text(titleCase(s))),
            ],
            onChanged:
                (v) => setState(() => _status = v ?? VendorProductStatus.draft),
          ),
          const SizedBox(height: 8),
          Text(
            VendorProductStatus.descriptions[_status] ?? '',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).hintColor,
            ),
          ),
          const Divider(height: 26),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: isLive,
            onChanged:
                (v) => setState(
                  () =>
                      _status =
                          v
                              ? VendorProductStatus.active
                              : VendorProductStatus.inactive,
                ),
            title: const Text(
              'Available for sale',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              isLive
                  ? 'Buyers can find and order this product'
                  : 'Hidden from the marketplace',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  // ─── FIELD HELPERS ──────────────────────────────────────────────────────
  Widget _text(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    bool numeric = false,
    bool url = false,
    int? maxLength,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType:
          numeric
              ? TextInputType.number
              : (url
                  ? TextInputType.url
                  : (maxLines > 1
                      ? TextInputType.multiline
                      : TextInputType.text)),
      inputFormatters:
          numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
              : null,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) {
        final v = (value ?? '').trim();
        if (required && v.isEmpty) return '$label is required';
        if (numeric && v.isNotEmpty && num.tryParse(v) == null) {
          return 'Enter a number';
        }
        return null;
      },
    );
  }

  Widget _note(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          MvIcon('bell', size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editable variant row. Controllers are always allocated — a blank field is
/// simply an empty controller — so rows can be added, edited and disposed
/// independently of the rest of the form.
class _VariantDraft {
  _VariantDraft({
    String? color,
    String? size,
    String? weight,
    String? sku,
    String? stock,
  }) : color = TextEditingController(text: color ?? ''),
       size = TextEditingController(text: size ?? ''),
       weight = TextEditingController(text: weight ?? ''),
       sku = TextEditingController(text: sku ?? ''),
       stock = TextEditingController(text: stock ?? '');

  factory _VariantDraft.empty() => _VariantDraft();

  factory _VariantDraft.of(ProductVariant v) => _VariantDraft(
    color: v.color,
    size: v.size,
    weight: v.weight,
    sku: v.sku,
    stock: v.stock?.toString(),
  );

  final TextEditingController color;
  final TextEditingController size;
  final TextEditingController weight;
  final TextEditingController sku;
  final TextEditingController stock;

  /// True when the vendor has not filled anything in yet, so the row is skipped
  /// on save instead of sending empty specs to the API.
  bool get isEmpty =>
      [color, size, weight, sku, stock].every((c) => c.text.trim().isEmpty);

  static String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Map<String, dynamic> toJson() {
    final qty = int.tryParse(stock.text.trim());
    return {
      if (_clean(color) != null) 'color': _clean(color),
      if (_clean(size) != null) 'size': _clean(size),
      if (_clean(weight) != null) 'weight': _clean(weight),
      if (_clean(sku) != null) 'sku': _clean(sku),
      if (qty != null) 'stock': qty,
    };
  }

  void dispose() {
    color.dispose();
    size.dispose();
    weight.dispose();
    sku.dispose();
    stock.dispose();
  }
}
