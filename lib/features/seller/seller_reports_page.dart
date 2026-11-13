import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';
import 'vendor_data.dart';

const _reportRanges = [('7', 'Last 7 days'), ('30', 'Last 30 days'), ('90', 'Last 90 days'), ('365', 'Last 12 months'), ('all', 'All time')];

/// `/vendor/reports` — sales summary for a period with the order list.
class SellerReportsPage extends StatefulWidget {
  const SellerReportsPage({super.key});

  @override
  State<SellerReportsPage> createState() => _SellerReportsPageState();
}

class _SellerReportsPageState extends State<SellerReportsPage> {
  late final _data = Loader(vendorData);
  String _range = '30';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      feature: 'advancedAnalytics',
      title: 'Advanced reports',
      child: PortalPage(
        eyebrow: 'Seller platform',
        title: 'Reports',
        subtitle: 'Sales summary for a chosen period, with every order in it.',
        onRefresh: _data.reload,
        action: FilterSelect(label: 'Report period', value: _range, options: _reportRanges, onChanged: (v) => setState(() => _range = v)),
        children: [
          LoadView(
            loader: _data,
            builder: (d) {
              final since = _range == 'all' ? null : DateTime.now().subtract(Duration(days: int.parse(_range)));
              final orders = since == null ? d.orders : d.orders.where((o) => (parseDate(o['createdAt']) ?? DateTime(2000)).isAfter(since)).toList();
              final s = summarizeOrders(orders, d.commission);
              final shown = orders.where((o) => matches(_q, [o['orderNumber'], personName(o['user'])])).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      MetricCard(label: 'Gross sales', value: money(s.gross), icon: 'chart', sub: '${s.countedOrders} orders'),
                      MetricCard(label: 'Paid sales', value: money(s.paidGross), icon: 'wallet', sub: '${s.paidOrders} paid orders'),
                      MetricCard(label: 'Platform fee (${d.commission.toStringAsFixed(d.commission % 1 == 0 ? 0 : 1)}%)', value: money(s.commission), icon: 'tag', sub: 'On paid sales'),
                      MetricCard(label: 'Net earnings', value: money(s.net), icon: 'check', sub: 'Paid sales after fee'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SearchBox(hint: 'Search orders…', onChanged: (v) => setState(() => _q = v)),
                  Paged<Map<String, dynamic>>(
                    items: shown,
                    empty: const EmptyState(title: 'No orders in this period.'),
                    itemBuilder:
                        (o) => RecordCard(
                          title: strOf(o['orderNumber']),
                          subtitle: '${personName(o['user'])} · ${formatDate(o['createdAt'])}',
                          lines: ['Payment: ${titleCase(o['paymentStatus'])}'],
                          amount: money(o['vendorSubtotal']),
                          status: Pill(o['orderStatus']),
                          onTap: () => context.push('/vendor/orders/${idOf(o)}'),
                        ),
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

// ─── Customers ───────────────────────────────────────────────────────────────
