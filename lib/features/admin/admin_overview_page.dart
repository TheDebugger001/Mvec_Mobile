import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'attention_queue.dart';

String _greeting() {
  final h = DateTime.now().toUtc().add(const Duration(hours: 2)).hour; // Kigali time
  return h < 12
      ? 'Good morning'
      : h < 18
      ? 'Good afternoon'
      : 'Good evening';
}

/// `/admin` — what needs doing, then how the marketplace is doing today.
class AdminOverviewPage extends ConsumerStatefulWidget {
  const AdminOverviewPage({super.key});

  @override
  ConsumerState<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends ConsumerState<AdminOverviewPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jget('/admin/overview'),
      jget('/admin/orders', {'page': 1, 'pageSize': 5}).catchError((_) => <String, dynamic>{}),
    ]);
    return (overview: asMap(r[0]['overview']), orders: asMaps(r[1]['data']));
  });
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _data.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider.select((a) => a.user));
    return PortalPage(
      eyebrow: 'Super admin dashboard',
      title: '${_greeting()}, ${user?.firstName ?? 'Administrator'}',
      subtitle: 'What needs doing first, then how the marketplace is doing today.',
      onRefresh: _data.reload,
      children: [
        const AttentionQueue(),
        LoadView(
          loader: _data,
          builder: (d) {
            final o = d.overview;
            final cats = asMaps(o['topCategories']);
            final maxCat = cats.fold<num>(1, (m, c) => numOf(c['products']) > m ? numOf(c['products']) : m);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Gross sales today', value: money(o['gmvToday']), sub: 'Paid orders today', icon: 'chart'),
                    MetricCard(label: 'Orders today', value: '${numOf(o['ordersToday']).toInt()}', sub: 'Placed in the last 24h', icon: 'cart'),
                    MetricCard(label: 'Users', value: '${numOf(o['totalUsers']).toInt()}', sub: 'Total registered accounts', icon: 'users'),
                    MetricCard(label: 'Vendors', value: '${numOf(o['totalVendors']).toInt()}', sub: 'Marketplace vendor accounts', icon: 'shop'),
                    MetricCard(label: 'Suppliers', value: '${numOf(o['totalSuppliers']).toInt()}', sub: 'Supplier accounts', icon: 'shop'),
                    MetricCard(label: 'Affiliates', value: '${numOf(o['totalAffiliates']).toInt()}', sub: 'Affiliate accounts', icon: 'users'),
                    MetricCard(label: 'Buyers', value: '${numOf(o['totalBuyers']).toInt()}', sub: 'Buyer accounts', icon: 'users'),
                    MetricCard(label: 'Total products', value: '${numOf(o['totalProducts']).toInt()}', sub: 'All catalog statuses', icon: 'box'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'Ikiguzi revenue',
                  subtitle: 'Platform commission earned across all vendors',
                  children: [
                    MetricGrid(
                      children: [
                        MetricCard(label: 'Commission earned', value: money(o['mvecRevenueToday']), sub: 'Today', icon: 'wallet'),
                        MetricCard(label: 'Orders total', value: '${numOf(o['totalOrders']).toInt()}', sub: 'All marketplace orders', icon: 'cart'),
                      ],
                    ),
                  ],
                ),
                Section(
                  title: 'Today',
                  subtitle: 'Live operational snapshot',
                  children: [
                    RecordCard(title: 'Orders on the way', amount: '${numOf(o['pendingDeliveries']).toInt()}', onTap: () => context.go('/admin/deliveries')),
                    RecordCard(title: 'Disputes under review', amount: '${numOf(o['pendingRefunds']).toInt()}', onTap: () => context.go('/admin/disputes')),
                    RecordCard(title: 'Full analytics', subtitle: 'Sales, top sellers and products, payment mix', onTap: () => context.go('/admin/analytics')),
                  ],
                ),
                Section(
                  title: 'Recent orders',
                  subtitle: 'Across all vendors',
                  trailing: TextButton(onPressed: () => context.go('/admin/orders'), child: const Text('View all')),
                  children: [
                    if (d.orders.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', message: 'Orders will appear here once buyers start checking out.'),
                    for (final x in d.orders)
                      RecordCard(
                        title: strOf(x['orderNumber']),
                        subtitle: personName(x['user'], 'Unknown buyer'),
                        amount: money(x['totalAmount']),
                        status: Pill(x['orderStatus']),
                        onTap: () => context.push('/admin/orders/${idOf(x)}'),
                      ),
                  ],
                ),
                Section(
                  title: 'Category health',
                  subtitle: 'Products by category',
                  trailing: TextButton(onPressed: () => context.go('/admin/categories'), child: const Text('Manage')),
                  children: [
                    if (cats.isEmpty) const EmptyState(icon: Icons.sell_outlined, title: 'No categories yet', message: 'Create categories to organize the catalog.'),
                    for (final c in cats) _Bar(label: strOf(c['name']), fraction: numOf(c['products']) / maxCat, value: '${numOf(c['products']).toInt()}'),
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

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.fraction, required this.value});
  final String label;
  final num fraction;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: fraction.toDouble().clamp(0, 1), minHeight: 8))),
        const SizedBox(width: 8),
        SizedBox(width: 44, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
      ],
    ),
  );
}

// ─── Users, products, categories, orders (GenericAdminTable) ────────────────
