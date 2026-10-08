/// Insight domain for the supplier "Finance & Insights" module: the trend
/// reporting behind Analytics and Reports, and the buyer feedback behind
/// Reviews.
///
/// The supplier-scoped analytics and review API response shapes.
library;

import '../../../models/user.dart';
import 'supplier_finance.dart';

/// The period selector shared by Analytics and Reports.
enum SupplierReportRange {
  last30Days,
  last3Months,
  lastYear;

  String get slug => switch (this) {
    SupplierReportRange.last30Days => '30d',
    SupplierReportRange.last3Months => '3m',
    SupplierReportRange.lastYear => '1y',
  };

  String get label => switch (this) {
    SupplierReportRange.last30Days => 'Last 30 days',
    SupplierReportRange.last3Months => 'Last 3 months',
    SupplierReportRange.lastYear => 'Last 12 months',
  };

  /// Compact label for the segmented control.
  String get shortLabel => switch (this) {
    SupplierReportRange.last30Days => '30 days',
    SupplierReportRange.last3Months => '3 months',
    SupplierReportRange.lastYear => '12 months',
  };

  /// Width of the window in days, used to filter the ledger.
  int get days => switch (this) {
    SupplierReportRange.last30Days => 30,
    SupplierReportRange.last3Months => 90,
    SupplierReportRange.lastYear => 365,
  };

  static SupplierReportRange parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll('-', '_');
    return switch (v) {
      '3m' || '3_months' || 'quarter' => SupplierReportRange.last3Months,
      '1y' || '12m' || 'year' || '12_months' => SupplierReportRange.lastYear,
      _ => SupplierReportRange.last30Days,
    };
  }
}

/// One wholesale category's contribution to the period.
class SupplierCategoryPerformance {
  const SupplierCategoryPerformance({
    required this.category,
    required this.revenue,
    required this.units,
    required this.share,
  });

  final String category;

  /// Net revenue for the category, after commission.
  final num revenue;

  final int units;

  /// Share of the period's net revenue, as a fraction (`0.42` = 42%).
  final num share;

  /// [share] as a percentage, for the progress bars.
  double get percent => (share * 100).clamp(0, 100).toDouble();

  factory SupplierCategoryPerformance.fromJson(Map<String, dynamic> j) =>
      SupplierCategoryPerformance(
        category: '${j['category'] ?? j['name'] ?? 'Uncategorised'}',
        revenue: (_num(j['revenue'] ?? j['amount']) ?? 0),
        units: (_num(j['units'] ?? j['quantity']) ?? 0).toInt(),
        share: _num(j['share'] ?? j['percent']) ?? 0,
      );
}

/// A catalogue line that moved the most units in the period.
class SupplierProductPerformance {
  const SupplierProductPerformance({
    required this.name,
    required this.category,
    required this.units,
    required this.revenue,
  });

  final String name;
  final String category;
  final int units;

  /// Net revenue for the line, after commission.
  final num revenue;

  factory SupplierProductPerformance.fromJson(Map<String, dynamic> j) =>
      SupplierProductPerformance(
        name: '${j['name'] ?? j['product'] ?? 'Product'}',
        category: '${j['category'] ?? 'Uncategorised'}',
        units: (_num(j['units'] ?? j['quantity']) ?? 0).toInt(),
        revenue: (_num(j['revenue'] ?? j['amount']) ?? 0),
      );
}

/// Everything the Analytics page renders for one period.
class SupplierAnalyticsSnapshot {
  const SupplierAnalyticsSnapshot({
    required this.range,
    this.grossSales = 0,
    this.commission = 0,
    this.netEarnings = 0,
    this.orderCount = 0,
    this.unitsSold = 0,
    this.averageOrderValue = 0,
    this.salesDelta = 0,
    this.earningsDelta = 0,
    this.orderDelta = 0,
    this.series = const <SupplierEarningsPoint>[],
    this.categories = const <SupplierCategoryPerformance>[],
    this.topProducts = const <SupplierProductPerformance>[],
  });

  final SupplierReportRange range;

  /// Everything the vendors paid for goods in the period.
  final num grossSales;

  /// MVEC commission deducted in the period.
  final num commission;

  /// [grossSales] minus [commission].
  final num netEarnings;

  /// Distinct wholesale orders billed in the period.
  final int orderCount;

  /// Units shipped in the period.
  final int unitsSold;

  /// [netEarnings] per order — what a supplier actually keeps per PO.
  final num averageOrderValue;

  /// Period-over-period change, as a fraction.
  final num salesDelta;
  final num earningsDelta;
  final num orderDelta;

  /// Net earnings bucketed over the period, for the chart.
  final List<SupplierEarningsPoint> series;

  /// Categories ranked by net revenue.
  final List<SupplierCategoryPerformance> categories;

  /// Best-moving catalogue lines, ranked by units.
  final List<SupplierProductPerformance> topProducts;

  bool get isEmpty => orderCount == 0 && netEarnings == 0;

