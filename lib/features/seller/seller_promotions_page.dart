import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _promoTypes = [('PERCENT', 'Percentage off'), ('FIXED', 'Fixed amount off'), ('FREE_SHIPPING', 'Free shipping')];

const _promoStatuses = [('DRAFT', 'Draft'), ('SCHEDULED', 'Scheduled'), ('ACTIVE', 'Active'), ('PAUSED', 'Paused')];

const _liveLabel = {'ACTIVE': 'Live', 'SCHEDULED': 'Scheduled', 'EXPIRED': 'Expired', 'USED_UP': 'Used up', 'PAUSED': 'Paused', 'DRAFT': 'Draft', 'CANCELLED': 'Cancelled'};

const _promoTabs = [('ALL', 'All'), ('ACTIVE', 'Live'), ('SCHEDULED', 'Scheduled'), ('DRAFT', 'Drafts'), ('PAUSED', 'Paused'), ('ENDED', 'Ended')];

bool _inPromoTab(Map<String, dynamic> r, String tab) => tab == 'ALL' || (tab == 'ENDED' ? ['EXPIRED', 'USED_UP', 'CANCELLED'].contains(r['liveStatus']) : r['liveStatus'] == tab);

const _promoFields = [
  FieldSpec('name', 'Promotion name', required: true, hint: 'e.g. Back to School'),
  FieldSpec('code', 'Coupon code', required: true, hint: 'SCHOOL15'),
  FieldSpec('type', 'Discount type', type: FieldType.select, options: _promoTypes),
  FieldSpec('value', 'Discount value', type: FieldType.number, help: 'Percent (1–100) or RWF amount. Ignored for free shipping.'),
  FieldSpec('minOrderAmount', 'Minimum spend on your items (RWF)', type: FieldType.number),
  FieldSpec('startsAt', 'Starts', type: FieldType.date),
  FieldSpec('endsAt', 'Ends', type: FieldType.date),
  FieldSpec('usageLimit', 'Usage limit', type: FieldType.number, hint: 'Unlimited'),
  FieldSpec('status', 'Status', type: FieldType.select, options: _promoStatuses),
];

Map<String, dynamic> _promoPayload(Map<String, dynamic> f) => {
  'name': f['name'],
  'code': f['code'],
  'type': f['type'],
  'value': f['type'] == 'FREE_SHIPPING' ? 0 : numOf(f['value']),
  'minOrderAmount': numOf(f['minOrderAmount']),
  'usageLimit': '${f['usageLimit'] ?? ''}'.isEmpty ? null : numOf(f['usageLimit']),
  'startsAt': '${f['startsAt'] ?? ''}'.isEmpty ? null : f['startsAt'],
  'endsAt': '${f['endsAt'] ?? ''}'.isEmpty ? null : f['endsAt'],
  'status': f['status'],
};

String _inputDate(dynamic v) {
  final d = parseDate(v);
  return d == null ? '' : d.toIso8601String().substring(0, 10);
}

/// `/vendor/promotions` — coupon codes for the seller's items.
class SellerPromotionsPage extends StatefulWidget {
  const SellerPromotionsPage({super.key});

  @override
  State<SellerPromotionsPage> createState() => _SellerPromotionsPageState();
}

