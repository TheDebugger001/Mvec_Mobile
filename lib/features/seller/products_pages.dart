import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/nav_items.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';

String _greeting() {
  final h = DateTime.now().hour;
  return h < 12
      ? 'Good morning'
      : h < 18
      ? 'Good afternoon'
      : 'Good evening';
}

/// `/vendor` — greeting, catalogue size, low stock and the latest orders.
class SellerOverviewPage extends ConsumerStatefulWidget {
  const SellerOverviewPage({super.key});

  @override
  ConsumerState<SellerOverviewPage> createState() => _SellerOverviewPageState();
}

class _SellerOverviewPageState extends ConsumerState<SellerOverviewPage> {
  late final _data = Loader(() async {
    final res = await Future.wait([vendorProducts().catchError((_) => <Map<String, dynamic>>[]), jlist('/orders/vendor/orders', 'orders').catchError((_) => <Map<String, dynamic>>[])]);
    return (products: res[0], orders: res[1].take(5).toList());
  });

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider.select((a) => a.user));
    return PortalPage(
      eyebrow: 'Seller platform',
      title: '${_greeting()}, ${user?.firstName ?? 'Seller'}',
      subtitle:
          user?.isStaff == true
              ? "You're working in ${user?.staffStoreName ?? 'the store'} as ${staffRoleLabel[user?.staffRole] ?? 'staff'}. Menus show what your role can access."
              : 'Everything you need to operate your MVEC store.',
      onRefresh: _data.reload,
      children: [
        const OnboardingBanner(),
        LoadView(
          loader: _data,
          builder: (d) {
            final low = d.products.where((p) => numOf(p['stockQuantity']) <= numOf(p['lowStockThreshold'], 5)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Products', value: '${d.products.length}', icon: 'box', sub: 'Published catalog'),
                    MetricCard(label: 'Low-stock items', value: '${low.length}', icon: 'bell', sub: 'Needs attention'),
                    MetricCard(label: 'Recent orders', value: '${d.orders.length}', icon: 'cart', sub: 'Latest activity'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'Inventory alerts',
                  subtitle: 'Reorder soon',
                  trailing: TextButton(onPressed: () => context.go('/vendor/inventory'), child: const Text('View all')),
                  children: [
                    if (low.isEmpty) const Tiny('No low-stock items right now.'),
                    for (final p in low.take(6)) RecordCard(title: strOf(p['name']), subtitle: '${p['stockQuantity']} units remaining', status: const StatusChip('Low stock', tone: StatusTone.warn)),
                  ],
                ),
                Section(
                  title: 'Recent orders',
                  subtitle: 'Latest customer activity',
                  trailing: TextButton(onPressed: () => context.go('/vendor/orders'), child: const Text('View all')),
                  children: [
                    if (d.orders.isEmpty) const Tiny('No orders yet.'),
                    for (final o in d.orders)
                      RecordCard(
                        title: strOf(o['orderNumber']),
                        subtitle: personName(o['user']),
                        amount: money(o['vendorSubtotal']),
                        status: Pill(o['orderStatus']),
                        onTap: () => context.push('/vendor/orders/${idOf(o)}'),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Products ────────────────────────────────────────────────────────────────

String productImage(Map<String, dynamic> p) => strOf(asMap(p['media'])['mainImage'] ?? p['mainImage']);

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

int? _salePrice(dynamic price, String type, dynamic value) {
  final p = numOf(price), v = numOf(value);
  if (type.isEmpty || p <= 0 || v <= 0) return null;
  final off = type == 'PERCENT' ? p * v / 100 : v;
  final r = (p - off).round();
  return r < 1 ? 1 : r;
}

String _discountError(dynamic price, String type, dynamic value) {
  if (type.isEmpty) return '';
  final p = numOf(price), v = numOf(value);
  if ('${value ?? ''}'.isEmpty || v <= 0) return 'Enter a discount greater than 0.';
  if (type == 'PERCENT' && v >= 100) return 'A percentage discount must be less than 100%.';
  if (type == 'FIXED' && p > 0 && v >= p) return 'The discount amount must be less than the selling price.';
  return '';
}

/// Add / edit a product (`ProductForm`): details, pricing with discount,
/// stock, attributes and photos.
class ProductEditorPage extends StatefulWidget {
  const ProductEditorPage({super.key, this.product});
  final Map<String, dynamic>? product;

  @override
  State<ProductEditorPage> createState() => _ProductEditorPageState();
}

class _ProductEditorPageState extends State<ProductEditorPage> {
  static const _text = [
    'name',
    'sku',
    'brand',
    'shortDescription',
    'description',
    'price',
    'discountValue',
    'costPrice',
    'stockQuantity',
    'lowStockThreshold',
    'color',
    'size',
    'material',
    'weight',
    'capacity',
    'model',
  ];
  final _c = <String, TextEditingController>{};
  String _categoryId = '';
  String _storeId = '';
  String _status = 'DRAFT';
  String _discountType = '';
  List<String> _gallery = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _stores = [];
  bool _saving = false;
  bool _uploading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final p = widget.product ?? const <String, dynamic>{};
    final attrs = asMap(p['attributes']);
    for (final k in _text) {
      final v = p[k] ?? attrs[k];
      _c[k] = TextEditingController(text: v == null ? '' : '$v'.replaceAll(RegExp(r'\.0+$'), ''));
    }
    if (widget.product == null) _c['lowStockThreshold']!.text = '5';
    _categoryId = idOf(p['category']).isNotEmpty ? idOf(p['category']) : strOf(p['categoryId']);
    _storeId = idOf(p['store']);
    _status = strOf(p['status'], 'DRAFT');
    final media = asMap(p['media']);
    _gallery = [for (final g in (media['gallery'] is List ? media['gallery'] as List : const [])) '$g'];
    final main = strOf(media['mainImage'] ?? p['mainImage']);
    if (main.isNotEmpty && !_gallery.contains(main)) _gallery.insert(0, main);
    if (strOf(p['discountType']).isNotEmpty) {
      _discountType = strOf(p['discountType']);
    } else if (numOf(p['discountPrice']) > 0 && numOf(p['discountPrice']) < numOf(p['price'])) {
      _discountType = 'FIXED';
      _c['discountValue']!.text = '${numOf(p['price']) - numOf(p['discountPrice'])}';
    }
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
    jlist('/stores/mine', 'stores').then((v) => mounted ? setState(() => _stores = v) : null).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();

  Future<void> _addImages() async {
    setState(() {
      _uploading = true;
      _error = '';
    });
    try {
      final urls = await pickAndUploadImages();
      if (mounted) setState(() => _gallery = [..._gallery, ...urls]);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        toast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _newCategory() async {
    final created = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'New category',
      subtitle: "It's added to the marketplace and selected for this product.",
      fields: [
        const FieldSpec('name', 'Category name', required: true, hint: 'e.g. Smartphones'),
        FieldSpec('parentId', 'Parent category', type: FieldType.select, placeholderOption: 'None (top-level category)', options: [for (final r in buildCategoryTree(_categories)) (r.id, r.name)]),
      ],
      initial: {'name': '', 'parentId': ''},
      submitLabel: 'Create & select',
      onSubmit: (v) => jpost('/categories', {'name': v['name'], 'parentId': '${v['parentId']}'.isEmpty ? null : v['parentId']}),
    );
    if (created == null || !mounted) return;
    final cat = {'parentId': null, ...asMap(created['category'])};
    cat['id'] = idOf(cat);
    setState(() {
      if (!_categories.any((c) => idOf(c) == cat['id'])) _categories = [..._categories, cat];
      _categoryId = '${cat['id']}';
    });
    toast(context, created['alreadyExisted'] == true ? strOf(created['message'], 'Category selected.') : 'Category “${cat['name']}” created and selected.');
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_t('name').isEmpty || _categoryId.isEmpty || _t('price').isEmpty || _t('stockQuantity').isEmpty || _gallery.isEmpty) {
      setState(() => _error = 'Please complete the required fields and add at least one image.');
      return;
    }
    if (_t('description').isEmpty) {
      setState(() => _error = 'Add a description.');
      return;
    }
    final problem = _discountError(_t('price'), _discountType, _t('discountValue'));
    if (problem.isNotEmpty) {
      setState(() => _error = problem);
      return;
    }
    final form = <String, dynamic>{
      for (final k in ['name', 'sku', 'brand', 'shortDescription', 'description', 'color', 'size', 'material', 'weight', 'capacity', 'model']) k: _t(k),
      'categoryId': _categoryId,
      'storeId': _storeId,
      'price': num.parse(_t('price')),
      'discountType': _discountType.isEmpty ? null : _discountType,
      'discountValue': _discountType.isEmpty ? null : num.parse(_t('discountValue')),
      if (_discountType.isEmpty) 'discountPrice': null,
      'costPrice': _t('costPrice').isEmpty ? null : num.parse(_t('costPrice')),
      'stockQuantity': num.parse(_t('stockQuantity')).toInt(),
      'lowStockThreshold': int.tryParse(_t('lowStockThreshold')) ?? 5,
      'status': _status,
      'mainImage': _gallery.first,
      'gallery': _gallery,
    };
    setState(() => _saving = true);
    try {
      final id = idOf(widget.product);
      if (widget.product == null) {
        await jpost('/products', productPayload(form));
      } else {
        if (id.isEmpty) throw ApiException('This product no longer exists. Refresh the page.');
        await jput('/products/$id', productPayload(form));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        toast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String k, String label, {bool number = false, String? hint, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _c[k],
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : (lines > 1 ? TextInputType.multiline : TextInputType.text),
      minLines: lines > 1 ? 3 : 1,
      maxLines: lines > 1 ? lines : 1,
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => k == 'price' || k == 'discountValue' ? setState(() {}) : null,
    ),
  );

  Widget _heading(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 10), child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.mv.text)));

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final editing = widget.product != null;
    final sale = _salePrice(_t('price'), _discountType, _t('discountValue'));
    final dErr = _discountError(_t('price'), _discountType, _t('discountValue'));
    final catOptions = categoryOptions(_categories);
    final primary = idOf(_stores.where((s) => s['isPrimary'] == true).firstOrNull);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        title: Text(editing ? 'Edit product' : 'Add product'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Tiny('Complete product information before publishing it to the MVEC marketplace.'),
            if (_error.isNotEmpty) Notice(text: _error),
            _heading('Basic information'),
            _field('name', 'Product name *', hint: 'e.g. Samsung Galaxy S25'),
            _field('sku', 'SKU', hint: 'Auto-generated if left blank'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: catOptions.any((o) => o.$1 == _categoryId) ? _categoryId : '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category *'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Select category')),
                  for (final (v, l) in catOptions) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem(value: '__new__', child: Text('+ Create new category…')),
                ],
                onChanged: (v) {
                  if (v == '__new__') {
                    setState(() {});
                    _newCategory();
                  } else {
                    setState(() => _categoryId = v ?? '');
                  }
                },
              ),
            ),
            _field('brand', 'Brand', hint: 'Brand name'),
            if (_stores.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilterSelect(
                  label: 'Store',
                  value: _storeId.isEmpty ? primary : _storeId,
                  options: [for (final s in _stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' (primary)' : ''}')],
                  onChanged: (v) => setState(() => _storeId = v),
                ),
              ),
            _field('shortDescription', 'Short description', hint: 'A short summary shown on product cards'),
            _field('description', 'Description *', lines: 6, hint: 'Describe the product, benefits and important information'),
            _heading('Pricing & inventory'),
            _field('price', 'Selling price (RWF) *', number: true),
            Row(
              children: [
                Expanded(
                  child: FilterSelect(
                    label: 'Discount',
                    value: _discountType,
                    options: const [('', 'No discount'), ('PERCENT', 'Percent %'), ('FIXED', 'Amount RWF')],
                    onChanged:
                        (v) => setState(() {
                          _discountType = v;
                          if (v.isEmpty) _c['discountValue']!.clear();
                        }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _c['discountValue'],
                    enabled: _discountType.isNotEmpty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Value',
                      hintText:
                          _discountType == 'PERCENT'
                              ? 'e.g. 15'
                              : _discountType == 'FIXED'
                              ? 'e.g. 5000'
                              : '—',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_discountType.isNotEmpty && _t('discountValue').isNotEmpty)
              Tiny(
                dErr.isNotEmpty
                    ? dErr
                    : sale != null
                    ? 'Sale price ${money(sale)} · buyers save ${money(numOf(_t('price')) - sale)}'
                    : '',
                color: dErr.isNotEmpty ? MvColors.errorText : null,
              ),
            const SizedBox(height: 12),
            _field('costPrice', 'Cost price', number: true),
            Row(
              children: [
                Expanded(child: _field('stockQuantity', 'Stock quantity *', number: true)),
                const SizedBox(width: 10),
                Expanded(child: _field('lowStockThreshold', 'Low stock threshold', number: true)),
              ],
            ),
            FilterSelect(label: 'Status', value: _status, options: const [('DRAFT', 'Draft'), ('ACTIVE', 'Active'), ('INACTIVE', 'Inactive')], onChanged: (v) => setState(() => _status = v)),
            const SizedBox(height: 8),
            _heading('Product attributes'),
            for (final (k, l) in const [('color', 'Color'), ('size', 'Size'), ('material', 'Material'), ('weight', 'Weight'), ('capacity', 'Capacity'), ('model', 'Model')]) _field(k, l),
            _heading('Media'),
            Tiny('Upload product images. The first image becomes the main product image.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _gallery.length; i++)
                  Stack(
                    children: [
                      ProductImage(src: _gallery[i], size: 86, radius: 10),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: () => setState(() => _gallery = [..._gallery]..removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                      if (i == 0)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(color: MvColors.primaryDark, borderRadius: BorderRadius.circular(5)),
                            child: const Text('Main', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                InkWell(
                  onTap: _uploading ? null : _addImages,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: mv.border, width: 1.5), color: mv.soft),
                    child:
                        _uploading
                            ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                            : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [Icon(Icons.add_photo_alternate_outlined, color: mv.accentDeep), Text('Add photos', style: TextStyle(fontSize: 11, color: mv.accentDeep))],
                            ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Tiny('PNG, JPG or WEBP, several at once (max 8 MB each).'),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: GradientButton(label: editing ? 'Save changes' : 'Create product', loading: _saving, onPressed: _uploading ? null : _save),
        ),
      ),
    );
  }
}

// ─── Bulk upload (CSV) ───────────────────────────────────────────────────────

const _bulkColumns = ['name', 'description', 'price', 'discountPrice', 'stockQuantity', 'category', 'brand', 'mainImage', 'status'];
const bulkTemplate =
    'name,description,price,discountPrice,stockQuantity,category,brand,mainImage,status\n'
    '"Wireless earbuds","Bluetooth 5.3 earbuds with charging case",25000,22000,40,Electronics,SoundMax,https://example.com/earbuds.jpg,DRAFT\n';

/// Minimal CSV reader: commas, quoted fields with "" escapes, CRLF or LF.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// Upload up to 200 products from a spreadsheet saved as CSV (`BulkUpload`).
class BulkUploadSheet extends StatefulWidget {
  const BulkUploadSheet({super.key});

  @override
  State<BulkUploadSheet> createState() => _BulkUploadSheetState();
}

class _BulkUploadSheetState extends State<BulkUploadSheet> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _rows = [];
  List<String> _problems = [];
  Map<String, dynamic>? _result;
  String _error = '';
  String _file = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
  }

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'], mimeTypes: ['text/csv', 'text/comma-separated-values'], uniformTypeIdentifiers: ['public.comma-separated-values-text']),
      ],
    );
    if (file == null) return;
    setState(() {
      _error = '';
      _result = null;
      _rows = [];
      _problems = [];
      _file = file.name;
    });
    final table = parseCsv(utf8.decode(await file.readAsBytes(), allowMalformed: true).replaceFirst('﻿', ''));
    if (table.length < 2) {
      setState(() => _error = "The file has no product rows. Use the template's first row as the header.");
      return;
    }
    final header = table.first.map((h) => h.trim()).toList();
    final missing = ['name', 'description', 'price', 'category', 'mainImage'].where((c) => !header.contains(c)).toList();
    if (missing.isNotEmpty) {
      setState(() => _error = 'The header is missing: ${missing.join(', ')}. The columns are: ${_bulkColumns.join(', ')}.');
      return;
    }
    final byName = {for (final c in _categories) strOf(c['name']).trim().toLowerCase(): idOf(c)};
    final found = <Map<String, dynamic>>[];
    final issues = <String>[];
    for (var i = 1; i < table.length; i++) {
      final cells = table[i];
      final r = {for (var j = 0; j < header.length; j++) header[j]: j < cells.length ? cells[j].trim() : ''};
      final categoryId = byName['${r['category']}'.toLowerCase()];
      final rowIssues = <String>[
        if ((r['name'] ?? '').isEmpty) 'name',
        if ((r['description'] ?? '').isEmpty) 'description',
        if (!(numOf(r['price']) > 0)) 'price',
        if (categoryId == null) 'category "${r['category']}" not found',
        if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(r['mainImage'] ?? '')) 'mainImage must be an image link (https://…)',
      ];
      if (rowIssues.isNotEmpty) {
        issues.add('Row ${i + 1}: ${rowIssues.join(', ')}');
        continue;
      }
      found.add({
        'name': r['name'],
        'description': r['description'],
        'price': numOf(r['price']),
        if (numOf(r['discountPrice']) > 0) 'discountPrice': numOf(r['discountPrice']),
        'stockQuantity': numOf(r['stockQuantity']).floor().clamp(0, 1 << 31),
        'category': categoryId,
        if ((r['brand'] ?? '').isNotEmpty) 'brand': r['brand'],
        'mainImage': r['mainImage'],
        'status': '${r['status']}'.toUpperCase() == 'ACTIVE' ? 'ACTIVE' : 'DRAFT',
      });
    }
    if (found.length > 200) {
      setState(() => _error = 'Upload up to 200 products at a time. Split the file and try again.');
      return;
    }
    setState(() {
      _rows = found;
      _problems = issues;
    });
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final res = await jpost('/products/bulk', {'products': _rows});
      setState(() => _result = res);
    } catch (e) {
      final data = e is ApiException ? e.data : null;
      setState(() {
        if (data is Map && data['results'] != null) _result = asMap(data);
        _error = errorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = numOf(_result?['created']) > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload products', style: context.mvH1.copyWith(fontSize: 18)),
            const Tiny('Fill in the template in Excel or Google Sheets, save it as CSV, then choose it here. Products are added as drafts unless the status column says ACTIVE. Up to 200 at a time.'),
            const SizedBox(height: 8),
            OutlineBtn(label: 'Copy template', icon: Icons.copy_rounded, compact: true, onPressed: () => copyText(context, bulkTemplate, 'Template copied. Paste it into a spreadsheet.')),
            const SizedBox(height: 8),
            OutlineBtn(label: _file.isEmpty ? 'Choose CSV file' : 'Change file ($_file)', icon: Icons.upload_file_rounded, compact: true, onPressed: _busy ? null : _pick),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) Notice(text: _error),
            if (_problems.isNotEmpty)
              Notice(
                text: '${_problems.length} row${_problems.length == 1 ? '' : 's'} will be skipped:',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final p in _problems.take(8)) Tiny(p), if (_problems.length > 8) Tiny('…and ${_problems.length - 8} more.')],
                ),
              ),
            if (_rows.isNotEmpty && _result == null) Tiny('${_rows.length} product${_rows.length == 1 ? '' : 's'} ready to upload.'),
            if (_result != null)
              Notice(
                ok: created,
                text: strOf(_result!['message'], created ? 'Products uploaded.' : 'Nothing was uploaded.'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final r in asMaps(_result!['results']).where((r) => r['ok'] != true).take(8)) Tiny('${strOf(r['name'], 'Product ${r['row']}')}: ${r['message']}')],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: OutlineBtn(label: _result != null ? 'Close' : 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop(created))),
                if (_result == null) ...[
                  const SizedBox(width: 10),
                  Expanded(child: GradientButton(label: 'Upload ${_rows.isEmpty ? '' : _rows.length}', loading: _busy, onPressed: _rows.isEmpty ? null : _upload)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inventory ───────────────────────────────────────────────────────────────

int _threshold(Map<String, dynamic> p) => numOf(p['lowStockThreshold'], 5).toInt();
String stockState(Map<String, dynamic> p) =>
    numOf(p['stockQuantity']) <= 0
        ? 'out'
        : numOf(p['stockQuantity']) <= _threshold(p)
        ? 'low'
        : 'ok';
const _stateLabel = {'ok': 'In stock', 'low': 'Low stock', 'out': 'Out of stock'};
const _stateTone = {'ok': StatusTone.good, 'low': StatusTone.warn, 'out': StatusTone.bad};
const _modes = [('add', 'Add stock (restock)'), ('remove', 'Remove stock'), ('set', 'Set exact count')];
const _defaultReasons = {
  'add': ['Restock', 'Received from supplier', 'Customer return', 'Other'],
  'remove': ['Damaged', 'Lost or stolen', 'Expired', 'Sold offline', 'Other'],
  'set': ['Stock count correction', 'Other'],
};
const _movementLabel = {'RESTOCK': 'Restock', 'REMOVE': 'Removed', 'COUNT': 'Count', 'TRANSFER': 'Moved'};

/// `/vendor/inventory` — stock per product and store, adjust, move between
/// stores, and the history of manual stock operations.
class SellerInventoryPage extends StatefulWidget {
  const SellerInventoryPage({super.key});

  @override
  State<SellerInventoryPage> createState() => _SellerInventoryPageState();
}

class _SellerInventoryPageState extends State<SellerInventoryPage> {
  late final _data = Loader(() async {
    final res = await Future.wait<dynamic>([
      vendorProducts(),
      jlist('/stores/mine', 'stores').catchError((_) => <Map<String, dynamic>>[]),
      jget('/products/vendor/stock-movements', {'limit': 200}).catchError((_) => <String, dynamic>{}),
    ]);
    final history = res[2] as Map<String, dynamic>;
    return (products: res[0] as List<Map<String, dynamic>>, stores: res[1] as List<Map<String, dynamic>>, movements: asMaps(history['movements']), reasons: asMap(history['reasons']));
  });
  String _storeTab = '';
  String _q = '';
  String _state = '';
  String _view = 'products';
  String _activityQ = '';
  String _activityType = '';
  final _selected = <String>{};

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  List<String> _reasonsFor(Map<String, dynamic> reasons, String mode) {
    final key = {'add': 'RESTOCK', 'remove': 'REMOVE', 'set': 'COUNT'}[mode]!;
    final list = reasons[key];
    return list is List && list.isNotEmpty ? [for (final r in list) '$r'] : _defaultReasons[mode]!;
  }

  Future<void> _adjust(Map<String, dynamic> p, Map<String, dynamic> reasons) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Adjust stock · ${p['name']}',
      subtitle: 'Currently ${p['stockQuantity']} units on hand.',
      fields: const [],
      fieldsFor:
          (v) => [
            const FieldSpec('mode', 'Operation', type: FieldType.select, options: _modes),
            FieldSpec('quantity', v['mode'] == 'set' ? 'New stock count' : 'Units', type: FieldType.number, required: true),
            FieldSpec('reason', 'Reason', type: FieldType.select, options: [for (final r in _reasonsFor(reasons, '${v['mode']}')) (r, r)]),
            const FieldSpec('note', 'Note', hint: 'Optional, e.g. supplier invoice number'),
          ],
      initial: {'mode': 'add', 'quantity': '', 'reason': _reasonsFor(reasons, 'add').first, 'note': ''},
      onFieldChange: (name, value, _) => name == 'mode' ? {'reason': _reasonsFor(reasons, '$value').first} : null,
      submitLabel: 'Update stock',
      onSubmit: (v) => jpatch('/products/${p['id']}/stock', {'mode': v['mode'], 'quantity': numOf(v['quantity']), 'reason': v['reason'], 'note': v['note']}),
    );
    if (res == null || !mounted) return;
    final m = asMap(res['movement']);
    toast(context, '${asMap(res['product'])['name'] ?? p['name']}: ${m['before']} → ${m['after']} units.');
    _data.reload();
  }

  Future<void> _move(List<String> ids, List<Map<String, dynamic>> stores) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Move ${ids.length} product${ids.length == 1 ? '' : 's'} to another store',
      subtitle: 'Products keep their stock and price; only the store they are listed under changes.',
      fields: [
        FieldSpec(
          'storeId',
          'Destination store',
          type: FieldType.select,
          required: true,
          placeholderOption: 'Select a store',
          options: [for (final s in stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' (primary)' : ''}')],
        ),
        const FieldSpec('note', 'Note', hint: 'Optional'),
      ],
      initial: {'storeId': '', 'note': ''},
      submitLabel: 'Move products',
      onSubmit: (v) => jpost('/products/vendor/move-store', {'productIds': ids, 'storeId': v['storeId'], 'note': v['note']}),
    );
    if (res == null || !mounted) return;
    toast(context, strOf(res['message'], 'Products moved.'));
    setState(_selected.clear);
    _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final multi = d.stores.length > 1;
        final primary = idOf(d.stores.where((s) => s['isPrimary'] == true).firstOrNull);
        String storeOf(Map<String, dynamic> p) => idOf(p['store']).isNotEmpty ? idOf(p['store']) : primary;
        String storeName(String id) => strOf(d.stores.where((s) => idOf(s) == id).map((s) => s['storeName']).firstOrNull, '—');
        final inScope = d.products.where((p) => _storeTab.isEmpty || storeOf(p) == _storeTab).toList();
        final filtered = inScope.where((p) => matches(_q, [p['name'], p['sku'], p['brand'], asMap(p['category'])['name']]) && (_state.isEmpty || stockState(p) == _state)).toList();
        final units = inScope.fold<num>(0, (s, p) => s + numOf(p['stockQuantity']));
        final value = inScope.fold<num>(0, (s, p) => s + numOf(p['stockQuantity']) * numOf(p['costPrice'] ?? p['discountPrice'] ?? p['price']));
        final storeMoves = d.movements.where((m) => _storeTab.isEmpty || idOf(m['store']) == _storeTab || idOf(m['fromStore']) == _storeTab).toList();
        final moves =
            storeMoves
                .where(
                  (m) =>
                      (_activityType.isEmpty || m['type'] == _activityType) &&
                      matches(_activityQ, [m['productName'], m['reason'], m['note'], asMap(m['performedBy'])['Fullname'], asMap(m['fromStore'])['storeName'], asMap(m['toStore'])['storeName']]),
                )
                .toList();
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Inventory',
          subtitle: multi ? 'Stock levels per store, with restock, removal, stock counts and transfers between stores.' : 'Stock levels with restock, removal and stock-count operations.',
          onRefresh: _data.reload,
          action: OutlineBtn(label: 'New product', icon: Icons.add_rounded, compact: true, onPressed: () => context.go('/vendor/products?add=1')),
          children: [
            if (multi)
              TabChips(
                tabs: [('', 'All stores'), for (final s in d.stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' ★' : ''}')],
                value: _storeTab,
                counts: {'': d.products.length, for (final s in d.stores) idOf(s): d.products.where((p) => storeOf(p) == idOf(s)).length},
                onChanged: (v) => setState(() => _storeTab = v),
              ),
            MetricGrid(
              children: [
                MetricCard(label: 'Units on hand', value: compact(units), icon: 'box', sub: '${inScope.length} products'),
                MetricCard(label: 'Stock value', value: money(value), icon: 'wallet', sub: 'At cost (or selling price)'),
                MetricCard(label: 'Low stock', value: '${inScope.where((p) => stockState(p) == 'low').length}', icon: 'bell', sub: 'At or below threshold'),
                MetricCard(label: 'Out of stock', value: '${inScope.where((p) => stockState(p) == 'out').length}', icon: 'cart', sub: 'Hidden from buyers'),
              ],
            ),
            const SizedBox(height: 14),
            TabChips(
              tabs: const [('products', 'Products'), ('activity', 'Recent stock activity')],
              value: _view,
              counts: {'products': inScope.length, 'activity': storeMoves.length},
              onChanged: (v) => setState(() => _view = v),
            ),
            if (_view == 'products') ...[
              SearchBox(hint: 'Search name, SKU, brand or category', onChanged: (v) => setState(() => _q = v)),
              FilterSelect(
                value: _state,
                label: 'Stock level',
                options: const [('', 'All stock levels'), ('low', 'Low stock'), ('out', 'Out of stock'), ('ok', 'In stock')],
                onChanged: (v) => setState(() => _state = v),
              ),
              const SizedBox(height: 12),
              if (_selected.isNotEmpty && multi)
                Notice(
                  info: true,
                  text: '${_selected.length} selected',
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ActionChipBtn('Move to store…', primary: true, onPressed: () => _move(_selected.toList(), d.stores)),
                      ActionChipBtn('Clear', onPressed: () => setState(_selected.clear)),
                    ],
                  ),
                ),
              Paged<Map<String, dynamic>>(
                items: filtered,
                empty:
                    d.products.isEmpty
                        ? EmptyState(
                          title: 'No products yet',
                          message: 'Add products to start tracking stock.',
                          action: GradientButton(label: 'Add product', compact: true, onPressed: () => context.go('/vendor/products?add=1')),
                        )
                        : const EmptyState(title: 'No products match these filters'),
                itemBuilder: (p) {
                  final st = stockState(p);
                  final pct = (numOf(p['stockQuantity']) / ((_threshold(p) * 3).clamp(1, 1 << 30))).clamp(0.0, 1.0).toDouble();
                  return RecordCard(
                    selected: _selected.contains(p['id']),
                    leading:
                        multi
                            ? Checkbox(value: _selected.contains(p['id']), onChanged: (on) => setState(() => on == true ? _selected.add('${p['id']}') : _selected.remove(p['id'])))
                            : ProductImage(src: productImage(p), size: 46, radius: 8),
                    title: strOf(p['name']),
                    subtitle: [strOf(p['sku']), strOf(asMap(p['category'])['name']), if (multi) storeName(storeOf(p))].where((x) => x.isNotEmpty).join(' · '),
                    lines: ['${p['stockQuantity']} on hand · min ${_threshold(p)}'],
                    status: StatusChip(_stateLabel[st]!, tone: _stateTone[st]!),
                    actions: [
                      SizedBox(
                        width: 120,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            color:
                                st == 'ok'
                                    ? MvColors.successText
                                    : st == 'low'
                                    ? MvColors.warningText
                                    : MvColors.errorText,
                            backgroundColor: mv.soft,
                          ),
                        ),
                      ),
                      ActionChipBtn('Adjust', onPressed: () => _adjust(p, d.reasons)),
                      if (multi) ActionChipBtn('Move', icon: Icons.storefront_outlined, onPressed: () => _move(['${p['id']}'], d.stores)),
                    ],
                  );
                },
              ),
            ],
            if (_view == 'activity') ...[
              SearchBox(hint: 'Search product, reason, note or person', onChanged: (v) => setState(() => _activityQ = v)),
              FilterSelect(
                value: _activityType,
                label: 'Operation',
                options: [('', 'All operations'), for (final e in _movementLabel.entries) (e.key, e.value)],
                onChanged: (v) => setState(() => _activityType = v),
              ),
              const SizedBox(height: 12),
              Tiny('Manual operations${_storeTab.isNotEmpty ? ' in ${storeName(_storeTab)}' : ''}; order sales are not listed.'),
              if (storeMoves.isEmpty) const Tiny('No stock operations yet. Use Adjust on a product to restock, remove or count stock.'),
              if (storeMoves.isNotEmpty && moves.isEmpty) const Tiny('No activity matches these filters.'),
              Paged<Map<String, dynamic>>(
                items: moves,
                itemBuilder: (m) {
                  final q = numOf(m['quantity']);
                  final transfer = m['type'] == 'TRANSFER';
                  return RecordCard(
                    title: strOf(m['productName'], 'Product'),
                    subtitle:
                        '${_movementLabel[m['type']] ?? m['type']} · ${transfer ? '${asMap(m['fromStore'])['storeName'] ?? '—'} → ${asMap(m['toStore'])['storeName'] ?? '—'}' : strOf(m['reason'])}',
                    lines: ['${strOf(m['note']).isEmpty ? '' : '${m['note']} · '}${personName(m['performedBy'], 'Seller')} · ${formatDateTime(m['createdAt'])}'],
                    amount: transfer ? '${m['after']} units' : '${q > 0 ? '+' : ''}$q',
                    status: transfer ? null : Text('${m['before']} → ${m['after']}', style: TextStyle(fontSize: 11.5, color: mv.textMuted)),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
