import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/catalog_api.dart';
import '../../api/commerce_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/order_rules.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../common/page_frame.dart';
import '../../portal/shared_pages.dart';

const _steps = <({String label, String by, List<String> statuses, String text})>[
  (label: 'Order placed', by: 'You', statuses: ['PENDING'], text: 'The items are reserved for you for 30 minutes while you pay.'),
  (label: 'Payment confirmed', by: 'Payment provider · automatic', statuses: ['CONFIRMED'], text: 'Mobile money, card or K-Pay confirms your payment. MVEC holds the money; the seller is not paid yet.'),
  (label: 'Preparing & packing', by: 'Seller', statuses: ['PROCESSING', 'READY_FOR_SHIPMENT'], text: 'The seller prepares your items and marks them packed.'),
  (label: 'On the way', by: 'Seller, then courier', statuses: ['SHIPPED', 'OUT_FOR_DELIVERY'], text: 'The seller hands the parcel over; the courier marks it out for delivery.'),
  (label: 'Delivered', by: 'You, with your code', statuses: ['DELIVERED', 'COMPLETED'], text: 'When the items are in your hands, give the courier your 6-digit code. That confirms delivery and releases the payment to the seller.'),
];
const _subStatus = {'READY_FOR_SHIPMENT': 'Packed, waiting for pickup', 'OUT_FOR_DELIVERY': 'Out for delivery today', 'PROCESSING': 'Being prepared', 'SHIPPED': 'Handed to the courier'};
const _reasons = [
  ('Product not received', 'ITEM_NOT_RECEIVED'),
  ('Wrong product', 'WRONG_ITEM'),
  ('Damaged product', 'DAMAGED_GOODS'),
  ('Missing item', 'INCOMPLETE_ORDER'),
  ('Other', 'OTHER'),
];
const _methodLabel = {'MOMO': 'MTN MoMo', 'AIRTEL': 'Airtel Money', 'CARD': 'Card', 'SPENN': 'SPENN', 'CASH_ON_DELIVERY': 'Cash on delivery'};

int _stepIndex(Map<String, dynamic> o) {
  if (o['paymentStatus'] == 'PENDING' && o['paymentMethod'] != 'CASH_ON_DELIVERY') return 0;
  final i = _steps.indexWhere((s) => s.statuses.contains(o['orderStatus']));
  return i < 1 ? 1 : i;
}

