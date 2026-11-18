import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';

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
    // A product waiting for approval (or sold out) is meant to be live; the server keeps it waiting.
    final status = strOf(p['status'], 'DRAFT');
    _status = const ['PENDING_APPROVAL', 'OUT_OF_STOCK'].contains(status) ? 'ACTIVE' : status;
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
      final Object? saved;
      if (widget.product == null) {
        saved = await jpost('/products', productPayload(form));
      } else {
        if (id.isEmpty) throw ApiException('This product no longer exists. Refresh the page.');
        saved = await jput('/products/$id', productPayload(form));
      }
      if (!mounted) return;
      // Before Ikiguzi approves the store, buyers don't see it yet: say so.
      final res = asMap(saved);
      if (res['waitingForApproval'] == true) toast(context, strOf(res['message'], 'Product saved. Buyers will see it once Ikiguzi approves your store.'));
      Navigator.of(context).pop(true);
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
            Tiny('Complete product information before publishing it to the Ikiguzi marketplace.'),
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
