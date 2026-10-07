import '../../../core/api_client.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_insights.dart';
import 'supplier_finance_service.dart';

/// Local demo implementation of [SupplierFinanceService] for the supplier
/// "Finance & Insights" pages.
///
/// The dataset is a reconcilable ledger built from the same wholesale orders
/// the demo Orders page shows ([DemoSupplierWorkspaceService]): each order posts
/// a SALE and a COMMISSION, an order that has been paid but not yet delivered
/// also posts an ESCROW_HOLD, and a delivered order adds an ESCROW_RELEASE.
/// Withdrawals post a PAYOUT and one cancelled order posts a REFUND.
///
/// Every headline number on the Payments page is derived from those same rows —
/// `availablePayout` is the opening cleared balance plus the released escrow
/// minus every withdrawal, `escrowHeld` is the holds that have not been
/// released — so a supplier (or an auditor) checking the demo can always
/// reconcile the metric cards against the ledger underneath, exactly as they
/// can with the vendor module.
class MockSupplierFinanceService implements SupplierFinanceService {
  MockSupplierFinanceService({this.delay = const Duration(milliseconds: 550)});

  final Duration delay;

  /// Wholesale commission MVEC takes from every settled order.
  static const double _commissionRate = 0.05;

  /// Cleared balance at the start of the demo window — i.e. everything earned
  /// and released before the oldest ledger row. Chosen so the payout form opens
  /// with a balance a supplier can actually withdraw from.
  static const _openingAvailable = 3600000;

  late final List<SupplierLedgerEntry> _ledger = _seedLedger();
  late final List<SupplierPayoutRequest> _payouts = _seedPayouts();
  late final List<SupplierReview> _reviews = _seedReviews();

  /// Payouts requested during this session, prepended to the seeded history.
  final List<SupplierPayoutRequest> _sessionPayouts = [];

  @override
  bool get isDemo => true;

  @override
  String? get fallbackReason => null;

  Future<void> _latency() => Future<void>.delayed(delay);

  // ── reads ────────────────────────────────────────────────────────────────

  @override
  Future<SupplierFinanceSummary> summary() async {
    await _latency();
    final sales = _sum(SupplierLedgerKind.sale);
    final refunds = _sum(SupplierLedgerKind.refund);
    final commission = _sum(SupplierLedgerKind.commission);
    final requests = [..._sessionPayouts, ..._payouts];

    final range = SupplierReportRange.last30Days;
    final now = DateTime.now();
    final current = _window(range, now);
    final previous = _window(range, now.subtract(Duration(days: range.days)));

    return SupplierFinanceSummary(
      grossSales: sales - refunds,
      commission: commission,
      netEarnings: sales - refunds - commission,
      // A hold that was never released is still MVEC's; a release cancels the
      // hold it belongs to, so the difference is what is locked up right now.
      escrowHeld:
          _sum(SupplierLedgerKind.escrowHold) -
          _sum(SupplierLedgerKind.escrowRelease),
      availablePayout: _available,
      pendingPayouts: requests
          .where((p) => p.isPending)
          .fold<num>(0, (sum, p) => sum + p.amount),
      commissionRate: _commissionRate,
      salesDelta: _growth(_grossIn(current), _grossIn(previous)),
      earningsDelta: _growth(_netIn(current), _netIn(previous)),
      series: _series(SupplierReportRange.last30Days),
      lastPayoutAt: requests.where((p) => p.isSettled).firstOrNull?.arrivedAt,
    );
  }

  @override
  Future<List<SupplierLedgerEntry>> ledger({
    SupplierLedgerKind? kind,
    int limit = 50,
  }) async {
    await _latency();
    final rows =
        kind == null ? _ledger : _ledger.where((e) => e.kind == kind).toList();
    return rows.take(limit).toList();
  }

  @override
  Future<List<SupplierPayoutRequest>> payouts() async {
    await _latency();
    return [..._sessionPayouts, ..._payouts];
  }

