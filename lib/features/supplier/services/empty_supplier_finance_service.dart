import '../../../core/api_client.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_insights.dart';
import 'supplier_finance_service.dart';

/// Empty-state implementation of [SupplierFinanceService].
///
/// The bundled dataset this used to serve is gone, so every read now resolves to
/// the same zeroed shape the API layer would produce for a supplier with no
/// financial activity yet: empty lists, zero balances, no series. The supplier
/// Finance pages therefore render their empty states instead of invented
/// numbers while `/suppliers/me/finance/*` is being connected.
///
/// Reads are safe and always succeed. Writes throw an [ApiException] on purpose
/// — a withdrawal cannot be acknowledged locally, so the form has to surface the
/// failure rather than report a payout that the backend never recorded.
class EmptySupplierFinanceService implements SupplierFinanceService {
  EmptySupplierFinanceService({this.delay = Duration.zero});

  /// Kept so the fallback wrapper can keep the same call pacing as the rest of
  /// the app without this class needing to know about it.
  final Duration delay;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  Future<T> _latency<T>(T value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return value;
  }

  @override
  Future<SupplierFinanceSummary> summary() =>
      _latency(const SupplierFinanceSummary());

  @override
  Future<List<SupplierLedgerEntry>> ledger({
    SupplierLedgerKind? kind,
    int limit = 50,
  }) => _latency(const <SupplierLedgerEntry>[]);

  @override
  Future<List<SupplierPayoutRequest>> payouts() =>
      _latency(const <SupplierPayoutRequest>[]);

  @override
  Future<SupplierPayoutRequest> requestPayout({
    required num amount,
    required SupplierPayoutMethod method,
    required String destination,
    String? note,
  }) =>
      throw ApiException(
        'Withdrawals are not available yet — this endpoint has not shipped.',
        statusCode: 501,
      );

  @override
  Future<SupplierAnalyticsSnapshot> analytics(SupplierReportRange range) =>
      _latency(SupplierAnalyticsSnapshot(range: range));

  @override
  Future<List<SupplierReview>> reviews() =>
      _latency(const <SupplierReview>[]);
}
