import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../../../widgets/mv_icon.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_insights.dart';

/// Small money metric with a consistent icon and headline amount.
///
/// Same shape as `VendorFinanceMetric`, kept in the supplier module so the two
/// portals can tune their own finance surfaces independently.
class SupplierFinanceMetric extends StatelessWidget {
  const SupplierFinanceMetric({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    this.emphasis = false,
  });

  final String label;
  final num amount;
  final String icon;

  /// Draws the amount in the brand colour — used for the withdrawable balance.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: palette.soft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: MvIcon(icon, size: 18, color: palette.accentDeep),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: emphasis ? palette.accentDeep : palette.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One signed, dated movement on the supplier's reconciliable money ledger.
class SupplierLedgerTile extends StatelessWidget {
  const SupplierLedgerTile({super.key, required this.entry});

  final SupplierLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final tone =
        entry.isNeutral
            ? palette.textMuted
            : entry.isCredit
            ? MvColors.successText
            : MvColors.errorText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: MvIcon(entry.kind.icon, size: 17, color: tone),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            entry.isNeutral
                ? money(entry.amount)
                : '${entry.isCredit ? '+' : '−'}${money(entry.amount)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  /// Kind plus the order number when the row belongs to one, then the date.
  static String _subtitle(SupplierLedgerEntry entry) {
    final label =
        entry.orderNumber == null
            ? entry.kind.label
            : '${entry.kind.label} · ${entry.orderNumber}';
    return '$label · ${shortDateTime(entry.at)}';
  }
}

/// One withdrawal request, as shown on the Payments page.
class SupplierPayoutRow extends StatelessWidget {
  const SupplierPayoutRow({super.key, required this.payout});

  final SupplierPayoutRequest payout;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 18,
            color: MvColors.primaryDeep,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payout.method.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${shortDateTime(payout.requestedAt)} · ${payout.destination ?? 'Destination not recorded'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: palette.textMuted),
                ),
                if (payout.note != null)
                  Text(
                    payout.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(payout.amount),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              StatusChip(payout.status),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bar chart of net earnings over time. Dependency-free like the rest of the
/// chart set — no `fl_chart`.
class SupplierEarningsChart extends StatelessWidget {
  const SupplierEarningsChart({
    super.key,
    required this.series,
    this.height = 144,
  });

  final List<SupplierEarningsPoint> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return const SizedBox(
        height: 130,
        child: Center(child: Text('No earnings activity in this period.')),
      );
    }
    final maximum = series
        .map((point) => point.net.toDouble())
        .fold<double>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in series)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message:
                      '${shortDate(point.at)} · ${money(point.net)}'
                      '${point.units == 0 ? '' : ' · ${plural(point.units, 'unit')} shipped'}',
                  child: Container(
                    height: 16 + 105 * point.net.toDouble() / maximum,
                    decoration: BoxDecoration(
                      color:
                          point.net == 0
                              ? context.mv.surfaceMuted
                              : MvColors.primary.withValues(alpha: .72),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Star row for a buyer review.
class SupplierRatingStars extends StatelessWidget {
  const SupplierRatingStars({super.key, required this.rating, this.size = 14});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone =
        rating >= 4
            ? const Color(0xFFE9A33B)
            : rating >= 3
            ? MvColors.warningText
            : MvColors.errorText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Padding(
            padding: const EdgeInsets.only(right: 1),
            child: Icon(
              star <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: tone,
            ),
          ),
      ],
    );
  }
}

/// One buyer review card, with the supplier's public reply when there is one.
class SupplierReviewTile extends StatelessWidget {
  const SupplierReviewTile({super.key, required this.review});

  final SupplierReview review;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SupplierRatingStars(rating: review.rating),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.comment,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.text),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    shortDate(review.createdAt),
                    if (review.orderReference != null)
                      'Order ${review.orderReference}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                ),
              ),
              if (review.hasReply)
                Text(
                  'Replied',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: palette.accentDeep,
                  ),
                ),
            ],
          ),
          if (review.hasReply) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: palette.accentDeep, width: 3),
                ),
              ),
              child: Text(
                review.reply!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: palette.text,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The period selector shared by Analytics and Reports.
class SupplierRangeSelector extends StatelessWidget {
  const SupplierRangeSelector({
    super.key,
    required this.range,
    required this.onChanged,
  });

  final SupplierReportRange range;
  final ValueChanged<SupplierReportRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in SupplierReportRange.values)
          ChoiceChip(
            label: Text(option.shortLabel),
            selected: option == range,
            onSelected: (_) => onChanged(option),
            selectedColor: context.mv.accentDeep,
            labelStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: option == range ? context.mv.onAccent : context.mv.text,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }
}

/// Formats a period-over-period movement for a metric card.
String supplierDelta(num value) {
  final percent = (value * 100).toStringAsFixed(0);
  return '${value >= 0 ? '+' : ''}$percent%';
}

/// The colour a movement should be drawn in.
Color supplierDeltaColor(num value) =>
    value >= 0 ? MvColors.successText : MvColors.errorText;
