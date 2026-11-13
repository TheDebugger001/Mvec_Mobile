import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';
import 'bulk_upload_sheet.dart';
import 'product_editor_page.dart';
import 'products_shared.dart';

/// `/vendor/products` — the catalogue: search, filters, edit, archive, delete.
class SellerProductsPage extends StatefulWidget {
  const SellerProductsPage({super.key, this.addNew = false, this.category});
  final bool addNew;
  final String? category;

  @override
  State<SellerProductsPage> createState() => _SellerProductsPageState();
}

class _SellerProductsPageState extends State<SellerProductsPage> {
  late final _data = Loader(() async {
    final res = await Future.wait([
      vendorProducts(),
      jlist('/stores/mine', 'stores').catchError((_) => <Map<String, dynamic>>[]),
      jlist('/categories', 'categories').catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (products: res[0], stores: res[1], categories: res[2]);
  });
  String _q = '';
  String _status = '';
  String _store = '';
  late String _category = widget.category ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.addNew) WidgetsBinding.instance.addPostFrameCallback((_) => _edit(null));
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? p) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ProductEditorPage(product: p)));
    if (saved == true) {
      if (mounted) toast(context, p == null ? 'Product created.' : 'Product saved.');
      _data.reload();
    }
  }

  Future<void> _toggleArchive(Map<String, dynamic> p) async {
    final ok = await runAction(
      context,
      () => jput('/products/${p['id']}', {'status': p['status'] == 'INACTIVE' ? 'ACTIVE' : 'INACTIVE'}),
      success: p['status'] == 'INACTIVE' ? 'Product restored.' : 'Product archived.',
    );
    if (ok) _data.reload();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    if (!await confirmDialog(context, 'Delete ${p['name']}?', confirm: 'Delete', danger: true)) return;
    if (!mounted) return;
    final ok = await runAction(context, () => jdelete('/products/${p['id']}'), success: 'Product deleted.');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Products',
      subtitle: 'Manage product details, pricing, stock, media and publishing status.',
      onRefresh: _data.reload,
      action: Row(
        children: [
          Expanded(child: GradientButton(label: 'Add product', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null))),
          const SizedBox(width: 10),
          Expanded(
            child: OutlineBtn(
              label: 'Upload sheet',
              icon: Icons.upload_file_rounded,
              compact: true,
              onPressed: () async {
                final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => const BulkUploadSheet());
                if (done == true) _data.reload();
              },
            ),
          ),
        ],
      ),
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final primary = idOf(d.stores.where((s) => s['isPrimary'] == true).firstOrNull);
            String storeOf(Map<String, dynamic> p) => idOf(p['store']).isNotEmpty ? idOf(p['store']) : primary;
            final catIds = _category.isEmpty ? null : {_category, ...d.categories.where((c) => idOf(c['parentId']) == _category).map(idOf)};
            final shown =
                d.products.where((p) {
                  final cat = asMap(p['category']);
                  return matches(_q, [p['name'], p['sku'], p['brand'], cat['name']]) &&
                      (_status.isEmpty || p['status'] == _status) &&
                      (_store.isEmpty || storeOf(p) == _store) &&
                      (catIds == null || catIds.contains(idOf(cat)));
                }).toList();
            final statuses = d.products.map((p) => strOf(p['status'])).where((s) => s.isNotEmpty).toSet();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SearchBox(hint: 'Search products, SKU, brand or category', onChanged: (v) => setState(() => _q = v)),
                FilterRow(
                  children: [
                    FilterSelect(value: _status, label: 'Status', options: [('', 'All statuses'), for (final s in statuses) (s, titleCase(s))], onChanged: (v) => setState(() => _status = v)),
                    FilterSelect(value: _category, label: 'Category', options: [('', 'All categories'), ...categoryOptions(d.categories)], onChanged: (v) => setState(() => _category = v)),
                    if (d.stores.length > 1)
                      FilterSelect(
                        value: _store,
                        label: 'Store',
                        options: [('', 'All stores'), for (final s in d.stores) (idOf(s), strOf(s['storeName']))],
                        onChanged: (v) => setState(() => _store = v),
                      ),
                  ],
                ),
                Tiny('${shown.length} products'),
                Paged<Map<String, dynamic>>(
                  items: shown,
                  perPage: 8,
                  empty:
                      d.products.isEmpty
                          ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'No products yet', message: 'Add your first product to start selling.')
                          : const EmptyState(title: 'No products match these filters'),
                  itemBuilder: (p) {
                    final discounted = numOf(p['discountPrice']) > 0 && numOf(p['discountPrice']) < numOf(p['price']);
                    final cat = asMap(p['category']);
                    final storeName = d.stores.length > 1 ? strOf(d.stores.where((s) => idOf(s) == storeOf(p)).map((s) => s['storeName']).firstOrNull) : '';
                    return RecordCard(
                      leading: ProductImage(src: productImage(p), size: 54, radius: 8),
                      title: strOf(p['name']),
                      subtitle: [strOf(p['sku']), strOf(p['brand'], 'No brand'), strOf(cat['name']), storeName].where((x) => x.isNotEmpty).join(' · '),
                      lines: [
                        discounted
                            ? '${money(p['discountPrice'])} (was ${money(p['price'])}, ${p['discountType'] == 'PERCENT' ? '-${p['discountValue']}%' : '-${money(numOf(p['price']) - numOf(p['discountPrice']))}'})'
                            : money(p['price']),
                        'Stock: ${p['stockQuantity']}',
                      ],
                      status: Pill(p['status']),
                      actions: [
                        ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(p)),
                        ActionChipBtn(
                          p['status'] == 'INACTIVE' ? 'Restore' : 'Archive',
                          icon: p['status'] == 'INACTIVE' ? Icons.check_rounded : Icons.archive_outlined,
                          onPressed: () => _toggleArchive(p),
                        ),
                        ActionChipBtn('Delete', icon: Icons.delete_outline_rounded, danger: true, onPressed: () => _delete(p)),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
