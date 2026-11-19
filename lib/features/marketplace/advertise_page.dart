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
import '../common/page_frame.dart';

const _sellers = ['vendor', 'supplier', 'super_admin'];

/// `/advertise` — "Advertise here" (`pages/Advertise.jsx`): sellers and
/// suppliers put products in the home page banner for a flat fee per product,
/// paid by mobile money. Ikiguzi approves it, or rejects it and refunds.
class AdvertisePage extends ConsumerStatefulWidget {
  const AdvertisePage({super.key});

  @override
  ConsumerState<AdvertisePage> createState() => _AdvertisePageState();
}

class _AdvertisePageState extends ConsumerState<AdvertisePage> {
  Map<String, dynamic> _price = const {'pricePerProduct': 1000, 'days': 7};
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _bookings = const [];
  final _picked = <String>{};
  final _phone = TextEditingController();
  bool _busy = false;
  ({bool ok, String text})? _notice;

  @override
  void initState() {
    super.initState();
    jget('/ad-bookings/pricing').then((p) { if (mounted) setState(() => _price = p); }).catchError((_) {});
    Future.microtask(_loadMine);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    final user = ref.read(authProvider).user;
    if (user == null || !_sellers.contains(user.role)) return;
    if (_phone.text.isEmpty) _phone.text = user.telephone;
    try {
      // Suppliers advertise the marketplace listings of their wholesale products.
      final list = user.role == 'supplier'
          ? [for (final w in asMaps(asMap(await jget('/suppliers/me/products'))['products'])) if (w['retailProduct'] is Map) asMap(w['retailProduct'])]
          : asMaps(asMap(await jget('/products/vendor/me'))['products']);
      final mine = asMaps(asMap(await jget('/ad-bookings/mine'))['bookings']);
      if (mounted) {
        setState(() {
          _products = list.where((p) => p['status'] == 'ACTIVE' && numOf(p['stockQuantity']) > 0).toList();
          _bookings = mine;
        });
      }
    } catch (_) {}
  }

  Future<void> _pay() async {
    if (_picked.isEmpty) return setState(() => _notice = (ok: false, text: 'Choose at least one product.'));
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final res = asMap(await jpost('/ad-bookings', {'productIds': _picked.toList(), 'phoneNumber': _phone.text.trim()}));
      setState(() {
        _notice = (ok: true, text: strOf(res['message']));
        _picked.clear();
      });
      await _loadMine();
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final user = ref.watch(authProvider.select((a) => a.user));
    final per = numOf(_price['pricePerProduct'], 1000);
    final days = numOf(_price['days'], 7).toInt();
    return PageFrame(
      title: 'Advertise',
      storefront: true,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Put your products on the home page', style: context.mvH1.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Your products show in the banner at the top of the Ikiguzi home page for $days days. It costs ${money(per)} per product: 3 products cost ${money(per * 3)}. Pay by mobile money; Ikiguzi checks the ad and puts it live, or refunds you in full.',
              style: TextStyle(color: mv.textMuted, fontSize: 13, height: 1.45)),
          const SizedBox(height: 16),
          if (user == null) ...[
            const Notice(info: true, text: 'Advertising is for seller and supplier accounts, the accounts that list products.'),
            const SizedBox(height: 10),
            GradientButton(label: 'Log in', expand: true, onPressed: () => context.push('/login')),
            const SizedBox(height: 8),
            OutlineBtn(label: 'Create a seller account', expand: true, onPressed: () => context.push('/signup?role=vendor')),
          ] else if (!_sellers.contains(user.role)) ...[
            const Notice(info: true, text: 'Advertising is for sellers and suppliers. Open a store to list products, then advertise them here.'),
            const SizedBox(height: 10),
            GradientButton(label: 'Start selling', expand: true, onPressed: () => context.push('/signup?role=vendor')),
          ] else ...[
            Text('Choose products', style: TextStyle(fontWeight: FontWeight.w800, color: mv.text)),
            const SizedBox(height: 6),
            if (_products.isEmpty) const Tiny('You have no products on sale yet. Only live, in-stock products can be advertised.'),
            for (final p in _products)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _picked.contains(idOf(p)),
                onChanged: (v) => setState(() => v == true ? _picked.add(idOf(p)) : _picked.remove(idOf(p))),
                secondary: ProductImage(src: strOf(asMap(p['media'])['mainImage']), size: 44, radius: 8),
                title: Text(strOf(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(money(p['price'])),
              ),
            const SizedBox(height: 8),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile money number that pays', hintText: '07xx xxx xxx')),
            const SizedBox(height: 10),
            Text('${_picked.length} × ${money(per)} = ${money(per * _picked.length)}', style: context.mvH1.copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
            if (_notice != null) ...[const SizedBox(height: 10), Notice(text: _notice!.text, ok: _notice!.ok)],
            const SizedBox(height: 12),
            GradientButton(label: 'Pay ${money(per * _picked.length)}', expand: true, loading: _busy, onPressed: _busy || _picked.isEmpty ? null : _pay),
            if (_bookings.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('My ads', style: TextStyle(fontWeight: FontWeight.w800, color: mv.text)),
              const SizedBox(height: 6),
              for (final b in _bookings)
                RecordCard(
                  title: '${b['bookingNumber']} · ${b['statusLabel']}',
                  subtitle: '${asMaps(b['products']).map((p) => p['name']).join(', ')} · ${money(b['amount'])}',
                  lines: [
                    if (b['status'] == 'LIVE') 'On the home page until ${formatDate(b['endsAt'])}',
                    if (b['status'] == 'REJECTED') 'Reason: ${b['rejectionReason']}. Refunded to ${strOf(b['payerPhone'], 'the paying number')}.',
                  ],
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Ikiguzi: paid home page ad bookings to approve (live) or reject (refund).
class AdBookingsAdminSection extends StatefulWidget {
  const AdBookingsAdminSection({super.key});

  @override
  State<AdBookingsAdminSection> createState() => _AdBookingsAdminSectionState();
}

class _AdBookingsAdminSectionState extends State<AdBookingsAdminSection> {
  late final Loader<List<Map<String, dynamic>>> _rows = Loader(() async => asMaps(asMap(await jget('/ad-bookings/admin', {'status': 'PAID'}))['bookings']));

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Home page ad bookings to approve',
      subtitle: 'Paid per product. Rejecting refunds the number that paid.',
      children: [
        LoadView<List<Map<String, dynamic>>>(
          loader: _rows,
          builder: (rows) => rows.isEmpty
              ? const Tiny('Nothing waiting.')
              : Column(children: [
                  for (final b in rows)
                    RecordCard(
                      title: '${b['bookingNumber']} · ${money(b['amount'])}',
                      subtitle: '${b['sellerName']} · paid from ${b['payerPhone']}',
                      lines: [asMaps(b['products']).map((p) => p['name']).join(', ')],
                      actions: [
                        GradientButton(label: 'Approve', compact: true, onPressed: () async {
                          if (await runAction(context, () => jpost('/ad-bookings/${idOf(b)}/approve'))) _rows.reload();
                        }),
                        OutlineBtn(label: 'Reject & refund', compact: true, onPressed: () async {
                          final why = await promptDialog(context, 'Why reject it? The seller sees this, and the money is refunded.', confirm: 'Reject');
                          if (why == null || !context.mounted) return;
                          if (await runAction(context, () => jpost('/ad-bookings/${idOf(b)}/reject', {'reason': why}))) _rows.reload();
                        }),
                      ],
                    ),
                ]),
        ),
      ],
    );
  }
}
