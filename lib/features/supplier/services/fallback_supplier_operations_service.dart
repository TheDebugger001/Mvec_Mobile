import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../../../core/api_config.dart';
import '../models/supplier_operations.dart';
import 'mock_supplier_operations_service.dart';
import 'supplier_operations_service.dart';

/// Runs every [SupplierOperationsService] call against the live API and falls
/// back to the bundled demo dataset when the route does not exist yet.
///
/// Mirrors `FallbackSupplierFinanceService`: the first unreachable response
/// degrades the module for the rest of the session, so the pages do not probe a
/// missing endpoint on every rebuild.
class FallbackSupplierOperationsService implements SupplierOperationsService {
  FallbackSupplierOperationsService(
    ApiClient api, {
    SupplierOperationsService? fallback,
    bool? forceDemo,
  }) : _api = ApiSupplierOperationsService(api),
       _fallback = fallback ?? MockSupplierOperationsService(),
       _forceDemo = forceDemo ?? kDemoMode {
    if (_forceDemo) {
      _degraded = true;
      lastFallbackReason = 'Demo mode — using the bundled supplier dataset.';
    }
  }

  final ApiSupplierOperationsService _api;
  final SupplierOperationsService _fallback;
  final bool _forceDemo;
  bool _degraded = false;
  String? lastFallbackReason;

  @override
  bool get isDemo => _degraded && _fallback.isDemo;

  @override
  String? get fallbackReason => lastFallbackReason;

  @override
  Future<List<SupplierShipment>> shipments() =>
      _resolve((s) => s.shipments(), source: 'delivery milestones');

  @override
  Future<List<SupplierSettlementEvent>> settlements() =>
      _resolve((s) => s.settlements(), source: 'settlement schedules');

  @override
  Future<DeliverySettlementSummary> deliverySummary() =>
      _resolve((s) => s.deliverySummary(), source: 'settlement summaries');

  @override
  Future<List<SupplierSupplyRequest>> supplyRequests() =>
      _resolve((s) => s.supplyRequests(), source: 'supply requests');

  @override
  Future<List<SupplyProcessStep>> supplyProcess() async =>
      // The process guide is the app's own copy of MVEC's flow, not server data,
      // so it answers from the same constant the status badges are built from.
      kSupplyProcessSteps;

  @override
  Future<SupplierSupplyRequest> createSupplyRequest({
    required List<SupplyRequestLine> lines,
    required DateTime neededBy,
    String? note,
  }) => _resolve(
    (s) => s.createSupplyRequest(lines: lines, neededBy: neededBy, note: note),
    source: 'supply requests',
  );

  @override
  Future<SupplierSupplyRequest> cancelSupplyRequest(String id, String reason) =>
      _resolve(
        (s) => s.cancelSupplyRequest(id, reason),
        source: 'supply request updates',
      );

  @override
  Future<SupplierSupplyRequest> resubmitSupplyRequest(String id) => _resolve(
    (s) => s.resubmitSupplyRequest(id),
    source: 'supply request updates',
  );

  Future<T> _resolve<T>(
    Future<T> Function(SupplierOperationsService service) call, {
    required String source,
  }) async {
    if (_degraded) return call(_fallback);
    try {
      return await call(_api);
    } catch (error) {
      if (_isUnreachable(error)) {
        _degraded = true;
        lastFallbackReason =
            'MVEC does not serve supplier $source yet — showing the bundled '
            'demo dataset instead.';
        return call(_fallback);
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