  @override
  Future<SupplierAnalyticsSnapshot> analytics(SupplierReportRange range) async {
    await _latency();
    final now = DateTime.now();
    final current = _window(range, now);
    final previous = _window(range, now.subtract(Duration(days: range.days)));

    final sales = _sumIn(current, SupplierLedgerKind.sale);
    final refunds = _sumIn(current, SupplierLedgerKind.refund);
    final commission = _sumIn(current, SupplierLedgerKind.commission);
    final orders = {
      for (final e in current)
        if (e.kind == SupplierLedgerKind.sale) e.orderNumber ?? e.id,
    };

    return SupplierAnalyticsSnapshot(
      range: range,
      grossSales: sales - refunds,
      commission: commission,
      netEarnings: sales - refunds - commission,
      orderCount: orders.length,
      unitsSold: _unitsIn(current),
      averageOrderValue: orders.isEmpty ? 0 : (sales - refunds) / orders.length,
      salesDelta: _growth(_grossIn(current), _grossIn(previous)),
      earningsDelta: _growth(_netIn(current), _netIn(previous)),
      orderDelta: _growth(_orderCount(current), _orderCount(previous)),
      series: _series(range),
      categories: _categories(current),
      topProducts: _topProducts(current),
    );
  }

  @override
  Future<List<SupplierReview>> reviews() async {
    await _latency();
    return List.unmodifiable(_reviews);
  }

  // ── writes ───────────────────────────────────────────────────────────────

  @override
  Future<SupplierPayoutRequest> requestPayout({
    required num amount,
    required SupplierPayoutMethod method,
    required String destination,
    String? note,
  }) async {
    await _latency();
    if (amount < kMinSupplierPayoutAmount) {
      throw ApiException(
        'The minimum withdrawal is ${_plain(kMinSupplierPayoutAmount)} RWF.',
      );
    }
    if (destination.trim().isEmpty) {
      throw ApiException(
        'Enter the phone number or bank account to receive the money.',
      );
    }
    final available = _available;
    if (amount > available) {
      throw ApiException(
        'You can withdraw at most ${_plain(available)} RWF right now.',
      );
    }

    final request = SupplierPayoutRequest(
      id: 'sup-payout-${_sessionPayouts.length + 1}',
      amount: amount,
      method: method,
      requestedAt: DateTime.now(),
      status: 'PENDING',
      destination: destination.trim(),
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );
    _sessionPayouts.insert(0, request);

    // Post the withdrawal to the ledger too, so the two views stay in step and
    // the balance on the card drops by exactly the requested amount.
    _ledger.insert(
      0,
      SupplierLedgerEntry(
        id: 'sup-led-${request.id}',
        at: request.requestedAt,
        kind: SupplierLedgerKind.payout,
        amount: amount,
        description: 'Withdrawal to ${method.label}',
        balanceAfter: available - amount,
        payoutMethod: method,
        payoutStatus: 'PENDING',
      ),
    );
    return request;
  }

  // ── derivations ──────────────────────────────────────────────────────────

  /// Cleared balance: the opening figure, plus every escrow release, minus every
  /// withdrawal including the ones requested this session.
  num get _available =>
      _openingAvailable +
      _sum(SupplierLedgerKind.escrowRelease) -
      _sum(SupplierLedgerKind.payout);

  /// Total of every ledger row of one [kind].
  num _sum(SupplierLedgerKind kind) =>
      _ledger.where((e) => e.kind == kind).fold<num>(0, (s, e) => s + e.amount);

  num _sumIn(List<SupplierLedgerEntry> rows, SupplierLedgerKind kind) =>
      rows.where((e) => e.kind == kind).fold<num>(0, (s, e) => s + e.amount);

  /// The [range]-wide window ending at [end], inclusive of the start.
  List<SupplierLedgerEntry> _window(SupplierReportRange range, DateTime end) {
    final start = end.subtract(Duration(days: range.days));
    return _ledger
        .where((e) => !e.at.isBefore(start) && !e.at.isAfter(end))
        .toList();
  }

