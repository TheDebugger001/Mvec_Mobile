import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/utils.dart';
import '../../../../core/utils/app_theme.dart';
import '../../../../models/catalog.dart';
import '../../../../providers/admin_providers.dart';
import '../../../../widgets/common.dart';

/// Orders tab: current (active) and previous orders.
///
/// Backed by `GET /api/orders`, which the API scopes to the signed-in shopper.
/// Orders with no status yet are treated as active so a fresh order is not hidden.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  /// Statuses that count as an in-flight order. Anything else (delivered,
  /// cancelled, refunded) belongs under Past.
  static const Set<String> _activeStatuses = <String>{
    'PENDING',
    'CONFIRMED',
    'PROCESSING',
    'PACKED',
    'SHIPPED',
    'OUT_FOR_DELIVERY',
    'ASSIGNED',
    'ON_THE_WAY',
  };

  static bool isActive(OrderRecord order) {
    final status = (order.status ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (status.isEmpty) return true;
    return _activeStatuses.contains(status);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);
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
          Expanded(
            child: switch (ordersAsync) {
              AsyncLoading() => const Center(child: LoadingState()),
              AsyncError(:final error) => Center(
                child: ErrorState(
                  message: friendlyError(error),
                  onRetry: () => ref.invalidate(myOrdersProvider),
                ),
              ),
              AsyncData(:final value) => TabBarView(
                children: [
                  _OrdersList(
                    orders: value.where(isActive).toList(),
                    activeOnly: true,
                    onRetry: () => ref.invalidate(myOrdersProvider),
                  ),
                  _OrdersList(
                    orders: value.where((o) => !isActive(o)).toList(),
                    activeOnly: false,
                    onRetry: () => ref.invalidate(myOrdersProvider),
                  ),
                ],
              ),
              _ => const Center(child: LoadingState()),
            },
          ),
        ],
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.activeOnly,
    required this.onRetry,
  });

  final List<OrderRecord> orders;
  final bool activeOnly;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: context.mv.textMuted,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              activeOnly ? 'No active orders' : 'No past orders yet',
              style: AppTextStyles.title(context),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Refresh')),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _OrderCard(order: orders[index]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final OrderRecord order;

  @override
  Widget build(BuildContext context) {
    final status = (order.status ?? 'Unknown').trim();
    final statusColor = switch (status.toUpperCase()) {
      'DELIVERED' => AppColors.success,
      'CANCELLED' || 'REFUNDED' => AppColors.error,
      _ => AppColors.warning,
    };
    final items = order.itemsCount ?? order.raw?['itemsCount'];
    final placed = order.createdAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.orderNumber == null ? 'Order' : '#${order.orderNumber}',
                  style: AppTextStyles.title(context).copyWith(fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  color: context.mv.textMuted,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  placed == null ? 'Date unavailable' : shortDate(placed),
                  style: AppTextStyles.caption(context),
                ),
                const Spacer(),
                Text(
                  order.total == null ? '—' : money(order.total!),
                  style: AppTextStyles.price(context).copyWith(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              items == null ? 'View details' : '$items item(s) · View details',
              style: AppTextStyles.bodySecondary(context).copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}