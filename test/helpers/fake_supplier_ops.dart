// Fixture-backed [SupplierOperationsService] and [SupplierTeamService] for
// tests.
//
// The bundled supplier operations dataset that used to live in `lib/` is gone —
// the module is API-first and degrades to the empty adapters. The screens still
// need data to render against, so this lives in `test/` where it cannot ship.
//
// The fixtures keep the rules the screens and models depend on:
//  - a shipment only reports milestones it has actually reached;
//  - the escrow the delivery page reports is the sum of the undelivered net
//    values, so it reconciles with the finance summary;
//  - a supply request only moves forwards, and cannot be cancelled once it is
//    in flight;
//  - the account's owner cannot be edited, duplicated or removed, and a phone
//    number cannot be on the roster twice in a different format.

import 'package:mvec_mobile/core/api_client.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_finance.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_operations.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_team.dart';
import 'package:mvec_mobile/features/supplier/services/supplier_operations_service.dart';
import 'package:mvec_mobile/features/supplier/services/supplier_team_service.dart';

class FakeSupplierOperationsService implements SupplierOperationsService {
  FakeSupplierOperationsService({this.delay = Duration.zero});

  final Duration delay;

  final List<SupplierShipment> _shipments = <SupplierShipment>[];
  final List<SupplierSupplyRequest> _requests = <SupplierSupplyRequest>[];

  var _nextRequest = 2057;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  Future<T> _latency<T>(T value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return value;
  }

  /// Populates a coherent set of consignments: one already delivered, one out
  /// for delivery with money still held, and one still being packed.
  FakeSupplierOperationsService seed() {
    _shipments.addAll([
      SupplierShipment(
        id: 'shp-1',
        orderNumber: 'MV-20415',
        buyer: 'Aline U.',
        product: 'Green tea leaves',
        units: 40,
        gross: 480000,
        net: 456000,
        destination: 'Kicukiro, Kigali',
        stage: DeliveryStage.delivered,
        courier: 'Mvec Express',
        trackingNumber: 'TRK-1001',
        eta: DateTime(2026, 9, 18),
        deliveredAt: DateTime(2026, 9, 17),
        settledAt: DateTime(2026, 9, 18),
        milestones: [
          SupplierDeliveryMilestone(
            stage: DeliveryStage.confirmed,
            at: DateTime(2026, 9, 25),
          ),
        ],
      ),
      SupplierShipment(
        id: 'shp-2',
        orderNumber: 'MV-20431',
        buyer: 'Jean Bosco',
        product: 'Sesame oil',
        units: 120,
        gross: 89500,
        net: 85000,
        destination: 'Remera, Kigali',
        stage: DeliveryStage.outForDelivery,
        courier: 'Mvec Express',
        trackingNumber: 'TRK-1002',
        eta: DateTime(2026, 10, 2),
        holdReason: null,
        milestones: _milestonesThrough(DeliveryStage.outForDelivery),
      ),
      SupplierShipment(
        id: 'shp-3',
        orderNumber: 'MV-20440',
        buyer: 'Grace M.',
        product: 'Packaged coffee',
        units: 60,
        gross: 65000,
        net: 62000,
        destination: 'Nyamirambo, Kigali',
        stage: DeliveryStage.packed,
        milestones: _milestonesThrough(DeliveryStage.packed),
      ),
      SupplierShipment(
        id: 'shp-4',
        orderNumber: 'MV-20455',
        buyer: 'Eric N.',
        product: 'Beverage mixers',
        units: 200,
        gross: 71500,
        net: 68000,
        destination: 'Musanze, Rubavu',
        stage: DeliveryStage.dispatched,
        courier: 'Mvec Express',
        trackingNumber: 'TRK-1004',
        eta: DateTime(2026, 10, 8),
        holdReason: 'Delivery address needs confirming',
        milestones: _milestonesThrough(DeliveryStage.dispatched),
      ),
      // A consignment whose settlement is paused: the money is still locked but
      // no release is booked, so `isPaused` and the held branch are both live.
      SupplierShipment(
        id: 'shp-5',
        orderNumber: 'MV-20461',
        buyer: 'Claudine I.',
        product: 'Spice blend',
        units: 80,
        gross: 36900,
        net: 35000,
        destination: 'Huye, Southern Province',
        stage: DeliveryStage.dispatched,
        courier: 'Mvec Express',
        trackingNumber: 'TRK-1005',
        holdReason: 'Buyer disputed the delivery',
        milestones: _milestonesThrough(DeliveryStage.dispatched),
      ),
    ]);
    _requests.addAll([
      requestIn(
        SupplyRequestStatus.submitted,
        id: 'sup-req-2057',
        reference: 'SR-2057',
        lines: const [
          SupplyRequestLine(
            product: 'Green tea leaves',
            category: 'Beverages',
            units: 40,
            unit: 'kg',
            unitPrice: 8000,
          ),
        ],
      ),
      requestIn(
        SupplyRequestStatus.underReview,
        id: 'sup-req-2058',
        reference: 'SR-2058',
        lines: const [
          SupplyRequestLine(
            product: 'Sesame oil',
            category: 'Fresh produce',
            units: 120,
            unit: 'litre',
            unitPrice: 2400,
          ),
        ],
      ),
      requestIn(
        SupplyRequestStatus.inTransit,
        id: 'sup-req-2059',
        reference: 'SR-2059',
        lines: const [
          SupplyRequestLine(
            product: 'Packaged coffee',
            category: 'Beverages',
            units: 60,
            unit: 'kg',
            unitPrice: 3600,
          ),
        ],
      ),
      requestIn(
        SupplyRequestStatus.received,
        id: 'sup-req-2060',
        reference: 'SR-2060',
        lines: const [
          SupplyRequestLine(
            product: 'Beverage mixers',
            category: 'Beverages',
            units: 200,
            unit: 'unit',
            unitPrice: 1500,
          ),
        ],
      ),
    ]);
    return this;
  }

