import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/common.dart';
import '../models/supplier_insights.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_finance_widgets.dart';

/// Trend reporting for the supplier's wholesale business: revenue and volume
/// over the selected period, the categories that drive it, and the catalogue
/// lines moving the most units.
class SupplierAnalyticsScreen extends ConsumerStatefulWidget {
  const SupplierAnalyticsScreen({super.key});

  @override
  ConsumerState<SupplierAnalyticsScreen> createState() =>
      _SupplierAnalyticsScreenState();
}

class _SupplierAnalyticsScreenState
    extends ConsumerState<SupplierAnalyticsScreen> {
  SupplierReportRange _range = SupplierReportRange.last30Days;

  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(supplierAnalyticsProvider(_range));
    final module = ref.watch(supplierFinanceModuleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'ANALYTICS',
          title: 'Wholesale performance',
          subtitle:
              'How your catalogue performed against vendor orders, after MVEC '
              'takes its wholesale commission.',
          actions: [
            SupplierRangeSelector(
              range: _range,
              onChanged: (value) => setState(() => _range = value),
            ),
          ],
        ),
        if (module.fallbackReason != null) ...[
          InfoBox(module.fallbackReason!, icon: 'bell'),
          const SizedBox(height: 14),
        ],
        switch (analyticsAsync) {
          AsyncLoading() => const SizedBox(height: 240, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierAnalyticsProvider(_range)),
          ),
          AsyncData(:final value) => _snapshot(context, value),
          _ => const SizedBox(height: 240, child: LoadingState()),
        },
      ],
    );
  }

  Widget _snapshot(BuildContext context, SupplierAnalyticsSnapshot value) {
    if (value.isEmpty) {
      return DataCard(
        title: 'No activity in ${value.range.label.toLowerCase()}',
        child: EmptyState(
          message:
              'No wholesale orders were billed in this period. Widen the range '
              'to see earlier activity.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 720 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in _metrics(value))
                  SizedBox(width: width, child: metric),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Net earnings · ${value.range.label.toLowerCase()}',
          subtitle:
              'Commission deducted: ${money(value.commission)} · '
              '${plural(value.unitsSold, 'unit')} shipped',
          trailing: Text(
            supplierDelta(value.earningsDelta),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: supplierDeltaColor(value.earningsDelta),
            ),
          ),
          child: SupplierEarningsChart(series: value.series, height: 170),
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Revenue by category',
          subtitle: 'Net revenue share for the selected period.',
          child:
              value.categories.isEmpty
                  ? const EmptyState(message: 'No category revenue yet.')
                  : Column(
                    children: [
                      for (final category in value.categories)
                        ProgressRow(
                          label: category.category,
                          percent: category.percent,
                          count: '${category.percent.toStringAsFixed(0)}%',
                        ),
                    ],
                  ),
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Top moving products',
          subtitle: 'Ranked by units shipped in this period.',
          child:
              value.topProducts.isEmpty
                  ? const EmptyState(message: 'No products shipped yet.')
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final product in value.topProducts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      product.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: context.mv.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                plural(product.units, 'unit'),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                money(product.revenue),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
        ),
      ],
    );
  }

  List<Widget> _metrics(SupplierAnalyticsSnapshot value) => [
    MetricCard(
      label: 'Net earnings',
      value: money(value.netEarnings),
      delta: '${supplierDelta(value.earningsDelta)} vs previous period',
      deltaColor: supplierDeltaColor(value.earningsDelta),
      icon: 'wallet',
    ),
    MetricCard(
      label: 'Gross sales',
      value: money(value.grossSales),
      delta: '${supplierDelta(value.salesDelta)} vs previous period',
      deltaColor: supplierDeltaColor(value.salesDelta),
      icon: 'chart',
    ),
    MetricCard(
      label: 'Orders filled',
      value: numFmt(value.orderCount),
      delta: '${supplierDelta(value.orderDelta)} vs previous period',
      deltaColor: supplierDeltaColor(value.orderDelta),
      icon: 'cart',
    ),
    MetricCard(
      label: 'Kept per order',
      value: money(value.averageOrderValue),
      delta: '${plural(value.unitsSold, 'unit')} shipped',
      icon: 'box',
    ),
  ];
}
