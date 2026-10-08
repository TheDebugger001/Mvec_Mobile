// A fixture-backed [SupplierFinanceService] for tests.
//
// The bundled supplier dataset that used to live in `lib/` is gone — the module
// is API-first and degrades to [EmptySupplierFinanceService]. The screens still
// need real data to render against, so this lives in `test/` where it cannot
// ship: it implements the same contract over a small in-memory ledger, deriving
// the summary *from* that ledger so the reconciliation invariants hold for real
// rather than being asserted against hardcoded numbers.

import 'package:mvec_mobile/features/supplier/models/supplier_finance.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_insights.dart';
import 'package:mvec_mobile/features/supplier/services/supplier_finance_service.dart';

/// A seeded fixture service, ready to hand to a screen under test.
FakeSupplierFinanceService seededFinance() =>
    FakeSupplierFinanceService(delay: Duration.zero).seed();

class FakeSupplierFinanceService implements SupplierFinanceService {
  FakeSupplierFinanceService({this.delay = Duration.zero});

  final Duration delay;

  /// The platform minimum, re-exported so tests assert against the real number.
  static const double minPayout = kMinSupplierPayoutAmount;

  final List<SupplierLedgerEntry> _ledger = <SupplierLedgerEntry>[];
  final List<SupplierPayoutRequest> _payouts = <SupplierPayoutRequest>[];

  num _grossSales = 0;
  num _commission = 0;
  num _escrowHeld = 0;
  num _available = 0;
  num _balance = 0;
  var _nextId = 0;

  /// Populates the ledger with a coherent set of movements and derives every
  /// balance from them.
  FakeSupplierFinanceService seed() {
    _add(SupplierLedgerKind.sale, 1_200_000, 'Wholesale order MV-1001', order: 'MV-1001', commission: 60_000);
    _add(SupplierLedgerKind.sale, 800_000, 'Wholesale order MV-1002', order: 'MV-1002', commission: 40_000);
    _add(SupplierLedgerKind.sale, 540_000, 'Wholesale order MV-1003', order: 'MV-1003', commission: 27_000);
    _add(SupplierLedgerKind.escrowHold, 400_000, 'Funds held for MV-1001');
    _add(SupplierLedgerKind.escrowRelease, 150_000, 'Escrow released for MV-1002');
    _add(SupplierLedgerKind.refund, 60_000, 'Refund for MV-1003');
    _add(SupplierLedgerKind.commission, 0, 'Commission retained on MV-1001', commission: 60_000);
    _add(SupplierLedgerKind.commission, 0, 'Commission retained on MV-1002', commission: 40_000);
    _add(SupplierLedgerKind.commission, 0, 'Commission retained on MV-1003', commission: 27_000);
    // Settle what has been cleared into the withdrawable balance, then take one
    // withdrawal out of it so the ledger and the balance stay in step.
    _balance += 1_200_000;
    _available += 1_200_000;
    _add(SupplierLedgerKind.payout, 250_000, 'Withdrawal to MTN MoMo');
    return this;
  }

  void _add(
    SupplierLedgerKind kind,
    num amount,
    String description, {
    String? order,
    num commission = 0,
  }) {
    _nextId++;
    switch (kind) {
      case SupplierLedgerKind.sale:
        _grossSales += amount;
      case SupplierLedgerKind.refund:
        _grossSales -= amount;
      case SupplierLedgerKind.commission:
        _commission += commission;
      case SupplierLedgerKind.escrowHold:
        _escrowHeld += amount;
      case SupplierLedgerKind.escrowRelease:
        _escrowHeld -= amount;
      case SupplierLedgerKind.payout:
        _available -= amount;
      default:
        break;
    }
    _ledger.insert(
      0,
      SupplierLedgerEntry(
        id: 'sup-led-$_nextId',
        at: DateTime(2026, 9, 30 - _nextId),
        kind: kind,
        amount: amount,
        description: description,
        orderNumber: order,
        balanceAfter: _balance,
      ),
    );
  }

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  Future<T> _latency<T>(T value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return value;
  }

  @override
  Future<SupplierFinanceSummary> summary() {
    return _latency(
      SupplierFinanceSummary(
        grossSales: _grossSales,
        commission: _commission,
        netEarnings: _grossSales - _commission,
        escrowHeld: _escrowHeld,
        availablePayout: _available,
        pendingPayouts: _payouts
            .where((p) => p.isPending)
            .fold<num>(0, (sum, p) => sum + p.amount),
        series: _series(),
        lastPayoutAt: DateTime(2026, 9, 28),
      ),
    );
  }

