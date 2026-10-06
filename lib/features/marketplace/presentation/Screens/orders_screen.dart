import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/theme.dart';
import '../../../../core/utils/app_theme.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Orders', style: AppTextStyles.headline(context)),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Past'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _OrdersList(activeOnly: true),
                _OrdersList(activeOnly: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersList extends StatefulWidget {
  const _OrdersList({required this.activeOnly});

  final bool activeOnly;

  @override
  State<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<_OrdersList> {
  late Future<_OrdersResult> _orders;

  @override
  void initState() {
    super.initState();
    _orders = _loadOrders();
  }

  Future<_OrdersResult> _loadOrders() async {
    if (await ApiClient.readToken() == null) {
      return const _OrdersResult(signedIn: false, orders: []);
    }
    final response = await ApiClient.instance.get('/orders/my-orders');
    return _OrdersResult(
      signedIn: true,
      orders: listJson(response, ['orders']),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OrdersResult>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessageState(
            icon: Icons.cloud_off_outlined,
            message: 'Could not load orders.',
            action: TextButton(
              onPressed: () => setState(() => _orders = _loadOrders()),
              child: const Text('Retry'),
            ),
          );
        }
        final result = snapshot.data!;
        if (!result.signedIn) {
          return const _MessageState(
            icon: Icons.lock_outline,
            message: 'Sign in to see your orders.',
          );
        }
        final orders = result.orders.where((order) {
          final status = '${order['orderStatus'] ?? 'PENDING'}'.toUpperCase();
          final isPast = status == 'DELIVERED' ||
              status == 'COMPLETED' ||
              status == 'CANCELLED';
          return widget.activeOnly ? !isPast : isPast;
        }).toList();
        if (orders.isEmpty) {
          return _MessageState(
            icon: Icons.receipt_long_outlined,
            message: widget.activeOnly
                ? 'No active orders'
                : 'No past orders yet',
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _OrderTile(order: orders[index]),
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    final refreshed = _loadOrders();
    setState(() => _orders = refreshed);
    await refreshed;
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final orderNumber = '${order['orderNumber'] ?? 'Order'}';
    final status = '${order['orderStatus'] ?? 'PENDING'}'
        .replaceAll('_', ' ')
        .toLowerCase();
    final total = order['totalAmount'];
    final amount = total is num ? total.toStringAsFixed(0) : '$total';
    final createdAt = DateTime.tryParse('${order['createdAt'] ?? ''}');
    final itemCount = order['items'] is List
        ? (order['items'] as List).fold<int>(0, (sum, item) {
            if (item is Map && item['quantity'] is num) {
              return sum + (item['quantity'] as num).toInt();
            }
            return sum;
          })
        : 0;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(orderNumber),
        subtitle: Text(
          '$itemCount item${itemCount == 1 ? '' : 's'} · '
          '${createdAt == null ? '' : '${createdAt.toLocal().toString().split(' ').first} · '}$status',
        ),
        trailing: Text(
          '$amount RWF',
          style: AppTextStyles.price(context),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: context.mv.textMuted, size: 56),
          const SizedBox(height: 12),
          Text(message, style: AppTextStyles.title(context)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _OrdersResult {
  const _OrdersResult({required this.signedIn, required this.orders});

  final bool signedIn;
  final List<Map<String, dynamic>> orders;
}