  /// Milestones are dated only up to [stage]; everything past it stays undated
  /// so the screen can draw the pending part of the track.
  static List<SupplierDeliveryMilestone> _milestonesThrough(DeliveryStage stage) {
    const reached = [DeliveryStage.confirmed, DeliveryStage.packed, DeliveryStage.dispatched, DeliveryStage.outForDelivery, DeliveryStage.delivered];
    final cut = reached.indexOf(stage);
    return [
      for (var i = 0; i < reached.length; i++)
        SupplierDeliveryMilestone(
          stage: reached[i],
          at: i <= cut ? DateTime(2026, 9, 25 + i) : null,
        ),
    ];
  }

  @override
  Future<List<SupplierShipment>> shipments() =>
      _latency(List<SupplierShipment>.unmodifiable(_shipments));

  @override
  Future<List<SupplierSettlementEvent>> settlements() {
    final events = <SupplierSettlementEvent>[
      for (final shipment in _shipments)
        SupplierSettlementEvent(
          id: 'set-${shipment.id}',
          at: shipment.eta ?? DateTime(2026, 9, 25),
          kind: shipment.settledAt == null
              ? SupplierLedgerKind.escrowHold
              : SupplierLedgerKind.escrowRelease,
          amount: shipment.net,
          description: '${shipment.product} for ${shipment.orderNumber}',
          orderNumber: shipment.orderNumber,
          expectedAt: shipment.eta,
          settledAt: shipment.settledAt,
        ),
    ];
    // A consignment on hold books no release date, which is what makes the event
    // paused: the money is still locked with no date attached.
    for (final shipment in _shipments.where((s) => s.isOnHold && s.eta == null)) {
      events.add(
        SupplierSettlementEvent(
          id: 'set-paused-${shipment.id}',
          at: DateTime(2026, 9, 28),
          kind: SupplierLedgerKind.escrowRelease,
          amount: shipment.net,
          description: 'Settlement paused for ${shipment.orderNumber}',
          orderNumber: shipment.orderNumber,
        ),
      );
    }
    events.sort((a, b) => a.at.compareTo(b.at));
    return _latency(events);
  }

  @override
  Future<DeliverySettlementSummary> deliverySummary() {
    // Counters are derived from the shipment list, never a second copy of it.
    final undelivered = _shipments.where((s) => !s.isDelivered).toList();
    final month = DateTime.now().subtract(const Duration(days: 30));
    final delivered = _shipments.where((s) => s.deliveredAt != null).toList();
    final onTime = delivered.where((s) {
      final eta = s.eta;
      final at = s.deliveredAt;
      return eta != null && at != null && !at.isAfter(eta);
    }).length;

    return _latency(
      DeliverySettlementSummary(
        activeShipments: undelivered.length,
        deliveredThisMonth:
            delivered.where((s) => s.deliveredAt!.isAfter(month)).length,
        inEscrow: undelivered.fold<num>(0, (sum, s) => sum + s.net),
        scheduled: _shipments
            .where((s) => s.settledAt == null && s.eta != null)
            .fold<num>(0, (sum, s) => sum + s.net),
        releasedThisPeriod: _shipments
            .where((s) => s.settledAt != null)
            .fold<num>(0, (sum, s) => sum + s.net),
        heldOrders: _shipments.where((s) => s.holdReason != null).length,
        onTimeRate: delivered.isEmpty ? 0 : onTime / delivered.length,
        nextReleaseAt: _nextRelease(),
      ),
    );
  }