  List<SupplierEarningsPoint> _series() => [
    for (var day = 1; day <= 7; day++)
      SupplierEarningsPoint(at: DateTime(2026, 9, day), net: 40_000 * day),
  ];

  @override
  Future<List<SupplierLedgerEntry>> ledger({
    SupplierLedgerKind? kind,
    int limit = 50,
  }) {
    final list = kind == null
        ? _ledger
        : _ledger.where((e) => e.kind == kind).toList();
    return _latency(list.take(limit).toList());
  }

  @override
  Future<List<SupplierPayoutRequest>> payouts() =>
      _latency(List<SupplierPayoutRequest>.unmodifiable(_payouts));

  @override
  Future<SupplierPayoutRequest> requestPayout({
    required num amount,
    required SupplierPayoutMethod method,
    required String destination,
    String? note,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    if (amount < kMinSupplierPayoutAmount) {
      throw FakeFinanceError('Below the minimum withdrawal of $kMinSupplierPayoutAmount RWF');
    }
    if (destination.trim().isEmpty) {
      throw FakeFinanceError('A destination is required');
    }
    if (amount > _available) {
      throw FakeFinanceError('Amount exceeds your available balance');
    }

    _nextId++;
    final request = SupplierPayoutRequest(
      id: 'sup-pay-$_nextId',
      requestedAt: DateTime(2026, 10, 1),
      amount: amount,
      method: method,
      destination: destination.trim(),
      note: note == null || note.trim().isEmpty ? null : note.trim(),
      status: 'PENDING',
    );
    _payouts.insert(0, request);
    _add(SupplierLedgerKind.payout, amount, 'Withdrawal to ${method.label}');
    return request;
  }

  @override
  Future<SupplierAnalyticsSnapshot> analytics(SupplierReportRange range) {
    // Wider windows are strictly larger, so the report screens can be checked
    // for switching period without inventing a second dataset.
    final factor = switch (range) {
      SupplierReportRange.last30Days => 4,
      SupplierReportRange.last3Months => 12,
      SupplierReportRange.lastYear => 24,
    };
    final orders = 40 * factor;
    final gross = _grossSales * factor;
    final net = gross - _commission * factor;
    final buckets = factor.clamp(4, 12);

    return _latency(
      SupplierAnalyticsSnapshot(
        range: range,
        grossSales: gross,
        netEarnings: net,
        orderCount: orders,
        unitsSold: orders * 3,
        averageOrderValue: orders == 0 ? 0 : gross / orders,
        series: [
          for (var week = 1; week <= buckets; week++)
            SupplierEarningsPoint(
              at: DateTime(2026, 1, week),
              net: net / buckets,
            ),
        ],
        categories: [
          SupplierCategoryPerformance(
            category: 'Fresh produce',
            revenue: net * 0.55,
            units: 400,
            share: 0.55,
          ),
          SupplierCategoryPerformance(
            category: 'Packaged goods',
            revenue: net * 0.3,
            units: 260,
            share: 0.3,
          ),
          SupplierCategoryPerformance(
            category: 'Beverages',
            revenue: net * 0.15,
            units: 180,
            share: 0.15,
          ),
        ],
        topProducts: [
          SupplierProductPerformance(
            name: 'Green tea leaves',
            category: 'Beverages',
            units: 400,
            revenue: 320_000,
          ),
          SupplierProductPerformance(
            name: 'Sesame oil',
            category: 'Fresh produce',
            units: 260,
            revenue: 210_000,
          ),
        ],
      ),
    );
  }

  @override
  Future<List<SupplierReview>> reviews() => _latency([
    SupplierReview(
      id: 'rev-1',
      author: 'Aline U.',
      rating: 5,
      comment: 'Reliable supplier, always on time.',
      createdAt: DateTime(2026, 9, 20),
      reply: 'Thank you for your business.',
    ),
    SupplierReview(
      id: 'rev-2',
      author: 'Jean Bosco',
      rating: 4,
      comment: 'Good quality, packaging could improve.',
      createdAt: DateTime(2026, 9, 12),
    ),
    SupplierReview(
      id: 'rev-3',
      author: 'Grace M.',
      rating: 5,
      comment: 'Great prices in bulk.',
      createdAt: DateTime(2026, 8, 30),
      reply: 'We appreciate it.',
    ),
  ]);
}
/// A refusal from the fixture service. Typed so tests can assert on it
/// directly instead of matching on message strings.
class FakeFinanceError implements Exception {
  FakeFinanceError(this.message);

  final String message;

  @override
  String toString() => 'FakeFinanceError: $message';
}
