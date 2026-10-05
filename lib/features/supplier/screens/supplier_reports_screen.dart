import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils.dart';
import '../../../widgets/charts.dart';
import '../../../widgets/common.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_insights.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_finance_widgets.dart';

/// A shareable summary of the supplier's period: what was billed, what MVEC
/// took, what is still held, what has been withdrawn, and how the money splits
/// across categories.
///
/// Composed from the same analytics snapshot and payout list the Analytics and
/// Payments pages use, so the three cannot report different totals.
class SupplierReportsScreen extends ConsumerStatefulWidget {
  const SupplierReportsScreen({super.key});

  @override
  ConsumerState<SupplierReportsScreen> createState() =>
      _SupplierReportsScreenState();
}

class _SupplierReportsScreenState extends ConsumerState<SupplierReportsScreen> {
  SupplierReportRange _range = SupplierReportRange.last30Days;

  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(supplierAnalyticsProvider(_range));
    final summaryAsync = ref.watch(supplierFinanceSummaryProvider);
    final payoutsAsync = ref.watch(supplierPayoutsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'REPORTS',
          title: 'Settlement report',
          subtitle:
              'A period summary you can copy and share with your accountant.',
          actions: [
            SupplierRangeSelector(
              range: _range,
              onChanged: (value) => setState(() => _range = value),
            ),
            OutlineMvButton(
              label: 'Copy report',
              icon: 'copy',
              onPressed:
                  analyticsAsync.valueOrNull == null
                      ? null
                      : () => copyToClipboard(
                        context,
                        _asText(
                          analyticsAsync.valueOrNull!,
                          summaryAsync.valueOrNull,
                          payoutsAsync.valueOrNull ?? const [],
                        ),
                      ),
            ),
          ],
        ),
        switch (analyticsAsync) {
          AsyncLoading() => const SizedBox(height: 240, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierAnalyticsProvider(_range)),
          ),
          AsyncData(:final value) => _report(
            context,
            value,
            summaryAsync.valueOrNull,
            payoutsAsync.valueOrNull ?? const <SupplierPayoutRequest>[],
          ),
          _ => const SizedBox(height: 240, child: LoadingState()),
        },
      ],
    );
  }

  Widget _report(
    BuildContext context,
    SupplierAnalyticsSnapshot analytics,
    SupplierFinanceSummary? summary,
    List<SupplierPayoutRequest> payouts,
  ) {
    final withdrawn = payouts.fold<num>(0, (sum, p) => sum + p.amount);
    final pending = payouts
        .where((p) => p.isPending)
        .fold<num>(0, (sum, p) => sum + p.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataCard(
          title: 'Period summary · ${analytics.range.label}',
          subtitle:
              '${plural(analytics.orderCount, 'order')} · '
              '${plural(analytics.unitsSold, 'unit')} shipped',
          child: KeyValueGrid(
            entries: [
              MapEntry('Gross sales', money(analytics.grossSales)),
              MapEntry('MVEC commission', '− ${money(analytics.commission)}'),
              MapEntry('Net earnings', money(analytics.netEarnings)),
              MapEntry('Kept per order', money(analytics.averageOrderValue)),
              MapEntry('Held in escrow', money(summary?.escrowHeld ?? 0)),
              MapEntry(
                'Available to withdraw',
                money(summary?.availablePayout ?? 0),
              ),
              MapEntry('Withdrawals requested', money(withdrawn)),
              MapEntry('Still processing', money(pending)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Revenue by category',
          subtitle: 'Net revenue share for the period.',
          child:
              analytics.categories.isEmpty
                  ? const EmptyState(
                    message: 'No category revenue in this period.',
                  )
                  : Column(
                    children: [
                      for (final category in analytics.categories)
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
          title: 'Withdrawal history',
          subtitle:
              '${plural(payouts.length, 'request')} · ${money(pending)} still '
              'processing.',
          child:
              payouts.isEmpty
                  ? const EmptyState(
                    message: 'No payout requests on this account yet.',
                  )
                  : Column(
                    children: [
                      for (final payout in payouts)
                        SupplierPayoutRow(payout: payout),
                    ],
                  ),
        ),
        const SizedBox(height: 14),
        InfoBox(
          'This report is generated from the ledger on your account. Order '
          'values appear once a vendor order is accepted, and escrow is '
          'released once delivery is confirmed.',
          icon: 'chart',
        ),
      ],
    );
  }

  /// Plain-text version for the clipboard, in the same order as the cards.
  static String _asText(
    SupplierAnalyticsSnapshot analytics,
    SupplierFinanceSummary? summary,
    List<SupplierPayoutRequest> payouts,
  ) {
    final buffer =
        StringBuffer()
          ..writeln('MVEC supplier settlement report')
          ..writeln(analytics.range.label)
          ..writeln()
          ..writeln('Gross sales: ${money(analytics.grossSales)}')
          ..writeln('MVEC commission: − ${money(analytics.commission)}')
          ..writeln('Net earnings: ${money(analytics.netEarnings)}')
          ..writeln('Orders filled: ${analytics.orderCount}')
          ..writeln('Units shipped: ${analytics.unitsSold}')
          ..writeln('Kept per order: ${money(analytics.averageOrderValue)}')
          ..writeln('Held in escrow: ${money(summary?.escrowHeld ?? 0)}')
          ..writeln(
            'Available to withdraw: ${money(summary?.availablePayout ?? 0)}',
          );
    if (analytics.categories.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Revenue by category');
      for (final category in analytics.categories) {
        buffer.writeln(
          '- ${category.category}: ${money(category.revenue)} '
          '(${category.percent.toStringAsFixed(0)}%)',
        );
      }
    }
    if (payouts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Withdrawals');
      for (final payout in payouts) {
        buffer.writeln(
          '- ${shortDate(payout.requestedAt)} · ${money(payout.amount)} · '
          '${payout.method.label} · ${titleCase(payout.status)}',
        );
      }
    }
    return buffer.toString();
  }
}