  int _unitsIn(List<SupplierLedgerEntry> rows) => rows
      .where((e) => e.kind == SupplierLedgerKind.sale)
      .fold<int>(0, (sum, e) => sum + e.units);

  /// Gross sales in a window: order values less the refunds booked against them.
  num _grossIn(List<SupplierLedgerEntry> rows) =>
      _sumIn(rows, SupplierLedgerKind.sale) -
      _sumIn(rows, SupplierLedgerKind.refund);

  num _netIn(List<SupplierLedgerEntry> rows) =>
      _grossIn(rows) - _sumIn(rows, SupplierLedgerKind.commission);

  num _orderCount(List<SupplierLedgerEntry> rows) =>
      rows
          .where((e) => e.kind == SupplierLedgerKind.sale)
          .map((e) => e.id)
          .toSet()
          .length;

  /// Fractional change between two windows, zero when there is nothing to
  /// compare against — a first-period supplier should not read "∞% growth".
  num _growth(num current, num previous) {
    if (previous == 0) return 0;
    return (current - previous) / previous;
  }

  /// Net earnings bucketed over [range], oldest bucket first.
  List<SupplierEarningsPoint> _series(SupplierReportRange range) {
    final buckets = switch (range) {
      // 15 two-day buckets span exactly the 30-day window.
      SupplierReportRange.last30Days => 15,
      // 13 weekly buckets ≈ the 3-month window.
      SupplierReportRange.last3Months => 13,
      // 12 thirty-day buckets ≈ the 12-month window.
      SupplierReportRange.lastYear => 12,
    };
    final bucketDays = range.days / buckets;
    final now = DateTime.now();
    final points = <SupplierEarningsPoint>[];
    for (var i = buckets - 1; i >= 0; i--) {
      final start = now.subtract(Duration(days: (i * bucketDays).round()));
      final end = start.add(Duration(days: bucketDays.ceil()));
      final rows =
          _ledger
              .where((e) => !e.at.isBefore(start) && e.at.isBefore(end))
              .toList();
      points.add(
        SupplierEarningsPoint(
          at: start,
          net: _netIn(rows),
          units: _unitsIn(rows),
        ),
      );
    }
    return points;
  }

  /// Net revenue per catalogue category, ranked.
  List<SupplierCategoryPerformance> _categories(
    List<SupplierLedgerEntry> rows,
  ) {
    final totals = <String, ({num revenue, int units})>{};
    for (final order in _orders) {
      if (!rows.any((e) => e.orderNumber == order.number)) continue;
      final net = order.gross - _commissionFor(order.gross);
      final current = totals[order.category] ?? (revenue: 0, units: 0);
      totals[order.category] = (
        revenue: current.revenue + net,
        units: current.units + order.units,
      );
    }
    final grand = totals.values.fold<num>(0, (sum, t) => sum + t.revenue);
    final ranked =
        totals.entries.toList()
          ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
    return [
      for (final entry in ranked)
        SupplierCategoryPerformance(
          category: entry.key,
          revenue: entry.value.revenue,
          units: entry.value.units,
          share: grand == 0 ? 0 : entry.value.revenue / grand,
        ),
    ];
  }

  /// Best-moving catalogue lines by units shipped.
  List<SupplierProductPerformance> _topProducts(
    List<SupplierLedgerEntry> rows,
  ) {
    final totals = <String, ({String category, int units, num revenue})>{};
    for (final order in _orders) {
      if (!rows.any((e) => e.orderNumber == order.number)) continue;
      final net = order.gross - _commissionFor(order.gross);
      final current =
          totals[order.product] ??
          (category: order.category, units: 0, revenue: 0);
      totals[order.product] = (
        category: order.category,
        units: current.units + order.units,
        revenue: current.revenue + net,
      );
    }
    final ranked =
        totals.entries.toList()
          ..sort((a, b) => b.value.units.compareTo(a.value.units));
    return [
      for (final entry in ranked.take(6))
        SupplierProductPerformance(
          name: entry.key,
          category: entry.value.category,
          units: entry.value.units,
          revenue: entry.value.revenue,
        ),
    ];
  }