class _SellerPromotionsPageState extends State<SellerPromotionsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jlist('/promotions', 'data'),
      jlist('/stores/mine', 'stores').catchError((_) => <Map<String, dynamic>>[]),
      vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (promos: r[0], stores: r[1], products: r[2]);
  });
  String _tab = 'ALL';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? p, List<Map<String, dynamic>> stores, List<Map<String, dynamic>> products) async {
    final isNew = p == null;
    final res = await showFormSheet<bool>(
      context,
      title: isNew ? 'New promotion' : 'Edit promotion',
      fields: [
        if (isNew && stores.length > 1)
          FieldSpec('storeId', 'Store', type: FieldType.select, options: [for (final s in stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' (primary)' : ''}')]),
        if (isNew) FieldSpec('product', 'Applies to', type: FieldType.select, options: [('', 'All my products'), for (final x in products) (idOf(x), strOf(x['name']))]),
        ..._promoFields,
      ],
      initial:
          isNew
              ? {'type': 'PERCENT', 'status': 'DRAFT', 'value': '10', 'storeId': idOf(stores.where((s) => s['isPrimary'] == true).firstOrNull), 'product': ''}
              : {
                ...p,
                'startsAt': _inputDate(p['startsAt']),
                'endsAt': _inputDate(p['endsAt']),
                'usageLimit': p['usageLimit'] == null ? '' : '${p['usageLimit']}',
                'value': '${p['value'] ?? ''}',
                'minOrderAmount': '${p['minOrderAmount'] ?? ''}',
              },
      submitLabel: isNew ? 'Create promotion' : 'Save changes',
      onSubmit: (v) async {
        if (isNew) {
          await jpost('/promotions', {..._promoPayload(v), if ('${v['storeId'] ?? ''}'.isNotEmpty) 'storeId': v['storeId'], if ('${v['product'] ?? ''}'.isNotEmpty) 'product': v['product']});
        } else {
          await jpatch('/promotions/${p['id']}', _promoPayload(v));
        }
        return true;
      },
    );
    if (res == true && mounted) {
      toast(context, isNew ? 'Promotion created.' : 'Promotion saved.');
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final rows = d.promos;
        final shown = rows.where((r) => _inPromoTab(r, _tab)).toList();
        num orders = 0, sales = 0, discount = 0;
        for (final r in rows) {
          final s = asMap(r['stats']);
          orders += numOf(s['orders']);
          sales += numOf(s['sales']);
          discount += numOf(s['discountGiven']);
        }
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Promotions',
          subtitle: 'Coupon codes buyers enter at checkout. Discounts apply only to your items and come out of your earnings for that order.',
          onRefresh: _data.reload,
          action: GradientButton(label: 'New promotion', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null, d.stores, d.products)),
          children: [
            MetricGrid(
              children: [
                MetricCard(
                  label: 'Live codes',
                  value: '${rows.where((r) => r['liveStatus'] == 'ACTIVE').length}',
                  icon: 'tag',
                  sub: '${rows.where((r) => r['liveStatus'] == 'SCHEDULED').length} scheduled',
                ),
                MetricCard(label: 'Orders with a code', value: '$orders', icon: 'cart', sub: 'Excluding cancelled orders'),
                MetricCard(label: 'Sales from codes', value: money(sales), icon: 'chart', sub: 'Your items, after discount'),
                MetricCard(label: 'Discount given', value: money(discount), icon: 'wallet', sub: 'Paid from your earnings'),
              ],
            ),
            const SizedBox(height: 14),
            TabChips(tabs: _promoTabs, value: _tab, counts: {for (final t in _promoTabs) t.$1: rows.where((r) => _inPromoTab(r, t.$1)).length}, onChanged: (v) => setState(() => _tab = v)),
            Paged<Map<String, dynamic>>(
              items: shown,
              empty: const EmptyState(icon: Icons.local_offer_outlined, title: 'No promotions here', message: 'Create a code and share it with your buyers.'),
              itemBuilder: (r) {
                final s = asMap(r['stats']);
                final product = strOf(r['product']).isEmpty ? '' : strOf(d.products.where((p) => idOf(p) == '${r['product']}').map((p) => p['name']).firstOrNull, 'one product');
                return RecordCard(
                  title: strOf(r['name']),
                  subtitle: '${r['discount'] ?? ''} · ${numOf(r['minOrderAmount']) > 0 ? 'Min. ${money(r['minOrderAmount'])}' : 'No minimum'}${product.isEmpty ? '' : ' · $product'}',
                  lines: [
                    'Used ${numOf(r['usedCount']).toInt()}${r['usageLimit'] != null ? ' / ${r['usageLimit']}' : ''} · ${r['startsAt'] != null ? formatDate(r['startsAt']) : 'Now'} → ${r['endsAt'] != null ? formatDate(r['endsAt']) : 'no end'}',
                    numOf(s['orders']) > 0 ? '${money(s['sales'])} from ${s['orders']} order${numOf(s['orders']) == 1 ? '' : 's'} · ${money(s['discountGiven'])} discount' : 'No orders yet',
                    if (d.stores.length > 1) 'Store: ${strOf(d.stores.where((st) => idOf(st) == '${r['store']}').map((st) => st['storeName']).firstOrNull, '—')}',
                  ],
                  status: Pill(r['liveStatus'] ?? r['status'], label: _liveLabel[r['liveStatus']] ?? titleCase(r['liveStatus'] ?? r['status'])),
                  actions: [
                    ActionChipBtn(strOf(r['code']), icon: Icons.copy_rounded, onPressed: () => copyText(context, strOf(r['code']), '${r['code']} copied.')),
                    ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(r, d.stores, d.products)),
                    if (['ACTIVE', 'PAUSED'].contains(r['status']))
                      ActionChipBtn(
                        r['status'] == 'ACTIVE' ? 'Pause' : 'Activate',
                        onPressed: () async {
                          if (await runAction(context, () => jpatch('/promotions/${r['id']}', {'status': r['status'] == 'ACTIVE' ? 'PAUSED' : 'ACTIVE'}), success: 'Promotion updated.')) {
                            _data.reload();
                          }
                        },
                      ),
                    ActionChipBtn(
                      'Delete',
                      danger: true,
                      onPressed: () async {
                        if (!await confirmDialog(context, 'Delete promotion ${r['code']}?', confirm: 'Delete', danger: true)) return;
                        if (context.mounted && await runAction(context, () => jdelete('/promotions/${r['id']}'), success: 'Promotion deleted.')) _data.reload();
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// ─── Shipping ────────────────────────────────────────────────────────────────
