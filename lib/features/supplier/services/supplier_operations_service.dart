import '../../../core/api_client.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_operations.dart';

/// Contract for the supplier's operations data: delivery milestones, the escrow
/// settlement schedule, and inbound supply requests.
///
/// Routes are token-scoped (`/me/*`) so the app never sends a supplier id.
abstract class SupplierOperationsService {
  /// True only when this service is answering from a bundled/local dataset.
  bool get isDemo;

  /// Why the empty-state adapter is being served instead of the API, when that
  /// is the case. Null while the live API is answering.
  String? get fallbackReason;

  /// Consignments on the road, newest first.
  Future<List<SupplierShipment>> shipments();

  /// The settlement schedule, ordered by when the money is due to move.
  Future<List<SupplierSettlementEvent>> settlements();

  /// Counters for the Delivery & Settlement header.
  Future<DeliverySettlementSummary> deliverySummary();

  /// Supply requests, newest first.
  Future<List<SupplierSupplyRequest>> supplyRequests();

  /// The step-by-step supply flow published by the backend.
  Future<List<SupplyProcessStep>> supplyProcess();

  /// Raises a new supply request.
  ///
  /// Throws when [lines] is empty, any quantity is not positive, or [neededBy]
  /// is already in the past.
  Future<SupplierSupplyRequest> createSupplyRequest({
    required List<SupplyRequestLine> lines,
    required DateTime neededBy,
    String? note,
  });

  /// Withdraws a request that has not been approved yet.
  ///
  /// Throws when the request is already approved, in transit or closed.
  Future<SupplierSupplyRequest> cancelSupplyRequest(String id, String reason);

  /// Puts a cancelled request back in the queue as a fresh submission.
  Future<SupplierSupplyRequest> resubmitSupplyRequest(String id);
}

/// Talks to the platform's supplier operations API.
///
/// These endpoints are served by the supplier dashboard API.
class ApiSupplierOperationsService implements SupplierOperationsService {
  ApiSupplierOperationsService(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  @override
  Future<List<SupplierShipment>> shipments() async {
    final res = await _api.get(
      '/suppliers/me/deliveries',
      query: {'limit': 40},
    );
    return listJson(res, [
      'shipments',
      'deliveries',
      'data',
    ]).map(SupplierShipment.fromJson).toList();
  }

  @override
  Future<List<SupplierSettlementEvent>> settlements() async {
    final res = await _api.get(
      '/suppliers/me/settlements',
      query: {'limit': 60},
    );
    return listJson(res, [
      'settlements',
      'events',
      'data',
    ]).map(SupplierSettlementEvent.fromJson).toList();
  }

  @override
  Future<DeliverySettlementSummary> deliverySummary() async {
    final res = await _api.get('/suppliers/me/delivery/summary');
    return DeliverySettlementSummary.fromJson(
      singleJson(res, ['summary', 'settlement', 'data']),
    );
  }

  @override
  Future<List<SupplierSupplyRequest>> supplyRequests() async {
    final res = await _api.get(
      '/suppliers/me/supply-requests',
      query: {'limit': 40},
    );
    return listJson(res, [
      'requests',
      'supplyRequests',
      'data',
    ]).map(SupplierSupplyRequest.fromJson).toList();
  }

  @override
  Future<List<SupplyProcessStep>> supplyProcess() async {
    final res = await _api.get('/suppliers/me/supply-requests/process');
    return listJson(res, [
      'steps',
      'process',
      'data',
    ]).map(SupplyProcessStep.fromJson).toList();
  }

  @override
  Future<SupplierSupplyRequest> createSupplyRequest({
    required List<SupplyRequestLine> lines,
    required DateTime neededBy,
    String? note,
  }) async {
    final res = await _api.post(
      '/suppliers/me/supply-requests',
      body: {
        'lines': [
          for (final line in lines)
            {
              'product': line.product,
              'category': line.category,
              'units': line.units,
              'unit': line.unit,
              'unitPrice': line.unitPrice,
              if (line.note != null && line.note!.trim().isNotEmpty)
                'note': line.note!.trim(),
            },
        ],
        'neededBy': neededBy.toIso8601String(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return SupplierSupplyRequest.fromJson(
      singleJson(res, ['request', 'supplyRequest']),
    );
  }

  @override
  Future<SupplierSupplyRequest> cancelSupplyRequest(
    String id,
    String reason,
  ) async {
    final res = await _api.post(
      '/suppliers/me/supply-requests/$id/cancel',
      body: {'reason': reason.trim()},
    );
    return SupplierSupplyRequest.fromJson(singleJson(res, ['request']));
  }

  @override
  Future<SupplierSupplyRequest> resubmitSupplyRequest(String id) async {
    final res = await _api.post('/suppliers/me/supply-requests/$id/resubmit');
    return SupplierSupplyRequest.fromJson(singleJson(res, ['request']));
  }
}

/// Ledger kinds the settlement schedule can carry. Exposed so the screen can
/// explain a row without importing the finance models for one switch.
const kSettlementKinds = <SupplierLedgerKind>[
  SupplierLedgerKind.escrowHold,
  SupplierLedgerKind.escrowRelease,
  SupplierLedgerKind.payout,
  SupplierLedgerKind.refund,
  SupplierLedgerKind.adjustment,
];