  static num _commissionFor(num gross) => (gross * _commissionRate).round();

  // ── demo dataset ─────────────────────────────────────────────────────────

  /// The wholesale orders behind the ledger. `delivered: false` means the
  /// vendor has paid but MVEC has not confirmed delivery, so the money sits in
  /// escrow instead of the cleared balance.
  static const _orders = <_SeedOrder>[
    _SeedOrder(
      'MV-4847',
      'Arabica Coffee Beans',
      'Beverages',
      5,
      62500,
      1,
      true,
    ),
    _SeedOrder(
      'MV-4821',
      'Arabica Coffee Beans',
      'Beverages',
      8,
      100000,
      2,
      false,
    ),
    _SeedOrder('MV-4836', 'Raw Forest Honey', 'Pantry', 4, 31200, 3, true),
    _SeedOrder('MV-4814', 'Fresh Avocados', 'Produce', 24, 21600, 5, false),
    _SeedOrder(
      'MV-4808',
      'Dried Red Kidney Beans',
      'Grains & pulses',
      15,
      36000,
      7,
      true,
    ),
    _SeedOrder('MV-4792', 'Raw Forest Honey', 'Pantry', 6, 46800, 7, false),
    _SeedOrder('MV-4780', 'Fresh Avocados', 'Produce', 36, 30000, 11, true),
    _SeedOrder(
      'MV-4760',
      'Arabica Coffee Beans',
      'Beverages',
      4,
      50000,
      12,
      true,
    ),
    _SeedOrder('MV-4745', 'Raw Forest Honey', 'Pantry', 7, 52000, 15, true),
    _SeedOrder(
      'MV-4733',
      'Arabica Coffee Beans',
      'Beverages',
      10,
      125000,
      19,
      true,
    ),
    _SeedOrder(
      'MV-4720',
      'Dried Red Kidney Beans',
      'Grains & pulses',
      25,
      60000,
      22,
      true,
    ),
    // Delivered, but the buyer disputed two jars, so the release is still held.
    // `MockSupplierOperationsService` carries the same order as a paused
    // consignment — the two pages must agree on which money is still locked.
    _SeedOrder('MV-4701', 'Raw Forest Honey', 'Pantry', 6, 46800, 26, false),
    _SeedOrder('MV-4688', 'Fresh Avocados', 'Produce', 30, 27000, 29, true),
    _SeedOrder(
      'MV-4678',
      'Arabica Coffee Beans',
      'Beverages',
      12,
      150000,
      33,
      true,
    ),
    _SeedOrder(
      'MV-4661',
      'Dried Red Kidney Beans',
      'Grains & pulses',
      20,
      48000,
      38,
      true,
    ),
    _SeedOrder('MV-4640', 'Raw Forest Honey', 'Pantry', 8, 62400, 44, true),
    _SeedOrder(
      'MV-4622',
      'Arabica Coffee Beans',
      'Beverages',
      25,
      300000,
      51,
      true,
    ),
    _SeedOrder('MV-4601', 'Fresh Avocados', 'Produce', 50, 42000, 58, true),
    _SeedOrder(
      'MV-4577',
      'Dried Red Kidney Beans',
      'Grains & pulses',
      40,
      88000,
      66,
      true,
    ),
    _SeedOrder(
      'MV-4541',
      'Arabica Coffee Beans',
      'Beverages',
      22,
      330000,
      78,
      true,
    ),
    _SeedOrder('MV-4490', 'Raw Forest Honey', 'Pantry', 18, 132000, 96, true),
    _SeedOrder(
      'MV-4460',
      'Dried Red Kidney Beans',
      'Grains & pulses',
      15,
      112000,
      118,
      true,
    ),
    _SeedOrder(
      'MV-4402',
      'Arabica Coffee Beans',
      'Beverages',
      35,
      380000,
      150,
      true,
    ),
    _SeedOrder('MV-4330', 'Fresh Avocados', 'Produce', 35, 160000, 190, true),
    _SeedOrder(
      'MV-4211',
      'Dried Red Kidney Beans',
      'Grains & pulses',
      45,
      96000,
      240,
      true,
    ),
    _SeedOrder(
      'MV-4094',
      'Arabica Coffee Beans',
      'Beverages',
      22,
      300000,
      300,
      true,
    ),
  ];