  factory SupplierAnalyticsSnapshot.fromJson(
    Map<String, dynamic> j, {
    SupplierReportRange? fallbackRange,
  }) => SupplierAnalyticsSnapshot(
    range:
        j['range'] == null
            ? (fallbackRange ?? SupplierReportRange.last30Days)
            : SupplierReportRange.parse('${j['range']}'),
    grossSales: _num(j['grossSales'] ?? j['revenue']) ?? 0,
    commission: _num(j['commission']) ?? 0,
    netEarnings: _num(j['netEarnings'] ?? j['earnings']) ?? 0,
    orderCount: (_num(j['orderCount'] ?? j['orders']) ?? 0).toInt(),
    unitsSold: (_num(j['unitsSold'] ?? j['units']) ?? 0).toInt(),
    averageOrderValue: _num(j['averageOrderValue']) ?? 0,
    salesDelta: _num(j['salesDelta'] ?? j['revenueDelta']) ?? 0,
    earningsDelta: _num(j['earningsDelta']) ?? 0,
    orderDelta: _num(j['orderDelta'] ?? j['ordersDelta']) ?? 0,
    series: _list(j['series']).map(SupplierEarningsPoint.fromJson).toList(),
    categories:
        _list(
          j['categories'],
        ).map(SupplierCategoryPerformance.fromJson).toList(),
    topProducts:
        _list(
          j['topProducts'],
        ).map(SupplierProductPerformance.fromJson).toList(),
  );
}

/// A buyer review of the supplier's business.
class SupplierReview {
  const SupplierReview({
    required this.id,
    required this.author,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.orderReference,
    this.reply,
  });

  final String id;

  /// The vendor business that left the review.
  final String author;

  /// 1–5 stars.
  final int rating;
  final String comment;
  final DateTime createdAt;
  final String? orderReference;

  /// A public reply from the supplier, when one has been published.
  final String? reply;

  bool get hasReply => (reply ?? '').isNotEmpty;

  bool get isPositive => rating >= 4;

  factory SupplierReview.fromJson(Map<String, dynamic> j) {
    final author = j['author'] ?? j['buyer'] ?? j['customer'];
    final rating = (_num(j['rating'] ?? j['stars']) ?? 0).round();
    return SupplierReview(
      id: '${j['_id'] ?? j['id'] ?? ''}',
      author:
          author is Map
              ? '${author['businessName'] ?? author['name'] ?? 'Marketplace buyer'}'
              : '${author ?? 'Marketplace buyer'}',
      // Clamp so a malformed payload cannot render 0 or 7 stars.
      rating: rating.clamp(1, 5),
      comment: '${j['comment'] ?? j['review'] ?? j['text'] ?? ''}',
      createdAt:
          parseDate(j['createdAt'] ?? j['date'] ?? j['postedAt']) ??
          DateTime.now(),
      orderReference: j['orderNumber'] == null ? null : '${j['orderNumber']}',
      reply: j['reply'] == null ? null : '${j['reply']}',
    );
  }
}

/// Aggregates for the Reviews page header.
class SupplierReviewSummary {
  const SupplierReviewSummary({
    this.average = 0,
    this.total = 0,
    this.withReply = 0,
    this.distribution = const <int>[0, 0, 0, 0, 0],
  });

  /// Mean rating out of 5.
  final double average;

  /// Number of reviews behind [average].
  final int total;

  /// How many of those the supplier has already answered.
  final int withReply;

  /// Counts for 5, 4, 3, 2 and 1 stars, in that order.
  final List<int> distribution;

  /// Reviews scoring 4 or 5, as a fraction (`0.8` = 80%).
  double get positiveShare =>
      total == 0 ? 0 : (distribution[0] + distribution[1]) / total;

  /// A single star's share of [total], as a percentage.
  double percentFor(int stars) {
    if (stars < 1 || stars > 5 || total == 0) return 0;
    return (distribution[5 - stars] / total * 100).clamp(0, 100).toDouble();
  }

  /// Derives the header aggregates from the review list, so the two can never
  /// disagree.
  factory SupplierReviewSummary.fromReviews(List<SupplierReview> reviews) {
    final counts = List<int>.filled(5, 0);
    var total = 0;
    var replied = 0;
    for (final review in reviews) {
      counts[5 - review.rating]++;
      total++;
      if (review.hasReply) replied++;
    }
    final sum = [
      for (var stars = 1; stars <= 5; stars++) stars * counts[5 - stars],
    ].fold<int>(0, (a, b) => a + b);
    return SupplierReviewSummary(
      average: total == 0 ? 0 : sum / total,
      total: total,
      withReply: replied,
      distribution: counts,
    );
  }

  factory SupplierReviewSummary.fromJson(Map<String, dynamic> j) =>
      SupplierReviewSummary(
        average: (_num(j['average'] ?? j['averageRating']) ?? 0).toDouble(),
        total: (_num(j['total'] ?? j['count']) ?? 0).toInt(),
        withReply: (_num(j['withReply']) ?? 0).toInt(),
        distribution:
            _list(j['distribution']).isEmpty
                ? const <int>[0, 0, 0, 0, 0]
                : _list(
                  j['distribution'],
                ).map((e) => (_num(e) ?? 0).toInt()).toList(),
      );
}

// ── parsing helpers ────────────────────────────────────────────────────────
num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);

List<Map<String, dynamic>> _list(dynamic value) =>
    value is List
        ? value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];