/// `/orders/:id` — status timeline, delivery code, cancel, review and report a
/// problem (`pages/OrderDetails.jsx`).
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String _loadError = '';
  ({bool ok, String text})? _notice;
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _cancelling = false;

  String _reason = '';
  final _description = TextEditingController();
  bool _reportBusy = false;

  /// This order's latest problem report, shown as a live case.
  String? _caseId;
  bool _caseOpen = false;

  String _reviewProduct = '';
  int _rating = 5;
  final _reviewText = TextEditingController();
  final _reviewed = <String>{};
  bool _reviewBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _findCase();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _order != null && paidCancelRemaining(_order!, _now) > Duration.zero) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _description.dispose();
    _reviewText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await OrdersApi.byId(widget.id);
      if (mounted) setState(() => _order = o);
    } catch (e) {
      if (mounted) setState(() => _loadError = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _closedCase = ['RESOLVED_BUYER_REFUNDED', 'RESOLVED_VENDOR_RELEASED', 'RESOLVED_SPLIT', 'REJECTED', 'WITHDRAWN'];

  Future<void> _findCase() async {
    try {
      final mine = (await DisputesApi.mine()).where((d) => idOf(d['order']) == widget.id || strOf(d['order']) == widget.id).toList()
        ..sort((a, b) => (parseDate(b['createdAt']) ?? DateTime(2000)).compareTo(parseDate(a['createdAt']) ?? DateTime(2000)));
      if (mine.isNotEmpty && mounted) {
        setState(() {
          _caseId = idOf(mine.first);
          _caseOpen = !_closedCase.contains(mine.first['status']);
        });
      }
    } catch (_) {
      // The order page still works without the case.
    }
  }

  String _productId(Map<String, dynamic> it) {
    final p = it['product'];
    return strOf(p is Map ? (p['_id'] ?? p['id']) : p);
  }

  Future<void> _cancel() async {
    final o = _order!;
    final paid = o['paymentStatus'] == 'PAID';
    final kpay = asMap(o['paidVia'])['gateway'] == 'KPAY' && ['CARD', 'SPENN'].contains(asMap(o['paidVia'])['method']);
    final backTo = kpay ? "you through K-Pay by MVEC's team" : (o['paymentMethod'] == 'CARD' ? 'the card you paid with' : 'your mobile money');
    if (!await confirmDialog(context, paid ? 'Cancel this order? Your payment is sent back to $backTo.' : 'Cancel this order?', confirm: 'Cancel order', danger: true)) return;
    setState(() {
      _cancelling = true;
      _notice = null;
    });
    try {
      final res = await OrdersApi.cancel(widget.id);
      setState(() {
        _order = {...o, ...asMap(res['order']), 'items': o['items']};
        _notice = (ok: true, text: strOf(res['message'], 'Order cancelled.'));
      });
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _report() async {
    final o = _order!;
    if (_reason.isEmpty || _description.text.trim().length < 10) {
      setState(() => _notice = (ok: false, text: 'Choose what went wrong and describe it in at least 10 characters.'));
      return;
    }
    setState(() {
      _reportBusy = true;
      _notice = null;
    });
    try {
      await DisputesApi.open(orderId: strOf(o['id']), reason: _reason, description: _description.text.trim(), amount: numOf(o['totalAmount']));
      setState(() {
        _order = {...o, 'paymentStatus': 'DISPUTED'};
        _notice = (ok: true, text: 'Your problem was reported. The seller and MVEC have been told, and the payment is on hold meanwhile.');
      });
      await _findCase();
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _reportBusy = false);
    }
  }

  Future<void> _review(List<Map<String, dynamic>> reviewable) async {
    final productId = _reviewProduct.isNotEmpty ? _reviewProduct : (reviewable.length == 1 ? _productId(reviewable.first) : '');
    if (productId.isEmpty) {
      setState(() => _notice = (ok: false, text: 'Choose the product you want to review.'));
      return;
    }
    if (_reviewText.text.trim().isEmpty) {
      setState(() => _notice = (ok: false, text: 'Write a few words about the product.'));
      return;
    }
    setState(() {
      _reviewBusy = true;
      _notice = null;
    });
    try {
      await CatalogApi.createReview(productId: productId, rating: _rating, text: _reviewText.text.trim());
      setState(() {
        _reviewed.add(productId);
        _reviewText.clear();
        _reviewProduct = '';
        _notice = (ok: true, text: 'Thanks for your review!');
      });
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _reviewBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    if (_loading) return const PageFrame(title: 'Order', fallback: '/orders', shopping: true, body: LoadingState(label: 'Loading order…'));
    final o = _order;
    if (o == null) {
      return PageFrame(title: 'Order', fallback: '/orders', shopping: true, body: PageList(children: [Notice(text: _loadError.isEmpty ? 'Order not found.' : _loadError), OutlineBtn(label: 'Back to orders', onPressed: () => context.go('/orders'))]));
    }
    final items = asMaps(o['items']);
    final cancelled = ['CANCELLED', 'REFUNDED'].contains(o['orderStatus']);
    final delivered = ['DELIVERED', 'COMPLETED'].contains(o['orderStatus']);
    final awaiting = isAwaitingPayment(o);
    final idx = _stepIndex(o);
    final addr = asMap(o['shippingAddress']);
    final isPickup = o['shippingMethod'] == 'PICKUP';
    final vendors = {for (final it in items) strOf(asMap(it['vendor'])['companyName'] ?? asMap(it['vendor'])['Fullname'])}..remove('');
    final reviewable = items.where((it) => _productId(it).isNotEmpty && !_reviewed.contains(_productId(it))).toList();
    final remaining = paidCancelRemaining(o, _now);
    final paidVia = asMap(o['paidVia']);
    final method = strOf(paidVia['method'], strOf(o['paymentMethod']));
    final methodText = paidVia['gateway'] == 'KPAY' ? 'K-Pay (${_methodLabel[method] ?? method})' : (_methodLabel[method] ?? method);
    final pickups = asMaps(o['pickupLocations']);
    final breakdown = asMaps(o['shippingBreakdown']);

    return PageFrame(
      title: 'Order details',
      fallback: '/orders',
      shopping: true,
      body: PageList(
        onRefresh: _load,
        children: [
          Text(strOf(o['orderNumber']), style: context.mvH1.copyWith(fontSize: 16)),
          const SizedBox(height: 2),
          Text('Placed ${formatDate(o['createdAt'])} · ${buyerStatus(o)}', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
          const SizedBox(height: 12),
          if (_notice != null) Notice(text: _notice!.text, ok: _notice!.ok),
          if (awaiting)
            InfoBox(
              title: 'Payment needed',
              text: 'This order is reserved for you but not paid yet. Unpaid orders are cancelled automatically 30 minutes after they are placed.',
              child: Row(children: [
                Expanded(child: GradientButton(label: 'Pay ${money(o['totalAmount'])}', compact: true, onPressed: () => context.push('/payment/${o['id']}'))),
                const SizedBox(width: 8),
                OutlineBtn(label: _cancelling ? 'Cancelling…' : 'Cancel', compact: true, danger: true, onPressed: _cancelling ? null : _cancel),
              ]),
            ),
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text('Items (${items.length})', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text))), StatusChip.of(strOf(o['orderStatus']), label: buyerStatus(o))]),
                const SizedBox(height: 8),
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      if (strOf(it['image']).isNotEmpty) Padding(padding: const EdgeInsets.only(right: 10), child: SizedBox(width: 46, height: 46, child: ProductImage(src: it['image'] as String?, radius: 8))),
                      Expanded(child: GestureDetector(onTap: _productId(it).isEmpty ? null : () => context.push('/product/${_productId(it)}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(strOf(it['name']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)), Text('Qty ${it['quantity']} × ${money(it['price'])}', style: TextStyle(color: mv.textMuted, fontSize: 11.5))]))),
                      Text(money(numOf(it['price']) * numOf(it['quantity'])), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                    ]),
                  ),
                const Divider(height: 18),
                SummaryRow('Products', money(o['subtotal'] ?? numOf(o['totalAmount']) - numOf(o['shippingFee']))),
                SummaryRow('${isPickup ? 'Pickup' : 'Delivery'}${o['shippingMethod'] == 'EXPRESS' ? ' (express)' : ''}${breakdown.length > 1 ? ' · ${breakdown.length} parcels' : ''}', numOf(o['shippingFee']) > 0 ? money(o['shippingFee']) : 'FREE'),
                if (!isPickup) for (final p in breakdown.where((p) => strOf(p['eta']).isNotEmpty)) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${strOf(p['storeName'], 'Seller')} · arrives in ${p['eta']}', style: TextStyle(color: mv.textMuted, fontSize: 11))),
                if (numOf(o['discountAmount']) > 0) SummaryRow('Coupon ${asMap(o['coupon'])['code'] ?? ''}', '−${money(o['discountAmount'])}'),
                SummaryRow('Total', money(o['totalAmount']), bold: true),
              ],
            ),
          ),
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isPickup ? 'Pickup' : 'Delivery', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                const SizedBox(height: 6),
                if (strOf(asMap(o['recipient'])['name']).isNotEmpty) Text(strOf(asMap(o['recipient'])['name']), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                if (strOf(asMap(o['recipient'])['phone']).isNotEmpty) Text(strOf(asMap(o['recipient'])['phone']), style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                if (isPickup) ...[
                  Text('You collect this order from the seller.', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                  for (final p in pickups) Text('${strOf(p['storeName'])}: ${strOf(p['address'])}${strOf(p['phone']).isEmpty ? '' : ' · ${p['phone']}'}', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                ] else ...[
                  Text([addr['street'], addr['sector'], addr['city']].where((e) => strOf(e).isNotEmpty).join(', '), style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                  Text([addr['province'] ?? addr['state'], addr['country']].where((e) => strOf(e).isNotEmpty).join(', '), style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                ],
                const SizedBox(height: 12),
                Text('Seller & payment', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                const SizedBox(height: 6),
                Text(vendors.isEmpty ? 'MVEC Seller' : vendors.join(', '), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                Text('Payment: ${o['paymentStatus'] == 'PAID' ? 'Paid${strOf(o['paidAt']).isEmpty ? '' : ' on ${formatDate(o['paidAt'])}'}' : buyerStatus(o)}', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                if (method.isNotEmpty && o['paymentStatus'] != 'PENDING') Text('Method: $methodText', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          if (remaining > Duration.zero && canCancel(o, _now))
            DataCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text('Changed your mind?', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text))), Text(countdown(remaining), style: TextStyle(fontWeight: FontWeight.w700, color: remaining < const Duration(minutes: 5) ? MvColors.errorText : mv.text))]),
                const SizedBox(height: 4),
                Text('You can cancel for a full refund until the timer ends or the seller ships.', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                const SizedBox(height: 10),
                OutlineBtn(label: _cancelling ? 'Cancelling…' : 'Cancel order', danger: true, compact: true, onPressed: _cancelling ? null : _cancel),
              ]),
            ),
          if (o['paymentStatus'] == 'PAID' && strOf(o['deliveryOtp']).isNotEmpty && !delivered && !cancelled)
            InfoBox(
              title: 'Your delivery code',
              text: '${isPickup ? 'When you collect your order, give this code to the seller only once the items are in your hands.' : 'Give this code to the seller or courier only when your order is in your hands.'} It releases your payment to the seller. It stays here on your order until delivery.',
              // Read digit by digit by screen readers; SelectableText alone isn't announced on the web.
              child: Semantics(
                label: 'Delivery code ${strOf(o['deliveryOtp']).split('').join(' ')}',
                child: ExcludeSemantics(child: SelectableText(strOf(o['deliveryOtp']), style: GoogleFontsSafe.code(mv.accentDeep))),
              ),
            ),
          if (cancelled)
            InfoBox(
              title: o['paymentStatus'] == 'REFUNDED' ? 'Order cancelled · full refund recorded' : 'Order cancelled',
              text: o['paymentStatus'] == 'REFUNDED'
                  ? (o['paymentMethod'] == 'CARD' ? 'Your full refund was sent back to the card you paid with. Banks usually show it within 5–10 working days.' : 'Your full refund was sent to the mobile money number you paid with. It usually arrives within minutes; you get an SMS when it does.')
                  : (o['cancellationReason'] == 'PAYMENT_TIMEOUT_EXPIRED_30_MIN' ? 'This order was not paid within 30 minutes, so it was cancelled. You were not charged.' : 'This order was cancelled before payment. You were not charged.'),
            ),
          if (!cancelled)
            DataCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progress', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                  Text('Who does what at each step. You get a notification every time it moves.', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _steps.length; i++)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(children: [
                            Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: i <= idx ? MvColors.skyBlue : Colors.transparent, border: Border.all(color: i <= idx ? MvColors.skyBlue : mv.border, width: 1.5))),
                            if (i < _steps.length - 1) Expanded(child: Container(width: 1.5, color: i < idx ? MvColors.skyBlue : mv.border)),
                          ]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_steps[i].label, style: TextStyle(fontWeight: i == idx ? FontWeight.w700 : FontWeight.w600, fontSize: 13, color: i <= idx ? mv.text : mv.textMuted)),
                                Text('${_steps[i].by}${i == idx ? ' · ${_subStatus[o['orderStatus']] ?? 'Current step'}' : (i < idx ? ' · Done' : '')}', style: TextStyle(color: mv.textMuted, fontSize: 11)),
                                if (i >= idx) Text(_steps[i].text, style: TextStyle(color: mv.textMuted, fontSize: 11.5, height: 1.35)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (delivered && reviewable.isNotEmpty)
            DataCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leave a review', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                  const SizedBox(height: 10),
                  if (reviewable.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _reviewProduct.isEmpty ? null : _reviewProduct,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Product'),
                      hint: const Text('Choose a product'),
                      items: [for (final it in reviewable) DropdownMenuItem(value: _productId(it), child: Text(strOf(it['name']), overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() => _reviewProduct = v ?? ''),
                    ),
                  Row(children: [for (var n = 1; n <= 5; n++) IconButton(onPressed: () => setState(() => _rating = n), tooltip: '$n star${n > 1 ? 's' : ''}', icon: Icon(n <= _rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF0A91A), size: 26))]),
                  TextField(controller: _reviewText, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(labelText: 'Your review', hintText: 'Tell other buyers about the product…')),
                  GradientButton(label: _reviewBusy ? 'Sending…' : 'Submit review', loading: _reviewBusy, compact: true, onPressed: () => _review(reviewable)),
                ],
              ),
            ),
          if (o['paymentStatus'] == 'PAID' && !cancelled && !_caseOpen)
            DataCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Report a problem', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                  const SizedBox(height: 4),
                  Text("Use this if something is wrong with your order. The seller's payment stays on hold while MVEC reviews it.", style: TextStyle(color: mv.textMuted, fontSize: 12)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _reason.isEmpty ? null : _reason,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'What went wrong?'),
                    hint: const Text('Choose a problem'),
                    items: [for (final r in _reasons) DropdownMenuItem(value: r.$2, child: Text(r.$1))],
                    onChanged: (v) => setState(() => _reason = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _description, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(labelText: 'Details', hintText: 'What did you receive, and what did you expect? (at least 10 characters)')),
                  OutlineBtn(label: _reportBusy ? 'Submitting…' : 'Report a problem', compact: true, onPressed: _reportBusy ? null : _report),
                ],
              ),
            ),
          if (_caseId != null)
            DataCard(child: DisputeCaseView(key: ValueKey(_caseId), caseId: _caseId!, onChanged: () {
              _findCase();
              _load();
            }))
          else if (o['paymentStatus'] == 'DISPUTED')
            InfoBox(title: 'Problem reported', text: 'MVEC support is reviewing this order. You can follow it under Refunds.', child: Align(alignment: Alignment.centerLeft, child: OutlineBtn(label: 'Open refunds', compact: true, onPressed: () => context.push('/buyer/refunds')))),
        ],
      ),
    );
  }
}

/// Monospace-ish style for the delivery code.
class GoogleFontsSafe {
  static TextStyle code(Color color) => TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]);
}