  /// One cancelled order, to exercise the negative side of the ledger.
  static const _refund = (
    'MV-4711',
    '2 × Organic Vanilla Garlic (kg), cancelled before dispatch',
    15600,
    24,
  );

  static DateTime _ago(int days) =>
      DateTime.now().subtract(Duration(days: days));

  static String _units(int units, String product) => '$units × $product';

  List<SupplierLedgerEntry> _seedLedger() {
    final rows = <SupplierLedgerEntry>[];

    for (final order in _orders) {
      final placedAt = _ago(order.daysAgo);
      final commission = _commissionFor(order.gross);
      final net = order.gross - commission;

      rows.add(
        SupplierLedgerEntry(
          id: 'sup-led-${order.number}',
          at: placedAt,
          kind: SupplierLedgerKind.sale,
          amount: order.gross,
          description: _units(order.units, order.product),
          orderNumber: order.number,
          units: order.units,
        ),
      );
      rows.add(
        SupplierLedgerEntry(
          id: 'sup-led-${order.number}-fee',
          at: placedAt.add(const Duration(minutes: 3)),
          kind: SupplierLedgerKind.commission,
          amount: commission,
          description: 'Wholesale commission (5%) on ${order.number}',
          orderNumber: order.number,
        ),
      );
      rows.add(
        SupplierLedgerEntry(
          id: 'sup-led-${order.number}-hold',
          at: placedAt.add(const Duration(minutes: 20)),
          kind: SupplierLedgerKind.escrowHold,
          amount: net,
          description: 'Held until delivery of ${order.number} is confirmed',
          orderNumber: order.number,
        ),
      );
      if (order.delivered) {
        rows.add(
          SupplierLedgerEntry(
            id: 'sup-led-${order.number}-release',
            at: placedAt.add(const Duration(days: 2, hours: 4)),
            kind: SupplierLedgerKind.escrowRelease,
            amount: net,
            description: 'Delivery confirmed for ${order.number}',
            orderNumber: order.number,
          ),
        );
      }
    }

    final (refundNo, refundDescription, refundAmount, refundDays) = _refund;
    rows.add(
      SupplierLedgerEntry(
        id: 'sup-led-$refundNo',
        at: _ago(refundDays),
        kind: SupplierLedgerKind.refund,
        amount: refundAmount,
        description: refundDescription,
        orderNumber: refundNo,
      ),
    );

    // Seeded withdrawal history so the payout list is not empty on first open.
    // These are ordinary PAYOUT rows, so they are already deducted from
    // [_available] through the same sum the summary uses.
    for (final payout in _payouts) {
      rows.add(
        SupplierLedgerEntry(
          id: 'sup-led-${payout.id}',
          at: payout.requestedAt,
          kind: SupplierLedgerKind.payout,
          amount: payout.amount,
          description: 'Withdrawal to ${payout.method.label}',
          payoutMethod: payout.method,
          payoutStatus: payout.status,
        ),
      );
    }

    // Newest first.
    rows.sort((a, b) => b.at.compareTo(a.at));
    return rows;
  }

