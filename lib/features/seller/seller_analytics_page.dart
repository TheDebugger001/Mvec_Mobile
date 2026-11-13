import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';
import 'vendor_data.dart';

const _channels = [('AFFILIATE', 'Affiliate referral'), ('COUPON', 'Coupon code'), ('MANUAL', 'Manual order'), ('ONLINE', 'Direct online')];

String _channelOf(Map<String, dynamic> o) =>
    strOf(o['affiliateCode']).isNotEmpty
        ? 'AFFILIATE'
        : strOf(asMap(o['coupon'])['code']).isNotEmpty
        ? 'COUPON'
        : o['source'] == 'MANUAL'
        ? 'MANUAL'
        : 'ONLINE';

/// `/vendor/analytics` — sales, channels, growth spend and top products.
class SellerAnalyticsPage extends StatefulWidget {
  const SellerAnalyticsPage({super.key});

  @override
  State<SellerAnalyticsPage> createState() => _SellerAnalyticsPageState();
}

class _SellerAnalyticsPageState extends State<SellerAnalyticsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([vendorData(), jlist('/vendor/advertisements', 'data').catchError((_) => <Map<String, dynamic>>[])]);
    return (vendor: r[0] as ({List<Map<String, dynamic>> orders, List<Map<String, dynamic>> products, double commission}), ads: r[1] as List<Map<String, dynamic>>);
  });

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      feature: 'advancedAnalytics',
      title: 'Advanced analytics',
      child: PortalPage(
        eyebrow: 'Seller platform',
        title: 'Analytics',
        subtitle: 'Sales performance across your orders and catalog.',
        onRefresh: _data.reload,
        children: [
          LoadView(
            loader: _data,
            builder: (d) {
              final v = d.vendor;
              final stats = summarizeOrders(v.orders, v.commission);
              final counted = v.orders.where(isRevenueOrder).toList();
              final totalSales = counted.fold<num>(0, (s, o) => s + numOf(o['vendorSubtotal']));
              final low = v.products.where((p) => numOf(p['stockQuantity']) <= numOf(p['lowStockThreshold'], 5)).length;
              final discount = counted.fold<num>(0, (s, o) => s + numOf(o['vendorDiscount']));
              final adSpend = d.ads.fold<num>(0, (s, a) => s + numOf(a['spent']));
              final adClicks = d.ads.fold<num>(0, (s, a) => s + numOf(a['clicks']));
              final liveAds = d.ads.where((a) => a['statusKey'] == 'ACTIVE').length;
              final byStatus = stats.byStatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      MetricCard(label: 'Gross sales', value: money(stats.gross), icon: 'chart', sub: '${stats.countedOrders} orders'),
                      MetricCard(label: 'Average order', value: money(stats.averageOrder), icon: 'cart', sub: 'Your items per order'),
                      MetricCard(label: 'Customers', value: '${stats.customers}', icon: 'users', sub: 'Unique buyers'),
                      MetricCard(label: 'Active products', value: '${v.products.where((p) => p['status'] == 'ACTIVE').length}', icon: 'box', sub: '$low low on stock'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Section(title: 'Revenue', subtitle: 'Last 6 months, excluding cancelled orders', children: [MiniBars(data: monthlyRevenue(v.orders))]),
                  Section(
                    title: 'Orders by status',
                    subtitle: '${stats.orders} total',
                    children: [
                      if (byStatus.isEmpty) const Tiny('No orders yet.'),
                      for (final e in byStatus) ProgressRow(label: titleCase(e.key), fraction: e.value / stats.orders, value: '${e.value}'),
                    ],
                  ),
                  Section(
                    title: 'Sales by channel',
                    subtitle: 'Where your orders come from',
                    children: [
                      for (final (k, label) in _channels)
                        Builder(
                          builder: (_) {
                            final list = counted.where((o) => _channelOf(o) == k).toList();
                            final sales = list.fold<num>(0, (s, o) => s + numOf(o['vendorSubtotal']));
                            final share = totalSales == 0 ? 0.0 : sales / totalSales;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [ProgressRow(label: label, fraction: share.toDouble(), value: '${(share * 100).round()}%'), Tiny('${money(sales)} · ${list.length} orders')],
                            );
                          },
                        ),
                    ],
                  ),
                  Section(
                    title: 'Growth spend',
                    subtitle: 'What marketing cost you',
                    trailing: TextButton(onPressed: () => context.go('/vendor/advertisements'), child: const Text('Ads')),
                    children: [
                      RecordCard(title: 'Coupon discounts', subtitle: 'Given on your items', amount: money(discount)),
                      RecordCard(title: 'Ad spend', subtitle: '${compact(adClicks)} clicks · $liveAds live campaign${liveAds == 1 ? '' : 's'}', amount: money(adSpend)),
                      RecordCard(title: 'Affiliate commission', subtitle: 'Paid by Ikiguzi, not you', amount: money(0)),
                    ],
                  ),
                  Section(
                    title: 'Top products',
                    subtitle: 'By revenue',
                    trailing: TextButton(onPressed: () => context.go('/vendor/products'), child: const Text('Manage')),
                    children: [
                      if (stats.topProducts.isEmpty) const Tiny('Sales by product will appear after your first order.'),
                      for (final p in stats.topProducts.take(6)) RecordCard(title: p.name, subtitle: '${p.units} units sold', amount: money(p.revenue)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
