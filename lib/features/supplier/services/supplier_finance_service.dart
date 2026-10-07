import '../../../core/api_client.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_insights.dart';

/// Contract for the supplier's Finance & Insights data: balances, the money
/// ledger, withdrawal requests, trend reporting and buyer reviews.
///
/// [ApiSupplierFinanceService] (live backend) and [EmptySupplierFinanceService]
/// (zeroed state while the routes are unshipped) are interchangeable; see
/// `supplier_dependencies.dart` for the wiring. Every supplier route is resolved
/// from the bearer token (`/me/*`), so no supplier id is ever sent by the app —
/// the same convention `ApiSupplierWorkspaceService` follows.
abstract class SupplierFinanceService {
  /// True only when this service is answering from a bundled/local dataset.
  bool get isDemo;

  /// Why the empty-state adapter is being served instead of the API, when that
  /// is the case. Null while the live API is answering.
  String? get fallbackReason;

  /// The headline balances plus the commission rate and the daily series.
  Future<SupplierFinanceSummary> summary();

  /// The money ledger, newest first, optionally narrowed to one [kind].
  Future<List<SupplierLedgerEntry>> ledger({
    SupplierLedgerKind? kind,
    int limit = 50,
  });

  /// Withdrawal requests, newest first. Pending ones are reserved from the
  /// available balance, so this list is what the payout form validates against.
  Future<List<SupplierPayoutRequest>> payouts();

  /// Requests a withdrawal of [amount] from the supplier's cleared earnings.
  ///
  /// Throws when [amount] exceeds the available balance, falls under the
  /// platform minimum, or the destination is missing for the chosen [method].
  Future<SupplierPayoutRequest> requestPayout({
    required num amount,
    required SupplierPayoutMethod method,
    required String destination,
    String? note,
  });

  /// Trend aggregates for one [range].
  Future<SupplierAnalyticsSnapshot> analytics(SupplierReportRange range);

  /// Buyer reviews of the supplier's business, newest first.
  Future<List<SupplierReview>> reviews();
}

/// Minimum withdrawal MVEC will process for a supplier, in RWF.
const double kMinSupplierPayoutAmount = 50000;

/// Talks to the platform's token-scoped supplier finance API.
class ApiSupplierFinanceService implements SupplierFinanceService {
  ApiSupplierFinanceService(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  @override
  Future<SupplierFinanceSummary> summary() async {
    final res = await _api.get('/suppliers/me/finance/summary');
    return SupplierFinanceSummary.fromJson(
      singleJson(res, ['summary', 'finance', 'data']),
    );
  }

  @override
  Future<List<SupplierLedgerEntry>> ledger({
    SupplierLedgerKind? kind,
    int limit = 50,
  }) async {
    final res = await _api.get(
      '/suppliers/me/finance/ledger',
      query: {'limit': limit, if (kind != null) 'kind': kind.slug},
    );
    return listJson(res, [
      'entries',
      'ledger',
      'data',
    ]).map(SupplierLedgerEntry.fromJson).toList();
  }

  @override
  Future<List<SupplierPayoutRequest>> payouts() async {
    final res = await _api.get(
      '/suppliers/me/finance/payouts',
      query: {'limit': 30},
    );
    return listJson(res, [
      'payouts',
      'withdrawals',
      'data',
    ]).map(SupplierPayoutRequest.fromJson).toList();
  }

  @override
  Future<SupplierPayoutRequest> requestPayout({
    required num amount,
    required SupplierPayoutMethod method,
    required String destination,
    String? note,
  }) async {
    final res = await _api.post(
      '/suppliers/me/finance/payouts',
      body: {
        'amount': amount,
        'method': method.slug,
        'destination': destination.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return SupplierPayoutRequest.fromJson(singleJson(res, ['payout']));
  }

  @override
  Future<SupplierAnalyticsSnapshot> analytics(SupplierReportRange range) async {
    final res = await _api.get(
      '/suppliers/me/finance/analytics',
      query: {'range': range.slug},
    );
    return SupplierAnalyticsSnapshot.fromJson(
      singleJson(res, ['analytics', 'report', 'data']),
      fallbackRange: range,
    );
  }

  @override
  Future<List<SupplierReview>> reviews() async {
    final res = await _api.get('/suppliers/me/reviews', query: {'limit': 50});
    return listJson(res, [
      'reviews',
      'data',
    ]).map(SupplierReview.fromJson).toList();
  }
}
