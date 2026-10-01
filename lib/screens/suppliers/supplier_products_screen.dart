import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../features/supplier/data/supplier_workspace.dart';
import '../../models/supplier.dart';
import '../../providers/supplier_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

/// Inventory management for a supplier: list, filter, add, edit and remove
/// the wholesale products they supply.
///
/// `GET /suppliers/me/products` returns the whole catalogue unpaginated, so the
/// table paginates client-side.
class SupplierProductsScreen extends ConsumerWidget {
  const SupplierProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(supplierWorkspaceProvider);
    final productsAsync = ref.watch(supplierProductsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPPLIER PORTAL',
          title: 'Wholesale products',
          subtitle: 'Manage products that vendors can buy in bulk.',
          actions: [
            GradientButton(
              label: 'Add wholesale product',
              icon: 'plus',
              onPressed: () => _openForm(context),
            ),
          eyebrow: 'SUPPLIER PLATFORM',
          title: 'Wholesale products',
          subtitle: 'Manage products that vendors can buy in bulk.',
          actions: [
            GradientButton(label: 'Add product', icon: 'plus', onPressed: () => _openForm(context)),
          ],
        ),
        const InfoBox('Products stay hidden from buyers until your business is verified.'),
        const SizedBox(height: 18),
        switch (workspace) {
          AsyncLoading() => const LoadingState(),
          AsyncError(:final error) => ErrorState(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(supplierWorkspaceProvider),
            ),
          AsyncData(:final value) => _table(context, ref, value.products),
        switch (productsAsync) {
          AsyncLoading() => const LoadingState(),
          AsyncError(:final error) => ErrorState(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(supplierProductsProvider),
            ),
          AsyncData(:final value) => _table(context, ref, value),
          _ => const LoadingState(),
        },
      ],
    );
  }

  Widget _table(BuildContext context, WidgetRef ref, List<SupplierProduct> products) {
    final rows = products
        .map(
          (p) => {
            '_product': p,
            'product': p.name,
            'category': p.category,
            'unit': p.unit,
            'price': money(p.price),
            'stock': '${p.stock}',
            'product': _productCell(p),
            'category': p.category ?? '—',
            'unit': p.unit ?? '—',
            'price': p.wholesalePrice == null ? '—' : money(p.wholesalePrice),
            'stock': '${p.stockQuantity ?? 0}',
            'discount': (p.bulkDiscount ?? 0) > 0 ? '${numFmt(p.bulkDiscount)}%' : '—',
            'availability': StockPill(product: p),
            'status': StatusChip(p.status),
          },
        )
        .toList();

    return SmartTable(
      columns: const [
        MvColumn('product', 'Product', bold: true),
        MvColumn('category', 'Category'),
        MvColumn('price', 'Wholesale price', align: TextAlign.right),
        MvColumn('stock', 'Stock', align: TextAlign.right),
        MvColumn('discount', 'Bulk discount', align: TextAlign.right),
        MvColumn('availability', 'Availability'),
        MvColumn('status', 'Status'),
      ],
      rows: rows,
      actionsLabel: '',
      filterKey: 'status',
      filterOptions: const ['ACTIVE', 'OUT_OF_STOCK', 'ARCHIVED'],
      pageSize: 8,
      emptyMessage: 'No products yet — add your first one.',
      rowActions: (row) {
        final p = row['_product'] as SupplierProduct;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TableActionBtn(
              icon: 'eye',
              tooltip: 'View',
              onPressed: () => _showDetail(context, p),
            ),
            const SizedBox(width: 6),
            TableActionBtn(
              icon: 'edit',
              tooltip: 'Edit',
              onPressed: () => _openForm(context, product: p),
            ),
            const SizedBox(width: 6),
            TableActionBtn(
              icon: 'trash',
              danger: true,
              tooltip: 'Remove',
              onPressed: () => _confirmDelete(context, ref, p),
            ),
          ],
        );
      },
    );
  }

  void _showDetail(BuildContext context, SupplierProduct p) {
    showMvDetailModal(
      context,
      title: 'PRODUCT DETAILS',
      children: [
        Row(
          children: [
            _thumb(p),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${p.category} · per ${p.unit}',
                  Text(p.display, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${p.category ?? 'General'} · per ${p.unit ?? 'piece'}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            StockPill(product: p),
          ],
        ),
        const SizedBox(height: 18),
        KeyValueGrid(
          entries: [
            MapEntry('Wholesale price', money(p.price)),
            // The supplier form no longer collects a retail price and the
            // backend defaults it to 0, so only show it when a real value was
            // actually stored.
            if (p.retailPrice != null && p.retailPrice! > 0)
              MapEntry('Retail price', money(p.retailPrice!)),
            MapEntry('Effective unit price', money(p.effectivePrice)),
            if (p.bulkDiscount > 0)
              MapEntry('Bulk discount', '${numFmt(p.bulkDiscount)}%'),
            MapEntry('Stock', '${p.stock}'),
            MapEntry('Minimum order', '${p.minimumOrderQuantity}'),
            MapEntry('Status', titleCase(p.status)),
            if (p.shortDescription.isNotEmpty)
              MapEntry('Description', p.shortDescription),
            if (p.gallery.isNotEmpty)
              MapEntry('Gallery', '${p.gallery.length} image(s)'),
            MapEntry('Wholesale price', p.wholesalePrice == null ? '—' : money(p.wholesalePrice)),
            MapEntry('Retail price', p.retailPrice == null ? '—' : money(p.retailPrice)),
            MapEntry('Effective unit price', money(p.effectivePrice)),
            if ((p.bulkDiscount ?? 0) > 0)
              MapEntry('Bulk discount', '${numFmt(p.bulkDiscount)}%'),
            MapEntry('Stock', '${p.stockQuantity ?? 0}'),
            MapEntry('Minimum order', '${p.moq ?? 1}'),
            MapEntry('Status', titleCase(p.status ?? 'UNKNOWN')),
            MapEntry('Created', shortDate(p.createdAt)),
            if (p.shortDescription != null && p.shortDescription!.isNotEmpty)
              MapEntry('Description', p.shortDescription!),
            if (p.gallery != null && p.gallery!.isNotEmpty)
              MapEntry('Gallery', '${p.gallery!.length} image(s)'),
          ],
        ),
      ],
      footer: Row(
        children: [
          Expanded(
            child: GradientButton(
              label: 'Edit',
              icon: 'edit',
              expanded: true,
              onPressed: () {
                Navigator.pop(context);
                _openForm(context, product: p);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, {SupplierProduct? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => _ProductFormSheet(product: product),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, SupplierProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text('Remove "${p.name}" from your catalogue? This cannot be undone.'),
        content: Text('Remove "${p.display}" from your catalogue? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || p.id.isEmpty) return;

    try {
      await ref.read(supplierWorkspaceProvider.notifier).deleteProduct(p.id);
      if (context.mounted) showMvSnack(context, 'Product removed', success: true);
    if (ok != true || p.id == null) return;

    try {
      await ref.read(supplierServiceProvider).deleteProduct(p.id!);
      if (context.mounted) showMvSnack(context, 'Product removed', success: true);
      ref.invalidate(supplierProductsProvider);
    } catch (e) {
      if (context.mounted) showMvSnack(context, friendlyError(e));
    }
  }
}

Widget _thumb(SupplierProduct p) {
  final image = p.imageUrl;
  final image = p.mainImage;
  return Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: MvColors.metricIconBg,
      borderRadius: BorderRadius.circular(9),
      image: image.isEmpty ? null : DecorationImage(image: NetworkImage(image), fit: BoxFit.cover),
    ),
    child: image.isEmpty
      image: (image == null || image.isEmpty) ? null : DecorationImage(image: NetworkImage(image), fit: BoxFit.cover),
    ),
    child: (image == null || image.isEmpty)
        ? const Icon(Icons.inventory_2_outlined, size: 20, color: MvColors.primaryDeep)
        : null,
  );
}

/// Stock availability pill driven by [SupplierProduct.stockStatus].
/// Product cell mirroring the web `.admin-product-main`: thumbnail plus the
/// name over a muted "category · MOQ n" caption.
Widget _productCell(SupplierProduct p) {
  return Row(
    children: [
      _thumb(p),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '${p.category ?? 'General'} · MOQ ${p.moq ?? 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: MvColors.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Stock availability pill. Mirrors `SupplierProduct.stockStatus` but keeps
/// the colour logic local to the UI layer.
class StockPill extends StatelessWidget {
  const StockPill({super.key, required this.product});

  final SupplierProduct product;

  Color get _color {
    if (product.isOutOfStock) return MvColors.errorText;
    if (product.isLowStock) return MvColors.warningText;
    return MvColors.successText;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        product.stockStatus,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: .3),
      ),
    );
  }
}

/// Add / edit sheet for a supplier product. The same widget covers both
/// modes: a null [product] creates, a non-null one updates.
class _ProductFormSheet extends ConsumerStatefulWidget {
  const _ProductFormSheet({this.product});

  final SupplierProduct? product;

  @override
  ConsumerState<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<_ProductFormSheet> {
  // Exactly the fields the web supplier form collects, in the same order:
  // name, category, wholesalePrice, moq, stock, bulkDiscount, description.
  late final TextEditingController _name =
      TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _category =
      TextEditingController(text: widget.product?.category ?? '');
  late final TextEditingController _wholesalePrice =
      TextEditingController(text: widget.product == null ? '' : '${widget.product!.price}');
  late final TextEditingController _moq =
      TextEditingController(text: '${widget.product?.minimumOrderQuantity ?? 1}');
  late final TextEditingController _stock =
      TextEditingController(text: '${widget.product?.stock ?? 0}');
  late final TextEditingController _bulkDiscount =
      TextEditingController(text: '${widget.product?.bulkDiscount ?? 0}');
  late final TextEditingController _description =
      TextEditingController(text: widget.product?.description ?? '');

  bool _busy = false;

  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _shortDescription =
      TextEditingController(text: widget.product?.shortDescription ?? '');
  late final TextEditingController _category = TextEditingController(text: widget.product?.category ?? '');
  late final TextEditingController _unit = TextEditingController(text: widget.product?.unit ?? 'piece');
  late final TextEditingController _wholesalePrice =
      TextEditingController(text: widget.product?.wholesalePrice?.toString() ?? '');
  late final TextEditingController _retailPrice =
      TextEditingController(text: widget.product?.retailPrice?.toString() ?? '');
  late final TextEditingController _moq = TextEditingController(text: '${widget.product?.moq ?? 1}');
  late final TextEditingController _stock = TextEditingController(text: '${widget.product?.stockQuantity ?? 0}');
  late final TextEditingController _bulkDiscount =
      TextEditingController(text: '${widget.product?.bulkDiscount ?? 0}');
  late final TextEditingController _mainImage = TextEditingController(text: widget.product?.mainImage ?? '');
  late final TextEditingController _gallery =
      TextEditingController(text: widget.product?.gallery?.join('\n') ?? '');

  late String _status = _statuses.contains(widget.product?.status?.toUpperCase())
      ? widget.product!.status!.toUpperCase()
      : 'ACTIVE';
  bool _busy = false;

  /// The backend forces `OUT_OF_STOCK` whenever `stockQuantity <= 0`, so it is
  /// not a choice a supplier can make here — only ACTIVE and ARCHIVED are.
  static const _statuses = ['ACTIVE', 'ARCHIVED'];

  @override
  void dispose() {
    for (final c in [
      _name,
      _category,
      _wholesalePrice,
      _moq,
      _stock,
      _bulkDiscount,
      _description,
      _shortDescription,
      _category,
      _unit,
      _wholesalePrice,
      _retailPrice,
      _moq,
      _stock,
      _bulkDiscount,
      _mainImage,
      _gallery,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Mirrors the web form's `required` set — the six value fields are
  /// mandatory and `description` is the only optional one. The numeric bounds
  /// match the backend schema (`wholesalePrice >= 0`, `moq >= 1`,
  /// `stockQuantity >= 0`, `bulkDiscount` 0–100) so a bad value is caught here
  /// instead of coming back as an opaque API error.
  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Enter a product name';
    if (_category.text.trim().isEmpty) return 'Enter a category';
    final price = num.tryParse(_wholesalePrice.text.trim());
    if (_wholesalePrice.text.trim().isEmpty) return 'Enter a wholesale price';
    if (price == null || price < 0) return 'Enter a valid wholesale price';
    final moq = int.tryParse(_moq.text.trim());
    if (moq == null || moq < 1) return 'Minimum order must be 1 or more';
    final stock = int.tryParse(_stock.text.trim());
    if (stock == null || stock < 0) return 'Enter a valid stock quantity';
    final discount = num.tryParse(_bulkDiscount.text.trim());
    if (discount == null || discount < 0 || discount > 100) {
      return 'Bulk discount must be between 0 and 100';
    }
  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Enter a product name';
    final price = num.tryParse(_wholesalePrice.text.trim());
    if (_wholesalePrice.text.trim().isEmpty) return 'Enter a wholesale price';
    if (price == null || price < 0) return 'Enter a valid wholesale price';
    final stock = int.tryParse(_stock.text.trim());
    if (stock == null || stock < 0) return 'Enter a valid stock quantity';
    final moq = int.tryParse(_moq.text.trim());
    if (moq == null || moq < 1) return 'Minimum order must be 1 or more';
    final discount = num.tryParse(_bulkDiscount.text.trim());
    if (discount == null || discount < 0 || discount > 100) return 'Bulk discount must be between 0 and 100';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      showMvSnack(context, problem);
      return;
    }
    setState(() => _busy = true);

    final isEdit = widget.product != null;
    final existing = widget.product;
    final stock = int.parse(_stock.text.trim());
    final product = SupplierProduct(
      // An empty id is what tells the workspace service to POST rather
      // than PUT, so a create keeps the sheet's product unset.
      id: existing?.id ?? '',
      name: _name.text.trim(),
      category: _category.text.trim(),
      description: _description.text.trim(),
      price: num.parse(_wholesalePrice.text.trim()).toDouble(),
      stock: stock,
      minimumOrderQuantity: int.parse(_moq.text.trim()),
      bulkDiscount: num.parse(_bulkDiscount.text.trim()).toDouble(),
      // Not collected by this form, so carry the stored values through. The
      // payload omits them, and the backend preserves them on update.
      unit: existing?.unit ?? 'piece',
      retailPrice: existing?.retailPrice,
      imageUrl: existing?.imageUrl ?? '',
      gallery: existing?.gallery ?? const <String>[],
      status: existing?.status ?? 'ACTIVE',
    );

    try {
      await ref.read(supplierWorkspaceProvider.notifier).saveProduct(product);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'shortDescription': _shortDescription.text.trim(),
      'category': _category.text.trim(),
      'unit': _unit.text.trim(),
      'wholesalePrice': num.parse(_wholesalePrice.text.trim()),
      'retailPrice': num.tryParse(_retailPrice.text.trim()) ?? 0,
      'moq': int.parse(_moq.text.trim()),
      'stockQuantity': int.parse(_stock.text.trim()),
      'bulkDiscount': num.parse(_bulkDiscount.text.trim()),
      'status': _status,
      'media': {
        'mainImage': _mainImage.text.trim(),
        'gallery': _gallery.text
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      },
    };

    final id = widget.product?.id;
    final isEdit = id != null;
    try {
      final svc = ref.read(supplierServiceProvider);
      if (isEdit) {
        await svc.updateProduct(id, body);
      } else {
        await svc.createProduct(body);
      }
      if (mounted) {
        Navigator.pop(context);
        showMvSnack(context, isEdit ? 'Product updated' : 'Product added', success: true);
      }
      ref.invalidate(supplierProductsProvider);
    } catch (e) {
      if (mounted) showMvSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isEdit ? 'Edit wholesale product' : 'Add wholesale product',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Enter the wholesale product details vendors will see when sourcing stock.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Product name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wholesalePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Wholesale price (RWF) *',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _moq,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Minimum order quantity *',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bulkDiscount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Bulk discount (%) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                helperText: 'Optional',
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: isEdit ? 'Save changes' : 'Add wholesale product',
              isEdit ? 'Edit product' : 'Add product',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Product name *')),
            const SizedBox(height: 12),
            TextField(
              controller: _shortDescription,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _category, decoration: const InputDecoration(labelText: 'Category'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unit'))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wholesalePrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Wholesale price *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _retailPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Retail price'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _moq,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min order *'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _bulkDiscount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Bulk %'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _mainImage, decoration: const InputDecoration(labelText: 'Main image URL')),
            const SizedBox(height: 12),
            TextField(
              controller: _gallery,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Gallery image links', hintText: 'One per line'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [
                for (final s in _statuses) DropdownMenuItem(value: s, child: Text(titleCase(s))),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'ACTIVE'),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: isEdit ? 'Save changes' : 'Add product',
              icon: 'check',
              expanded: true,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
