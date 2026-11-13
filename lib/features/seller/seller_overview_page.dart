import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/nav_items.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';

String _greeting() {
  final h = DateTime.now().hour;
  return h < 12
      ? 'Good morning'
      : h < 18
      ? 'Good afternoon'
      : 'Good evening';
}

/// `/vendor` — greeting, catalogue size, low stock and the latest orders.
class SellerOverviewPage extends ConsumerStatefulWidget {
  const SellerOverviewPage({super.key});

  @override
  ConsumerState<SellerOverviewPage> createState() => _SellerOverviewPageState();
}

class _SellerOverviewPageState extends ConsumerState<SellerOverviewPage> {
  late final _data = Loader(() async {
    final res = await Future.wait([vendorProducts().catchError((_) => <Map<String, dynamic>>[]), jlist('/orders/vendor/orders', 'orders').catchError((_) => <Map<String, dynamic>>[])]);
    return (products: res[0], orders: res[1].take(5).toList());
  });

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider.select((a) => a.user));
    return PortalPage(
      eyebrow: 'Seller platform',
      title: '${_greeting()}, ${user?.firstName ?? 'Seller'}',
      subtitle:
          user?.isStaff == true
              ? "You're working in ${user?.staffStoreName ?? 'the store'} as ${staffRoleLabel[user?.staffRole] ?? 'staff'}. Menus show what your role can access."
              : 'Everything you need to operate your Ikiguzi store.',
      onRefresh: _data.reload,
      children: [
        const OnboardingBanner(),
        LoadView(
          loader: _data,
          builder: (d) {
            final low = d.products.where((p) => numOf(p['stockQuantity']) <= numOf(p['lowStockThreshold'], 5)).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Products', value: '${d.products.length}', icon: 'box', sub: 'Published catalog'),
                    MetricCard(label: 'Low-stock items', value: '${low.length}', icon: 'bell', sub: 'Needs attention'),
                    MetricCard(label: 'Recent orders', value: '${d.orders.length}', icon: 'cart', sub: 'Latest activity'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'Inventory alerts',
                  subtitle: 'Reorder soon',
                  trailing: TextButton(onPressed: () => context.go('/vendor/inventory'), child: const Text('View all')),
                  children: [
                    if (low.isEmpty) const Tiny('No low-stock items right now.'),
                    for (final p in low.take(6)) RecordCard(title: strOf(p['name']), subtitle: '${p['stockQuantity']} units remaining', status: const StatusChip('Low stock', tone: StatusTone.warn)),
                  ],
                ),
                Section(
                  title: 'Recent orders',
                  subtitle: 'Latest customer activity',
                  trailing: TextButton(onPressed: () => context.go('/vendor/orders'), child: const Text('View all')),
                  children: [
                    if (d.orders.isEmpty) const Tiny('No orders yet.'),
                    for (final o in d.orders)
                      RecordCard(
                        title: strOf(o['orderNumber']),
                        subtitle: personName(o['user']),
                        amount: money(o['vendorSubtotal']),
                        status: Pill(o['orderStatus']),
                        onTap: () => context.push('/vendor/orders/${idOf(o)}'),
                      ),
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

// ─── Products ────────────────────────────────────────────────────────────────