  @override
  Future<List<SupplierSupplyRequest>> supplyRequests() =>
      _latency(List<SupplierSupplyRequest>.unmodifiable(_requests));

  @override
  Future<List<SupplyProcessStep>> supplyProcess() =>
      _latency(kSupplyProcessSteps);

  @override
  Future<SupplierSupplyRequest> createSupplyRequest({
    required List<SupplyRequestLine> lines,
    required DateTime neededBy,
    String? note,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (lines.isEmpty) throw ApiException('A request needs at least one line');
    if (lines.any((l) => l.units <= 0)) {
      throw ApiException('Every line needs a quantity above zero');
    }
    if (neededBy.isBefore(DateTime.now())) {
      throw ApiException('The needed-by date is already in the past');
    }
    _nextRequest++;
    final request = SupplierSupplyRequest(
      id: 'sup-req-$_nextRequest',
      reference: 'SR-$_nextRequest',
      createdAt: DateTime(2026, 10, 1),
      status: SupplyRequestStatus.submitted,
      lines: lines,
      neededBy: neededBy,
      note: note,
      events: [
        SupplierSupplyRequestEvent(
          at: DateTime(2026, 10, 1),
          title: 'Submitted',
          detail: 'Sent to MVEC for review',
        ),
      ],
    );
    _requests.insert(0, request);
    return request;
  }

  SupplierSupplyRequest _require(String id) {
    final index = _requests.indexWhere((r) => r.id == id);
    if (index < 0) throw ApiException('No supply request with id $id');
    return _requests[index];
  }

  @override
  Future<SupplierSupplyRequest> cancelSupplyRequest(String id, String reason) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final index = _requests.indexWhere((r) => r.id == id);
    if (index < 0) throw ApiException('No supply request with id $id');
    final request = _requests[index];
    if (!request.canCancel) {
      throw ApiException('${request.reference} is already in flight');
    }
    final cancelled = request.copyWith(
      status: SupplyRequestStatus.cancelled,
      decision: reason,
      updatedAt: DateTime(2026, 10, 2),
      events: [
        ...request.events,
        SupplierSupplyRequestEvent(
          at: DateTime(2026, 10, 2),
          title: 'Cancelled',
          detail: reason,
        ),
      ],
    );
    _requests[index] = cancelled;
    return cancelled;
  }

  @override
  Future<SupplierSupplyRequest> resubmitSupplyRequest(String id) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final index = _requests.indexWhere((r) => r.id == id);
    if (index < 0) throw ApiException('No supply request with id $id');
    final request = _requests[index];
    if (!request.canResubmit) {
      throw ApiException('${request.reference} cannot be resubmitted');
    }
    final resubmitted = request.copyWith(
      status: SupplyRequestStatus.submitted,
      updatedAt: DateTime(2026, 10, 3),
      events: [
        ...request.events,
        SupplierSupplyRequestEvent(
          at: DateTime(2026, 10, 3),
          title: 'Resubmitted',
          detail: 'Back in the review queue',
        ),
      ],
    );
    _requests[index] = resubmitted;
    return resubmitted;
  }

  /// Moves a seeded request into [status] so lifecycle tests have a subject.
  FakeSupplierOperationsService withRequest(SupplierSupplyRequest request) {
    _requests.insert(0, request);
    return this;
  }

  /// A request in [status], built for a lifecycle test.
  static SupplierSupplyRequest requestIn(
    SupplyRequestStatus status, {
    required List<SupplyRequestLine> lines,
    DateTime? neededBy,
    String id = 'sup-req-2001',
    String reference = 'SR-2001',
  }) => SupplierSupplyRequest(
    id: id,
    reference: reference,
    createdAt: DateTime(2026, 9, 1),
    status: status,
    lines: lines,
    neededBy: neededBy ?? DateTime(2026, 11, 1),
    events: [
      SupplierSupplyRequestEvent(
        at: DateTime(2026, 9, 1),
        title: 'Submitted',
        detail: 'Sent to MVEC for review',
      ),
    ],
  );

  /// The default line used across the lifecycle tests.
  static const sampleLine = SupplyRequestLine(
    product: 'Green tea leaves',
    category: 'Beverages',
    units: 40,
    unit: 'kg',
    unitPrice: 8000,
  );

  SupplierSupplyRequest requestById(String id) => _require(id);

  /// The soonest date a release is still scheduled for, if any.
  DateTime? _nextRelease() {
    DateTime? soonest;
    for (final shipment in _shipments) {
      final eta = shipment.eta;
      if (shipment.settledAt != null || eta == null) continue;
      if (soonest == null || eta.isBefore(soonest)) soonest = eta;
    }
    return soonest;
  }
}

