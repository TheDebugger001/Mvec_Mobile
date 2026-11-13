import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// `/admin/subscriptions` — the dormant subscription program and plans.
class AdminSubscriptionsPage extends StatefulWidget {
  const AdminSubscriptionsPage({super.key});

  @override
  State<AdminSubscriptionsPage> createState() => _AdminSubscriptionsPageState();
}

class _AdminSubscriptionsPageState extends State<AdminSubscriptionsPage> {
  late final _program = Loader(() async {
    final r = await Future.wait([jget('/admin/operations-settings'), jget('/plans/me')]);
    return (settings: asMap(r[0]['settings']), info: r[1]);
  });
  late final _subs = Loader(() async {
    final r = await Future.wait([
      jlist('/admin/subscriptions', 'data', {'limit': 200}),
      jlist('/admin/buyer-subscriptions', 'data', {'limit': 200}),
    ]);
    return (vendors: r[0], buyers: r[1]);
  });
  final _c = {
    for (final k in ['sellerPremiumPrice', 'buyerPremiumPrice', 'freeProductLimit']) k: TextEditingController(),
  };
  bool _filled = false;
  bool _busy = false;

  @override
  void dispose() {
    _program.dispose();
    _subs.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> patch, [String? confirm]) async {
    if (confirm != null && !await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => jput('/admin/operations-settings', patch));
    if (mounted) setState(() => _busy = false);
    if (ok) {
      _filled = false;
      _program.reload();
    }
  }

  Widget _plans(List<Map<String, dynamic>> rows) => Column(
    children: [
      if (rows.isEmpty) const Tiny('No subscriptions yet.'),
      for (final r in rows)
        RecordCard(
          title: strOf(r['holder']),
          subtitle: '${r['plan'] ?? ''} · ${r['billing'] ?? ''} · renews ${r['renewal'] ?? '—'}',
          amount: numOf(r['price']) > 0 ? money(r['price']) : 'Free',
          status: Pill(r['status'] == 'Active' ? 'ACTIVE' : r['status'], label: strOf(r['status'])),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Growth',
      title: 'Subscriptions',
      subtitle: 'Paid seller Premium and buyer ad-free plans. Plans renew and expire automatically.',
      onRefresh: () async {
        await Future.wait([_program.reload(), _subs.reload()]);
      },
      children: [
        LoadView(
          loader: _program,
          loadingLabel: 'Loading the subscription program…',
          builder: (d) {
            final s = d.settings;
            final on = s['subscriptionsEnabled'] == true;
            if (!_filled) {
              _filled = true;
              for (final k in _c.keys) {
                _c[k]!.text = '${numOf(s[k]).toInt()}';
              }
            }
            final free = [for (final x in (d.info['freeIncludes'] is List ? d.info['freeIncludes'] as List : const [])) '$x'];
            final premium = [for (final x in asMap(d.info['premiumFeatures']).values) '$x'];
            return Section(
              title: 'Subscription program',
              subtitle:
                  on
                      ? 'On: sellers and suppliers on Free have the Free limits; Premium is paid monthly from their balance.'
                      : 'Off: nobody is charged and every seller and supplier has every tool for free.',
              trailing: StatusChip(on ? 'On' : 'Off', tone: on ? StatusTone.good : StatusTone.warn),
              children: [
                DataCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Free Seller · RWF 0', style: TextStyle(fontWeight: FontWeight.w800)),
                      const Tiny('For new and small sellers and suppliers'),
                      for (final x in free) Tiny('• $x${x.startsWith('List products') ? ' (${_c['freeProductLimit']!.text})' : ''}'),
                    ],
                  ),
                ),
                DataCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seller Premium · ${money(_c['sellerPremiumPrice']!.text)}/month (recommended)', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Tiny("Paid from the seller's available balance"),
                      for (final x in premium) Tiny('• $x'),
                    ],
                  ),
                ),
                TextField(
                  controller: _c['sellerPremiumPrice'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seller Premium (RWF / month)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(controller: _c['buyerPremiumPrice'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Buyer ad-free (RWF / month)')),
                const SizedBox(height: 10),
                TextField(
                  controller: _c['freeProductLimit'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Free listing limit (products)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                OutlineBtn(label: 'Save prices and limit', loading: _busy, onPressed: () => _save({for (final e in _c.entries) e.key: numOf(e.value.text)})),
                const SizedBox(height: 8),
                on
                    ? OutlineBtn(
                      label: 'Switch program off',
                      onPressed:
                          _busy
                              ? null
                              : () => _save({
                                'subscriptionsEnabled': false,
                              }, 'Switch the subscription program off? Everyone gets every tool for free again and no renewals are charged. Active Premium plans keep their paid time.'),
                    )
                    : GradientButton(
                      label: 'Switch program on',
                      onPressed:
                          _busy
                              ? null
                              : () => _save(
                                {'subscriptionsEnabled': true},
                                'Switch the subscription program on? Free sellers and suppliers become limited to ${_c['freeProductLimit']!.text} products and Premium tools need a ${money(_c['sellerPremiumPrice']!.text)}/month plan. Tell your sellers before doing this.',
                              ),
                    ),
              ],
            );
          },
        ),
        LoadView(
          loader: _subs,
          loadingLabel: 'Loading subscriptions…',
          builder: (d) {
            bool paid(Map<String, dynamic> s) => s['planKey'] == 'PREMIUM' && s['status'] == 'Active';
            final monthly = [...d.vendors, ...d.buyers].where(paid).fold<num>(0, (sum, s) => sum + (s['billing'] == 'Yearly' ? numOf(s['price']) / 12 : numOf(s['price'])));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(icon: 'shop', label: 'Sellers on Premium', value: '${d.vendors.where(paid).length}'),
                    MetricCard(icon: 'users', label: 'Buyers ad-free', value: '${d.buyers.where(paid).length}'),
                    MetricCard(icon: 'wallet', label: 'Monthly value', value: money(monthly), sub: 'Active paid plans (yearly ÷ 12)'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(title: 'Sellers', subtitle: '${d.vendors.length} subscriptions', children: [_plans(d.vendors)]),
                Section(title: 'Buyers', subtitle: '${d.buyers.length} subscriptions', children: [_plans(d.buyers)]),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Platform settings ──────────────────────────────────────────────────────
