import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'products_pages.dart' show productImage;

const _steps = [
  ('You open your products', 'Turn the program on for all your products or only the ones you choose, and set the commission you add.'),
  ('Affiliates share tracked links', 'Each affiliate gets a unique link. A visitor who clicks it is remembered for 30 days (the last link clicked wins).'),
  ('A buyer orders and pays', "The affiliate's commission is recorded as pending. Nothing is taken from you yet."),
  ('The buyer confirms delivery', "Only then is the commission earned: your share is deducted from that sale, together with MVEC's fee."),
  ('Refunds reverse it', "If the order is cancelled or refunded, the affiliate's commission is taken back."),
];

/// `/vendor/affiliates` — the seller's affiliate program (`VendorAffiliate`).
class SellerAffiliateProgramPage extends StatefulWidget {
  const SellerAffiliateProgramPage({super.key});

  @override
  State<SellerAffiliateProgramPage> createState() => _SellerAffiliateProgramPageState();
}

class _SellerAffiliateProgramPageState extends State<SellerAffiliateProgramPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([jget('/vendors/me/affiliate-program'), vendorProducts(), jget('/affiliates/vendor/summary').catchError((_) => <String, dynamic>{})]);
    final p = r[0] as Map<String, dynamic>;
    final program = asMap(p['program']);
    if (!_filled) {
      _filled = true;
      _enabled = program['enabled'] == true;
      _rate.text = '${numOf(program['ratePercent'])}';
      _scope = strOf(program['scope'], 'ALL');
      _selected
        ..clear()
        ..addAll([for (final x in (program['selectedProductIds'] is List ? program['selectedProductIds'] as List : const [])) '$x']);
    }
    return (
      program: program,
      stats: asMap(p['stats']),
      maxRate: numOf(p['maxRatePercent'], 30),
      products: (r[1] as List<Map<String, dynamic>>).where((x) => ['ACTIVE', 'OUT_OF_STOCK'].contains(x['status'])).toList(),
      summary: r[2] as Map<String, dynamic>,
    );
  });
  bool _filled = false;
  bool _enabled = false;
  final _rate = TextEditingController();
  String _scope = 'ALL';
  final _selected = <String>{};
  String _q = '';
  bool _saving = false;

  @override
  void dispose() {
    _data.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save(num maxRate) async {
    final rate = numOf(_rate.text).clamp(0, 1 << 20);
    if (rate > maxRate) {
      toast(context, 'Choose a commission between 0% and $maxRate%.', error: true);
      return;
    }
    if (_enabled && _scope == 'SELECTED' && _selected.isEmpty) {
      toast(context, 'Choose at least one product, or open all your products to affiliates.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await jput('/vendors/me/affiliate-program', {'enabled': _enabled, 'ratePercent': rate, 'scope': _scope, if (_scope == 'SELECTED') 'productIds': _selected.toList()});
      if (mounted) toast(context, strOf(res['message'], 'Program saved.'));
      _filled = false;
      await _data.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Marketing',
      title: 'Affiliate program',
      subtitle: 'Let affiliates and influencers promote your products for a commission. It is off until you turn it on, and you choose which products and how much you add.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final platform = numOf(d.program['platformPercent'], 0.5);
            final rate = numOf(_rate.text).clamp(0, 1 << 20);
            final total = ((platform + rate) * 100).round() / 100;
            final shown = d.products.where((p) => matches(_q, [p['name']])).toList();
            final s = d.stats;
            final sum = d.summary;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Section(
                  title: 'Program settings',
                  subtitle: d.program['enabled'] == true ? 'On · affiliates earn ${d.program['totalPercent']}%' : 'Off · affiliates cannot promote your products',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      title: const Text('Let affiliates promote my products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: const Text(
                        'When off, your products are not offered to affiliates and existing links stop earning. Orders already placed keep their commission.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _rate,
                      enabled: _enabled,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Your commission (%)', helperText: '0 to ${d.maxRate}%'),
                      onChanged: (_) => setState(() {}),
                    ),
                    InfoBox(
                      title: 'Affiliates earn $total% per delivered sale',
                      text:
                          'MVEC pays $platform% from its fee; you pay $rate% from your earnings on that sale. Example: on a ${money(100000)} sale the affiliate earns ${money(1000 * total)}; you pay ${money(1000 * rate)}.',
                    ),
                    const Text('Which products', style: TextStyle(fontWeight: FontWeight.w800)),
                    RadioGroup<String>(
                      groupValue: _scope,
                      onChanged: (v) => _enabled ? setState(() => _scope = v ?? 'ALL') : null,
                      child: const Column(
                        children: [
                          RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'ALL', title: Text('All my products (including new ones)')),
                          RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'SELECTED', title: Text('Only the products I choose')),
                        ],
                      ),
                    ),
                    if (_scope == 'SELECTED') ...[
                      SearchBox(hint: 'Search your products…', onChanged: (v) => setState(() => _q = v)),
                      if (shown.isEmpty) const Tiny('No products for sale yet.'),
                      for (final p in shown)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(idOf(p)),
                          onChanged: _enabled ? (on) => setState(() => on == true ? _selected.add(idOf(p)) : _selected.remove(idOf(p))) : null,
                          secondary: ProductImage(src: productImage(p), size: 40, radius: 6),
                          title: Text(strOf(p['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          subtitle: Text(
                            '${money(numOf(p['discountPrice']) > 0 ? p['discountPrice'] : p['price'])} · affiliate earns ${money(numOf(numOf(p['discountPrice']) > 0 ? p['discountPrice'] : p['price']) * total / 100)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      Tiny('${_selected.length} product${_selected.length == 1 ? '' : 's'} chosen'),
                    ],
                    const SizedBox(height: 10),
                    GradientButton(label: 'Save program', loading: _saving, onPressed: () => _save(d.maxRate)),
                  ],
                ),
                if (s.isNotEmpty)
                  MetricGrid(
                    children: [
                      MetricCard(label: 'Active links', value: '${numOf(s['activeLinks']).toInt()}', icon: 'tag', sub: '${s['affiliates'] ?? 0} affiliate${numOf(s['affiliates']) == 1 ? '' : 's'}'),
                      MetricCard(label: 'Clicks', value: compact(s['clicks']), icon: 'eye', sub: 'Visits from affiliate links'),
                      MetricCard(label: 'Affiliate orders', value: '${numOf(s['orders']).toInt()}', icon: 'cart', sub: '${money(s['sales'])} in sales'),
                      MetricCard(label: 'Commission', value: money(s['commission']), icon: 'wallet', sub: '${money(s['paidByYou'])} paid by you'),
                    ],
                  ),
                const SizedBox(height: 14),
                if (asMaps(sum['affiliates']).isNotEmpty)
                  Section(
                    title: 'Top affiliates',
                    subtitle: 'Who brings you buyers',
                    children: [
                      for (final a in asMaps(sum['affiliates']))
                        RecordCard(
                          title: strOf(a['name']),
                          subtitle: '${a['links'] ?? 0} links · ${compact(a['clicks'])} clicks · ${a['orders'] ?? 0} orders',
                          lines: ['Last order ${formatDate(a['lastOrderAt'])}'],
                          amount: money(a['sales']),
                        ),
                    ],
                  ),
                if (asMaps(sum['products']).isNotEmpty)
                  Section(
                    title: 'Products affiliates promote',
                    subtitle: 'Links, clicks and sales per product',
                    children: [
                      for (final p in asMaps(sum['products']))
                        RecordCard(
                          title: strOf(p['name']),
                          subtitle: '${p['links'] ?? 0} links · ${compact(p['clicks'])} clicks · ${p['units'] ?? 0} sold',
                          amount: money(p['sales']),
                          onTap: () => context.push('/product/${p['productId']}'),
                        ),
                    ],
                  ),
                if (asMaps(sum['recent']).isNotEmpty)
                  Section(
                    title: 'Recent referred orders',
                    subtitle: 'Latest 20',
                    children: [
                      for (final o in asMaps(sum['recent']))
                        RecordCard(
                          title: strOf(o['orderNumber']),
                          subtitle: '${formatDate(o['date'])} · referred by ${o['affiliate']} (${o['code']})',
                          amount: money(o['sales']),
                          status: Pill(o['paymentStatus'] == 'PAID' ? o['orderStatus'] : o['paymentStatus']),
                          onTap: () => context.push('/vendor/orders/${o['orderId']}'),
                        ),
                    ],
                  ),
                Section(
                  title: 'How it works',
                  subtitle: 'Commission is only earned on delivered orders',
                  children: [
                    for (final (i, (t, x)) in _steps.indexed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('${i + 1}. $t', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        subtitle: Text(x, style: const TextStyle(fontSize: 12)),
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
