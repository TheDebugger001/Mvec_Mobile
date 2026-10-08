import '../../../core/api_client.dart';
import '../models/supplier_operations.dart';
import 'supplier_operations_service.dart';

/// Empty-state implementation of [SupplierOperationsService].
///
/// The bundled dataset this used to serve is gone, so every read now resolves to
/// the zeroed shape the API layer would produce for a supplier with nothing on
/// the road: no consignments, no settlement events, no inbound requests. The
/// Delivery & Settlement and Supply Requests pages render their empty states
/// while `/suppliers/me/deliveries` and `/suppliers/me/supply-requests` are being
/// connected.
///
/// [supplyProcess] still answers with [kSupplyProcessSteps] — that is MVEC's own
/// description of the workflow, not supplier data, and the status badges are
/// built from the same constant.
///
/// Writes throw an [ApiException] so the forms report a real failure instead of
/// acknowledging a request the backend never stored.
class EmptySupplierOperationsService implements SupplierOperationsService {
  EmptySupplierOperationsService({this.delay = Duration.zero});

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
  Future<List<SupplierShipment>> shipments() =>
      _latency(const <SupplierShipment>[]);

  @override
  Future<List<SupplierSettlementEvent>> settlements() =>
      _latency(const <SupplierSettlementEvent>[]);

  @override
  Future<DeliverySettlementSummary> deliverySummary() =>
      _latency(const DeliverySettlementSummary());

  @override
  Future<List<SupplierSupplyRequest>> supplyRequests() =>
      _latency(const <SupplierSupplyRequest>[]);

  @override
  Future<List<SupplyProcessStep>> supplyProcess() =>
      _latency(kSupplyProcessSteps);

  Never _writeUnsupported(String what) => throw ApiException(
    '$what is not available yet — this endpoint has not shipped.',
    statusCode: 501,
  );

  @override
  Future<SupplierSupplyRequest> createSupplyRequest({
    required List<SupplyRequestLine> lines,
    required DateTime neededBy,
    String? note,
  }) => _writeUnsupported('Supply requests');

  @override
  Future<SupplierSupplyRequest> cancelSupplyRequest(String id, String reason) =>
      _writeUnsupported('Supply request updates');

  @override
  Future<SupplierSupplyRequest> resubmitSupplyRequest(String id) =>
      _writeUnsupported('Supply request updates');
}
