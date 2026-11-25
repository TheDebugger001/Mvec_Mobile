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

/// `/advertise` — "Advertise here" (`pages/Advertise.jsx`): a seller or
/// supplier puts one product in the home page banner. Every ad costs the same
/// flat price (the server sets it) and shows for 5 seconds each turn: the
/// picture on the right, the seller's title and description on the left.
/// Paid by mobile money; the ad goes live once the payment is confirmed.
class AdvertisePage extends ConsumerStatefulWidget {
  const AdvertisePage({super.key});

  @override
  ConsumerState<AdvertisePage> createState() => _AdvertisePageState();
}

class _AdvertisePageState extends ConsumerState<AdvertisePage> {
  Map<String, dynamic> _price = const {'price': 5000, 'seconds': 5, 'days': 7, 'titleMax': 60, 'descriptionMax': 1000};
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _bookings = const [];
  String? _productId;
  String _method = 'MOMO';
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  ({bool ok, String text})? _notice;

  @override
  void initState() {
    super.initState();
    jget('/ad-bookings/pricing').then((p) { if (mounted) setState(() => _price = {..._price, ...p}); }).catchError((_) {});
    Future.microtask(_loadMine);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
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

  String? _problem() {
    if (_productId == null) return 'Choose the product you want to advertise.';
    if (_title.text.trim().length < 3) return 'Write a title of at least 3 characters.';
    if (_description.text.trim().length < 5) return 'Write a short description.';
    if (_phone.text.trim().isEmpty) return 'Enter the MTN or Airtel number that pays.';
    return null;
  }

  Future<void> _pay() async {
    final problem = _problem();
    if (problem != null) return setState(() => _notice = (ok: false, text: problem));
    final price = money(_price['price']);
    if (!await confirmDialog(context, 'Pay $price to show this product in the home page banner for ${numOf(_price['days'], 7).toInt()} days?', confirm: 'Pay $price', title: 'Check before you pay')) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      // No price goes to the server: it charges the flat price itself.
      final res = asMap(await jpost('/ad-bookings', {
        'productId': _productId,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'paymentMethod': _method,
        'phoneNumber': _phone.text.trim(),
      }));
      setState(() {
        _notice = (ok: true, text: strOf(res['message']));
        _productId = null;
        _title.clear();
        _description.clear();
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
    final price = numOf(_price['price'], 5000);
    final seconds = numOf(_price['seconds'], 5).toInt();
    final days = numOf(_price['days'], 7).toInt();
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: mv.text)),
        );
    return PageFrame(
      title: 'Advertise',
      storefront: true,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Put your product in the home banner', style: context.mvH1.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Your product takes turns in the banner at the top of the Ikiguzi home page: its picture on the right, your title and description on the left. One ad costs ${money(price)} and runs for $days days; each ad shows for $seconds seconds before the next one. Pay by mobile money; if Ikiguzi takes the ad down, you are refunded in full.',
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
            heading('1. Choose the product'),
            if (_products.isEmpty) const Tiny('You have no products on sale yet. Only live, in-stock products can be advertised.'),
            for (final p in _products)
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: _productId == idOf(p),
                onTap: () => setState(() => _productId = idOf(p)),
                leading: ProductImage(src: strOf(asMap(p['media'])['mainImage']), size: 44, radius: 8),
                title: Text(strOf(p['name']), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(money(p['price'])),
                trailing: Icon(_productId == idOf(p) ? Icons.radio_button_checked : Icons.radio_button_off, color: _productId == idOf(p) ? mv.accent : mv.border),
              ),
            heading('2. Write your banner'),
            TextField(controller: _title, maxLength: numOf(_price['titleMax'], 60).toInt(), decoration: const InputDecoration(labelText: 'Title (the big text)', hintText: 'Fresh coffee, direct from Huye')),
            TextField(controller: _description, maxLines: 3, maxLength: numOf(_price['descriptionMax'], 1000).toInt(), decoration: const InputDecoration(labelText: 'Description (smaller text under the title)')),
            heading('3. Pay'),
            Wrap(spacing: 8, children: [
              for (final m in const [('MOMO', 'MTN Mobile Money'), ('AIRTEL', 'Airtel Money')])
                ChoiceChip(showCheckmark: false, selected: _method == m.$1, label: Text(m.$2), onSelected: (_) => setState(() => _method = m.$1)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Mobile money number that pays', hintText: _method == 'MOMO' ? '078 or 079…' : '072 or 073…')),
            const SizedBox(height: 10),
            Text('One ad = ${money(price)} for $days days', style: context.mvH1.copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
            if (_notice != null) ...[const SizedBox(height: 10), Notice(text: _notice!.text, ok: _notice!.ok)],
            const SizedBox(height: 12),
            GradientButton(label: 'Pay ${money(price)}', expand: true, loading: _busy, onPressed: _busy ? null : _pay),
            if (_bookings.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('My ads', style: TextStyle(fontWeight: FontWeight.w800, color: mv.text)),
              const SizedBox(height: 6),
              for (final b in _bookings)
                RecordCard(
                  title: '${strOf(b['title'], strOf(b['bookingNumber']))} · ${b['statusLabel']}',
                  subtitle: '${asMaps(b['products']).map((p) => p['name']).join(', ')} · ${money(b['amount'])} · ${b['paymentLabel'] ?? ''}',
                  lines: [
                    if (b['status'] == 'LIVE') 'On the home page until ${formatDate(b['endsAt'])}',
                    if (b['status'] == 'LIVE' && b['views'] != null) '${numOf(b['views']).toInt()} views · ${numOf(b['clicks']).toInt()} presses',
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
