import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../../../core/api_config.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_insights.dart';
import 'mock_supplier_finance_service.dart';
import 'supplier_finance_service.dart';

/// Prefer the live supplier API and treat missing backend routes as errors rather
/// than shipping demo content back into the app.
class FallbackSupplierFinanceService implements SupplierFinanceService {
  FallbackSupplierFinanceService(
    ApiClient api, {
    SupplierFinanceService? fallback,
    bool? forceDemo,
  }) : _api = ApiSupplierFinanceService(api),
       _fallback = fallback ?? MockSupplierFinanceService(),
       _forceDemo = forceDemo ?? kDemoMode {
    if (_forceDemo) {
      _degraded = true;
      lastFallbackReason = 'Demo mode — using the bundled supplier dataset.';
    }
  }

  final ApiSupplierFinanceService _api;
  final SupplierFinanceService _fallback;
  final bool _forceDemo;
  bool _degraded = false;

  String? lastFallbackReason;

  @override
  bool get isDemo => _degraded && _fallback.isDemo;

  @override
  String? get fallbackReason => lastFallbackReason;

  @override
  Future<SupplierFinanceSummary> summary() =>
      _resolve((s) => s.summary(), source: 'balances');

  @override
  Future<List<SupplierLedgerEntry>> ledger({
    SupplierLedgerKind? kind,
    int limit = 50,
  }) => _resolve((s) => s.ledger(kind: kind, limit: limit), source: 'ledger');

  @override
  Future<List<SupplierPayoutRequest>> payouts() =>
      _resolve((s) => s.payouts(), source: 'payout history');

  @override
  Future<SupplierPayoutRequest> requestPayout({
    required num amount,
    required SupplierPayoutMethod method,
    required String destination,
    String? note,
  }) => _resolve(
    (s) => s.requestPayout(
      amount: amount,
      method: method,
      destination: destination,
      note: note,
    ),
    source: 'payout requests',
  );

  @override
  Future<SupplierAnalyticsSnapshot> analytics(SupplierReportRange range) =>
      _resolve((s) => s.analytics(range), source: 'analytics');

  @override
  Future<List<SupplierReview>> reviews() =>
      _resolve((s) => s.reviews(), source: 'reviews');

  Future<T> _resolve<T>(
  Future<T> Function(SupplierFinanceService service) call, {
    required String source,
  }) async {
  if (_degraded) return call(_fallback);
  try {
    return await call(_api);
  } catch (error) {
    if (_isUnreachable(error)) {
      _degraded = true;
      lastFallbackReason =
          'MVEC does not serve supplier $source yet — the app cannot show demo data.';
      throw error;
    }
    rethrow;
  }
  }

  bool _isUnreachable(Object error) {
  if (error is ApiException) {
    return error.statusCode == null ||
        error.statusCode == 404 ||
        error.statusCode == 501;
  }
  if (error is DioException) {
    final nested = error.error;
    if (nested is ApiException) return _isUnreachable(nested);
    final code = error.response?.statusCode;
    return code == null || code == 404 || code == 501;
  }
  return false;
  }
}
