import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/commerce_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/order_rules.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// `/orders` — the buyer's purchases (`pages/Orders.jsx`).
class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String _error = '';
  String _message = '';
  String _busyId = '';
  String _q = '';
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _orders.any((o) => paidCancelRemaining(o, _now) > Duration.zero)) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await OrdersApi.mine();
      if (mounted) {
        setState(() {
          _orders = list;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> o) async {
    final paid = o['paymentStatus'] == 'PAID';
    final backTo = o['paymentMethod'] == 'CARD' ? 'the card you paid with' : 'your mobile money';
    if (!await confirmDialog(context, paid ? 'Cancel this order? Your payment is sent back to $backTo.' : 'Cancel this order?', confirm: 'Cancel order', danger: true)) return;
    setState(() {
      _busyId = strOf(o['id']);
      _error = '';
      _message = '';
    });
    try {
      final res = await OrdersApi.cancel(strOf(o['id']));
      setState(() {
        _orders = [for (final x in _orders) x['id'] == o['id'] ? asMap(res['order']) : x];
        _message = strOf(res['message'], 'Order cancelled.');
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busyId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final needle = _q.trim().toLowerCase();
    final shown = needle.isEmpty
        ? _orders
        : _orders.where((o) => [o['orderNumber'], buyerStatus(o), ...asMaps(o['items']).map((i) => i['name'])].join(' ').toLowerCase().contains(needle)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          const PageTitle(eyebrow: 'Purchases', title: 'My orders', subtitle: 'Track payment, delivery and protected settlement from one place.'),
          if (_message.isNotEmpty) Notice(text: _message, ok: true, onClose: () => setState(() => _message = '')),
          if (_error.isNotEmpty) Notice(text: _error),
          if (_loading) const LoadingState(label: 'Loading your orders…'),
          if (!_loading && _orders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(onChanged: (v) => setState(() => _q = v), decoration: const InputDecoration(hintText: 'Search by order number, product or status…', prefixIcon: Icon(Icons.search_rounded, size: 20), isDense: true)),
            ),
          if (!_loading && _orders.isEmpty && _error.isEmpty)
            EmptyState(icon: Icons.inventory_2_outlined, title: 'No orders yet', message: 'Once you check out, your orders will show up here.', action: GradientButton(label: 'Start shopping', compact: true, onPressed: () => context.go('/shop'))),
          if (_orders.isNotEmpty && shown.isEmpty) const EmptyState(title: 'No matching orders'),
          for (final o in shown) _OrderRow(order: o, now: _now, busy: _busyId == strOf(o['id']), onCancel: () => _cancel(o)),
          if (_orders.isNotEmpty) const InfoBox(title: 'Protected payment & delivery', text: 'MVEC holds your payment until you confirm delivery with your code. You can cancel within 30 minutes of paying, before the seller ships. Unpaid orders are cancelled automatically after 30 minutes.'),
          if (!_loading) Padding(padding: const EdgeInsets.only(top: 4), child: GradientButton(label: 'Continue shopping', expand: true, onPressed: () => context.go('/shop'))),
          SizedBox(height: mv.page == Colors.transparent ? 0 : 0),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.now, required this.busy, required this.onCancel});
  final Map<String, dynamic> order;
  final DateTime now;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final o = order;
    final items = asMaps(o['items']);
    final remaining = paidCancelRemaining(o, now);
    final id = strOf(o['id']);
    final awaiting = isAwaitingPayment(o);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/orders/$id'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(strOf(o['orderNumber']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: mv.text, fontSize: 12.5))),
                  const SizedBox(width: 8),
                  StatusChip.of(awaiting ? 'PENDING' : strOf(o['orderStatus']), label: buyerStatus(o)),
                ],
              ),
              const SizedBox(height: 4),
              Text(formatDate(o['createdAt']), style: TextStyle(color: mv.textMuted, fontSize: 11)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (items.isNotEmpty && strOf(items.first['image']).isNotEmpty) Padding(padding: const EdgeInsets.only(right: 10), child: SizedBox(width: 44, height: 44, child: ProductImage(src: items.first['image'] as String?, radius: 8))),
                  Expanded(child: Text('${items.isEmpty ? 'Order' : strOf(items.first['name'], 'Order')}${items.length > 1 ? ' + ${items.length - 1} more' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                  Text(money(o['totalAmount']), style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w700, fontSize: 13.5)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (awaiting) GradientButton(label: 'Pay now', compact: true, onPressed: () => context.push('/payment/$id')),
                  if (remaining > Duration.zero) Text('Cancel within ${countdown(remaining)}', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                  if (canCancel(o, now)) OutlineBtn(label: busy ? 'Cancelling…' : 'Cancel', compact: true, danger: true, onPressed: busy ? null : onCancel),
                  TextButton(onPressed: () => context.push('/orders/$id'), child: const Text('Details')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
