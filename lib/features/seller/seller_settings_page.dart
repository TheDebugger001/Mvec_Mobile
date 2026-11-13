import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

const _shortcuts = [
  ('/vendor/stores', 'Storefront', 'Logo, description and store contact details', 'shop'),
  ('/vendor/shipping', 'Shipping zones', 'Delivery fees, regions and delivery times', 'box'),
  ('/vendor/payouts', 'Payouts', 'Balance and mobile money withdrawals', 'wallet'),
  ('/vendor/team', 'Team & permissions', 'Staff accounts and their access', 'users'),
  ('/vendor/notifications', 'Notifications', 'Order, stock and payout alerts', 'bell'),
  ('/vendor/profile', 'Account & security', 'Your personal profile and password', 'shield'),
];

/// `/vendor/settings` — business profile, account status and commission.
class SellerSettingsPage extends ConsumerStatefulWidget {
  const SellerSettingsPage({super.key});

  @override
  ConsumerState<SellerSettingsPage> createState() => _SellerSettingsPageState();
}

class _SellerSettingsPageState extends ConsumerState<SellerSettingsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([
      jget('/vendors/me/profile'),
      jget('/payouts/balance').catchError((_) => <String, dynamic>{}),
      jget('/vendors/me/fees').catchError((_) => <String, dynamic>{}),
      jlist('/categories', 'categories').catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (vendor: asMap((r[0] as Map)['vendor']), commissionRate: strOf((r[1] as Map)['commissionRate']), fees: r[2] as Map<String, dynamic>, categories: r[3] as List<Map<String, dynamic>>);
  });
  final _c = {
    for (final k in ['businessName', 'email', 'phone', 'location', 'description']) k: TextEditingController(),
  };
  String _category = '';
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _data.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_c['businessName']!.text.trim().isEmpty) {
      toast(context, 'Business name is required.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await jpatch('/vendors/me/profile', {for (final e in _c.entries) e.key: e.value.text.trim(), 'category': _category});
      if (mounted) toast(context, res['message'] == 'Vendor profile updated' ? 'Business profile saved.' : strOf(res['message'], 'Business profile saved.'));
      ref.read(authProvider.notifier).refresh().ignore();
      _data.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Settings',
      subtitle: 'Business profile, verification status and shortcuts to every store setting.',
      onRefresh: _data.reload,
      children: [
        ListenableBuilder(
          listenable: _data,
          builder: (context, _) {
            if (_data.data == null && _data.error != null) {
              return Notice(text: statusOf(_data.error!) == 404 ? 'No business profile yet. Create your store first from My Stores.' : errorText(_data.error!));
            }
            final d = _data.data;
            if (d == null) return const LoadingState();
            final v = d.vendor;
            if (!_filled) {
              _filled = true;
              for (final k in _c.keys) {
                _c[k]!.text = strOf(v[k]);
              }
              _category = strOf(v['category']);
            }
            final fees = d.fees;
            final cats = asMaps(fees['categories']);
            final defaultPercent = fees['defaultPercent'];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v['verificationStatus'] == 'REJECTED')
                  Notice(text: 'Ikiguzi asked for changes: ${strOf(v['verificationNote'], 'Check your business details.')} Save your profile to send it back for review.'),
                Section(
                  title: 'Business profile',
                  subtitle: 'Shown on your public vendor page',
                  children: [
                    TextField(controller: _c['businessName'], decoration: const InputDecoration(labelText: 'Business name *')),
                    const SizedBox(height: 10),
                    FilterSelect(
                      label: 'Business category',
                      value: _category,
                      options: [
                        ('', 'Select a category'),
                        for (final c in d.categories) (strOf(c['name']), strOf(c['name'])),
                        if (_category.isNotEmpty && !d.categories.any((c) => c['name'] == _category)) (_category, _category),
                      ],
                      onChanged: (x) => setState(() => _category = x),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: _c['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Business email')),
                    const SizedBox(height: 10),
                    TextField(controller: _c['phone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Business phone')),
                    const SizedBox(height: 10),
                    TextField(controller: _c['location'], decoration: const InputDecoration(labelText: 'Location', hintText: 'Kigali')),
                    const SizedBox(height: 10),
                    TextField(controller: _c['description'], minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'About the business')),
                    const SizedBox(height: 12),
                    GradientButton(label: 'Save profile', loading: _saving, onPressed: _save),
                  ],
                ),
                Section(
                  title: 'Account status',
                  subtitle: 'Managed by Ikiguzi',
                  children: [
                    Row(children: [const Expanded(child: Text('Account')), Pill(strOf(v['status'], 'ACTIVE'))]),
                    const SizedBox(height: 8),
                    Row(children: [const Expanded(child: Text('Verification')), Pill(strOf(v['verificationStatus'], 'PENDING'))]),
                    KV('Ikiguzi commission', defaultPercent != null ? '$defaultPercent% unless your category differs' : d.commissionRate),
                    KV('Rating', '${numOf(v['ratingAvg']).toStringAsFixed(1)} / 5'),
                  ],
                ),
                if (defaultPercent != null && cats.any((c) => c['percent'] != defaultPercent))
                  Section(
                    title: 'Your Ikiguzi commission by category',
                    subtitle: 'Taken from each sale when the buyer pays. Payment provider fees are paid by ${fees['gatewayFeePayer'] == 'SELLER' ? 'you' : 'Ikiguzi'}.',
                    children: [
                      for (final c in cats.where((c) => c['percent'] != defaultPercent)) KV('${c['category']} (${c['source']})', '${c['percent']}%'),
                      KV('Every other category', '$defaultPercent%'),
                    ],
                  ),
                DataCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final (to, title, sub, icon) in _shortcuts)
                        ListTile(
                          leading: Icon(_iconFor(icon), color: context.mv.accentDeep),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.go(to),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

IconData _iconFor(String name) => switch (name) {
  'shop' => Icons.storefront_outlined,
  'box' => Icons.local_shipping_outlined,
  'wallet' => Icons.account_balance_wallet_outlined,
  'users' => Icons.group_outlined,
  'bell' => Icons.notifications_none_rounded,
  _ => Icons.shield_outlined,
};

// ─── Team ────────────────────────────────────────────────────────────────────