class FakeSupplierTeamService implements SupplierTeamService {
  FakeSupplierTeamService({this.delay = Duration.zero});

  final Duration delay;

  final List<TeamMember> _members = <TeamMember>[];

  var _nextId = 0;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  Future<T> _latency<T>(T value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return value;
  }

  /// Populates a roster with one owner and three staff across the roles.
  FakeSupplierTeamService seed() {
    _members.addAll([
      const TeamMember(
        id: 'tm-owner',
        fullName: 'The Account Owner',
        role: TeamRole.owner,
        phone: '+250788000001',
        email: 'owner@example.rw',
        status: TeamMemberStatus.active,
        joinedAt: null,
      ),
      const TeamMember(
        id: 'tm-ops',
        fullName: 'Operations Lead',
        role: TeamRole.operations,
        phone: '+250788000002',
        status: TeamMemberStatus.active,
      ),
      const TeamMember(
        id: 'tm-wh',
        fullName: 'Warehouse',
        role: TeamRole.warehouse,
        phone: '+250788000003',
        status: TeamMemberStatus.active,
      ),
      const TeamMember(
        id: 'tm-fin',
        fullName: 'Finance',
        role: TeamRole.finance,
        phone: '+250788000004',
        status: TeamMemberStatus.suspended,
      ),
    ]);
    return this;
  }

  @override
  Future<List<TeamMember>> members() => _latency(List<TeamMember>.unmodifiable(_members));

  @override
  Future<TeamSummary> summary() => _latency(TeamSummary.fromMembers(_members));

  TeamMember? _byId(String id) {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  void _requireNotDuplicatePhone(String phone, {String? exceptId}) {
    final normalised = normalizeRwandanPhone(phone);
    for (final member in _members) {
      if (member.id == exceptId) continue;
      if (normalizeRwandanPhone(member.phone) == normalised) {
        throw ApiException('${member.fullName} is already on the roster');
      }
    }
  }

  @override
  Future<TeamMember> addMember({
    required String fullName,
    required String phone,
    required TeamRole role,
    String? email,
    String? note,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fullName.trim().isEmpty) throw ApiException('A name is required');
    final normalised = normalizeRwandanPhone(phone);
    if (normalised == null) throw ApiException('$phone is not a Rwandan number');
    if (role.isProtected) {
      throw ApiException('This account already has an owner');
    }
    _requireNotDuplicatePhone(phone);

    _nextId++;
    final member = TeamMember(
      id: 'tm-$_nextId',
      fullName: fullName.trim(),
      role: role,
      phone: formatRwandanPhone(normalised),
      email: email,
      status: TeamMemberStatus.invited,
      note: note,
    );
    _members.add(member);
    return member;
  }

  @override
  Future<TeamMember> updateMember(
    String id, {
    String? fullName,
    String? phone,
    TeamRole? role,
    TeamMemberStatus? status,
    String? email,
    String? note,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final member = _byId(id);
    if (member == null) throw ApiException('No team member with id $id');
    if (member.isOwner) {
      throw ApiException('The account owner cannot be edited');
    }
    if (phone != null) {
      final normalised = normalizeRwandanPhone(phone);
      if (normalised == null) throw ApiException('$phone is not a Rwandan number');
      _requireNotDuplicatePhone(phone, exceptId: id);
    }
    if (fullName != null && fullName.trim().isEmpty) {
      throw ApiException('A name is required');
    }
    // Suspension is a deliberate HR decision: it cannot be undone by flipping
    // the status back from a roster edit.
    if (status == TeamMemberStatus.active &&
        member.status == TeamMemberStatus.suspended) {
      throw ApiException(
        '${member.fullName} was suspended and cannot be reactivated here',
      );
    }

    final updated = TeamMember(
      id: member.id,
      fullName: fullName?.trim() ?? member.fullName,
      role: role ?? member.role,
      phone: phone == null ? member.phone : formatRwandanPhone(normalizeRwandanPhone(phone)!),
      email: email ?? member.email,
      status: status ?? member.status,
      joinedAt: member.joinedAt,
      note: note ?? member.note,
    );
    _members[_members.indexOf(member)] = updated;
    return updated;
  }

  @override
  Future<void> removeMember(String id) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final member = _byId(id);
    if (member == null) throw ApiException('No team member with id $id');
    if (member.isOwner) {
      throw ApiException('The account owner cannot be removed');
    }
    _members.remove(member);
  }

  TeamMember? memberById(String id) => _byId(id);
}