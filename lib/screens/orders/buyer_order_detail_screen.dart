import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/utils/app_theme.dart';

class BuyerOrderDetailScreen extends StatefulWidget {
  const BuyerOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<BuyerOrderDetailScreen> createState() => _BuyerOrderDetailScreenState();
}

class _BuyerOrderDetailScreenState extends State<BuyerOrderDetailScreen> {
  static const _window = Duration(minutes: 30);
  Map<String, dynamic>? _order;
  Object? _error;
  Timer? _timer;
  DateTime _now = DateTime.now();
  bool _cancelling = false;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _ticks++;
      final paymentStatus = '${_order?['paymentStatus'] ?? ''}'.toUpperCase();
      if (_ticks % 5 == 0 && !{'PAID', 'CONFIRMED'}.contains(paymentStatus)) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await ApiClient.instance.get('/orders/${widget.orderId}');
      final order = singleJson(response, ['order']);
      if (mounted) setState(() { _order = order; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _cancelOrder() async {
    setState(() => _cancelling = true);
    try {
      await ApiClient.instance.post('/orders/${widget.orderId}/cancel');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled and refund recorded.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel order: $error')),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
      body: _error != null && order == null
          ? Center(child: Text('Could not load this order: $_error'))
          : order == null
              ? const Center(child: CircularProgressIndicator())
              : _buildOrder(context, order),
    );
  }

  Widget _buildOrder(BuildContext context, Map<String, dynamic> order) {
    final createdAt = DateTime.tryParse('${order['createdAt'] ?? ''}')?.toLocal();
    final deadline = createdAt?.add(_window);
    final remaining = deadline == null ? Duration.zero : deadline.difference(_now);
    final status = '${order['orderStatus'] ?? 'PENDING'}'.toUpperCase();
    final paymentStatus = '${order['paymentStatus'] ?? 'PENDING'}'.toUpperCase();
    final paid = paymentStatus == 'PAID' || paymentStatus == 'CONFIRMED';
    final canCancel = paid && remaining > Duration.zero &&
        !{'CANCELLED', 'REFUNDED', 'COMPLETED', 'DELIVERED', 'RETURNED'}.contains(status);
    final items = order['items'] is List ? order['items'] as List : const [];
    final total = order['totalAmount'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: ListTile(
          title: Text('Order #${order['orderNumber'] ?? widget.orderId}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Status: $status · Payment: $paymentStatus'),
        )),
        const SizedBox(height: 12),
        if (paid && canCancel) ...[
          Card(
            color: context.mv.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('You can cancel this order within: ${_format(remaining)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: OutlinedButton(
                  onPressed: _cancelling ? null : _cancelOrder,
                  child: _cancelling
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Cancel Order'),
                )),
              ]),
            ),
          ),
        ] else if (paid && remaining <= Duration.zero && status != 'CANCELLED')
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Cancellation window expired. Order is now being processed for delivery.'),
          )),
        const SizedBox(height: 8),
        for (final raw in items)
          if (raw is Map)
            Card(child: ListTile(
              title: Text('${raw['name'] ?? 'Item'}'),
              subtitle: Text('Quantity: ${raw['quantity'] ?? 1}'),
              trailing: Text('RWF ${raw['price'] ?? ''}'),
            )),
        ListTile(
          title: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: Text('RWF ${total ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (!paid)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Approve the Mobile Money prompt to complete payment.'),
          ),
      ],
    );
  }

  String _format(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, _window.inSeconds);
    final minutesPart = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }
}
