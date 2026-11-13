import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'products_shared.dart';

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