  List<SupplierPayoutRequest> _seedPayouts() => [
    SupplierPayoutRequest(
      id: 'sup-payout-hist-1',
      amount: 1800000,
      method: SupplierPayoutMethod.mtnMomo,
      requestedAt: _ago(9),
      arrivedAt: _ago(9).add(const Duration(minutes: 21)),
      status: 'PAID',
      destination: '+250 78••• 610',
      note: 'Weekly settlement',
    ),
    SupplierPayoutRequest(
      id: 'sup-payout-hist-2',
      amount: 1250000,
      method: SupplierPayoutMethod.bankTransfer,
      requestedAt: _ago(27),
      arrivedAt: _ago(26),
      status: 'PAID',
      destination: 'Equity ••••2088',
    ),
    SupplierPayoutRequest(
      id: 'sup-payout-hist-3',
      amount: 420000,
      method: SupplierPayoutMethod.airtelMoney,
      requestedAt: _ago(2),
      status: 'PENDING',
      destination: '+250 73••• 415',
      note: 'Awaiting delivery confirmation',
    ),
  ];

  /// Buyer feedback on the demo supplier's business. The rating mix averages
  /// 4.6, matching `SupplierProfile.ratingAvg` on the Settings page.
  List<SupplierReview> _seedReviews() => [
    SupplierReview(
      id: 'sup-rev-1',
      author: 'Kigali Market Kitchen',
      rating: 5,
      comment:
          'Coffee arrived in perfect condition and the crates were clearly '
          'labelled with the lot number. Delivery landed exactly when promised.',
      createdAt: _ago(2),
      orderReference: 'MV-4847',
    ),
    SupplierReview(
      id: 'sup-rev-2',
      author: 'Green Basket Ltd',
      rating: 4,
      comment:
          'Avocados were well packed for wholesale and the bulk discount was '
          'applied correctly. A little more notice before dispatch would help.',
      createdAt: _ago(6),
      orderReference: 'MV-4814',
      reply:
          'Thank you for the feedback — dispatch notices now go out a day '
          'earlier.',
    ),
    SupplierReview(
      id: 'sup-rev-3',
      author: 'Umurimo Grocers',
      rating: 5,
      comment:
          'The honey is consistent across every delivery, which matters to us '
          'because we sell it by the jar.',
      createdAt: _ago(10),
      orderReference: 'MV-4808',
    ),
    SupplierReview(
      id: 'sup-rev-4',
      author: 'Kivu Cafe',
      rating: 5,
      comment:
          'Best wholesale coffee we have sourced in Rwanda. Roast profile is '
          'exactly as described on the listing.',
      createdAt: _ago(18),
      orderReference: 'MV-4733',
    ),
    SupplierReview(
      id: 'sup-rev-5',
      author: 'FreshPoint Market',
      rating: 4,
      comment:
          'Good quality beans and fair pricing. Delivery slipped by half a day '
          'once, otherwise very reliable.',
      createdAt: _ago(24),
      orderReference: 'MV-4688',
      reply:
          'Apologies for the delay — that shipment waited on a vehicle. It has '
          'not happened since.',
    ),
    SupplierReview(
      id: 'sup-rev-6',
      author: 'Hotel Girambato',
      rating: 5,
      comment:
          'Supplies our pantry every month without a single complaint from our '
          'kitchen team.',
      createdAt: _ago(31),
      orderReference: 'MV-4640',
    ),
    SupplierReview(
      id: 'sup-rev-7',
      author: 'Nyamirambo Foods',
      rating: 4,
      comment:
          'Bulk discount tiers are well structured and the stock counts are '
          'accurate, so we can plan our menus around them.',
      createdAt: _ago(39),
      orderReference: 'MV-4577',
    ),
  ];

  /// RWF amount without a currency suffix, for messages.
  static String _plain(num v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

/// One row of the seeded wholesale order book.
class _SeedOrder {
  const _SeedOrder(
    this.number,
    this.product,
    this.category,
    this.units,
    this.gross,
    this.daysAgo,
    this.delivered,
  );

  final String number;
  final String product;
  final String category;
  final int units;

  /// Order value before the wholesale commission.
  final num gross;
  final int daysAgo;

  /// `false` while MVEC still holds the funds in escrow.
  final bool delivered;
}
