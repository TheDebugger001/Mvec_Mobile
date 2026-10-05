import '../../../core/api_client.dart';
import '../models/supplier_finance.dart';
import '../models/supplier_operations.dart';
import 'supplier_operations_service.dart';

/// Local demo implementation of [SupplierOperationsService] for the supplier
/// Delivery & Settlement and Supply Requests pages.
///
/// The consignments reference the same vendor order numbers as
/// `MockSupplierFinanceService` (`MV-4821`, `MV-4814`, …), so the escrow a
/// shipment is holding is the same escrow the Payments page shows.
/// [settlements] is derived from those shipments rather than seeded separately,
/// so the schedule and the shipment list can never disagree: every consignment
/// posts the hold that locked its money, and posts the release once the buyer
/// has signed.
class MockSupplierOperationsService implements SupplierOperationsService {
  MockSupplierOperationsService({
    this.delay = const Duration(milliseconds: 550),
  });

  final Duration delay;

  static const double _commissionRate = 0.05;

  late final List<SupplierShipment> _shipments = _seedShipments();

  /// Requests raised during this session, newest first.
  final List<SupplierSupplyRequest> _sessionRequests = [];

  /// Seeded requests the supplier has changed this session, keyed by id.
  final Map<String, SupplierSupplyRequest> _overrides = {};

  /// Next number in the `SR-20xx` series, continuing past the seeded ones.
  int _nextReference = 2061;

  @override
  bool get isDemo => true;

  @override
  String? get fallbackReason => null;

  Future<void> _latency() => Future<void>.delayed(delay);

  // ── delivery & settlement ─────────────────────────────────────────────────

  @override
  Future<List<SupplierShipment>> shipments() async {
    await _latency();
    return _shipments;
  }

  @override
  Future<List<SupplierSettlementEvent>> settlements() async {
    await _latency();
    return _settlements();
  }

  @override
  Future<DeliverySettlementSummary> deliverySummary() async {
    await _latency();
    return _summary();
  }

  // ── supply requests ───────────────────────────────────────────────────────

  @override
  Future<List<SupplierSupplyRequest>> supplyRequests() async {
    await _latency();
    return [..._sessionRequests, ..._seedRequests()];
  }

  @override
  Future<List<SupplyProcessStep>> supplyProcess() async {
    await _latency();
    return kSupplyProcessSteps;
  }

  @override
  Future<SupplierSupplyRequest> createSupplyRequest({
    required List<SupplyRequestLine> lines,
    required DateTime neededBy,
    String? note,
  }) async {
    if (lines.isEmpty) {
      throw ApiException('Add at least one item to the request');
    }
    for (final line in lines) {
      if (line.product.trim().isEmpty) {
        throw ApiException('Every line needs an item name');
      }
      if (line.units <= 0) {
        throw ApiException('${line.product}: quantity must be at least 1');
      }
    }
    final now = DateTime.now();
    if (neededBy.isBefore(DateTime(now.year, now.month, now.day))) {
      throw ApiException('Pick a needed-by date from today onwards');
    }

    await _latency();
    final createdAt = DateTime.now();
    final request = SupplierSupplyRequest(
      id: 'sup-req-session-$_nextReference',
      reference: 'SR-${_nextReference++}',
      createdAt: createdAt,
      status: SupplyRequestStatus.submitted,
      lines: lines,
      neededBy: neededBy,
      note: _clean(note),
      updatedAt: createdAt,
      events: [
        SupplierSupplyRequestEvent(
          at: createdAt,
          title: 'Request submitted',
          detail:
              'Sent to the ${lines.first.category} category manager for '
              'review.',
        ),
      ],
    );
    _sessionRequests.insert(0, request);
    return request;
  }

  @override
  Future<SupplierSupplyRequest> cancelSupplyRequest(
    String id,
    String reason,
  ) async {
    final request = _find(id);
    if (!request.status.canCancel) {
      throw ApiException(
        '${request.reference} is already '
        '${request.status.label.toLowerCase()} and can no longer be withdrawn',
      );
    }
    await _latency();
    final now = DateTime.now();
    final cancelled = request.copyWith(
      status: SupplyRequestStatus.cancelled,
      decision:
          _clean(reason) == null
              ? 'Withdrawn by the supplier'
              : 'Withdrawn by the supplier · ${reason.trim()}',
      updatedAt: now,
      events: [
        ...request.events,
        SupplierSupplyRequestEvent(
          at: now,
          title: 'Request withdrawn',
          detail:
              _clean(reason) == null
                  ? 'The supplier withdrew this request.'
                  : 'The supplier withdrew this request · ${reason.trim()}',
        ),
      ],
    );
    return _remember(cancelled);
  }

  @override
  Future<SupplierSupplyRequest> resubmitSupplyRequest(String id) async {
    final request = _find(id);
    if (!request.status.canResubmit) {
      throw ApiException(
        '${request.reference} is '
        '${request.status.label.toLowerCase()} and cannot be resubmitted',
      );
    }
    await _latency();
    final now = DateTime.now();
    final resubmitted = SupplierSupplyRequest(
      // A fresh reference, so the supplier can tell the two attempts apart.
      id: 'sup-req-session-$_nextReference',
      reference: 'SR-${_nextReference++}',
      createdAt: now,
      status: SupplyRequestStatus.submitted,
      lines: request.lines,
      neededBy: request.neededBy,
      note: request.note,
      updatedAt: now,
      events: [
        SupplierSupplyRequestEvent(
          at: now,
          title: 'Request resubmitted',
          detail: 'Sent back to the category manager for review.',
        ),
      ],
    );
    _sessionRequests.insert(0, resubmitted);
    return resubmitted;
  }

  // ── derivations ──────────────────────────────────────────────────────────

  /// The settlement schedule, newest first.
  ///
  /// Each consignment contributes two rows: the hold that locked its money, and
  /// the release that frees it. A release carries a date only when one is
  /// genuinely known — once it is with the courier, and again once the buyer has
  /// signed — so a row never promises a date MVEC has not committed to.
  List<SupplierSettlementEvent> _settlements() {
    final events = <SupplierSettlementEvent>[];

    for (final shipment in _shipments) {
      final placedAt = shipment.milestoneFor(DeliveryStage.confirmed)?.at;
      if (placedAt == null) continue;

      events.add(
        SupplierSettlementEvent(
          id: 'sup-set-${shipment.id}-hold',
          at: placedAt.add(const Duration(minutes: 20)),
          kind: SupplierLedgerKind.escrowHold,
          amount: shipment.net,
          description:
              'Held until ${shipment.orderNumber} is delivered to '
              '${shipment.buyer}',
          orderNumber: shipment.orderNumber,
          settledAt: shipment.settledAt,
        ),
      );

      // A release only enters the schedule once the goods are actually moving.
      // Before that the hold is the whole story, and listing a release with no
      // date would read as a paused payment rather than a not-yet-due one.
      if (shipment.stage.index >= DeliveryStage.dispatched.index) {
        events.add(
          SupplierSettlementEvent(
            id: 'sup-set-${shipment.id}-release',
            at: shipment.milestoneFor(DeliveryStage.dispatched)?.at ?? placedAt,
            kind: SupplierLedgerKind.escrowRelease,
            amount: shipment.net,
            description:
                shipment.isOnHold
                    ? 'Release paused for ${shipment.orderNumber} · '
                        '${shipment.holdReason}'
                    : 'Delivery confirmed for ${shipment.orderNumber}',
            orderNumber: shipment.orderNumber,
            // No expected date while a dispute is open: [SupplierSettlementEvent
            // .isPaused] treats a dateless release as paused, which is what the
            // ledger shows the supplier.
            expectedAt:
                shipment.isOnHold
                    ? null
                    : shipment.isAwaitingSettlement
                    ? shipment.eta
                    : shipment.deliveredAt,
            settledAt: shipment.settledAt,
          ),
        );
      }
    }

    for (final payout in _payouts) {
      events.add(
        SupplierSettlementEvent(
          id: 'sup-set-payout-${payout.daysAgo}',
          at: _ago(payout.daysAgo),
          kind: SupplierLedgerKind.payout,
          amount: payout.amount,
          description: 'Withdrawal to ${payout.method}',
          // A negative offset means the money has not landed yet.
          expectedAt: _ago(payout.daysAgo - payout.arrivalOffset),
          settledAt:
              payout.arrivalOffset <= 0
                  ? _ago(payout.daysAgo - payout.arrivalOffset)
                  : null,
        ),
      );
    }

    events.sort((a, b) => a.timelineAt.compareTo(b.timelineAt));
    return events.reversed.toList();
  }

  DeliverySettlementSummary _summary() {
    final now = DateTime.now();
    final monthAgo = now.subtract(const Duration(days: 30));

    final delivered = _shipments.where((s) => s.deliveredAt != null).toList();
    final upcoming =
        _settlements()
            .where((e) => e.isScheduled && e.timelineAt.isAfter(now))
            .map((e) => e.timelineAt)
            .toList()
          ..sort();

    final releasedThisPeriod = _settlements()
        .where(
          (e) =>
              e.kind == SupplierLedgerKind.escrowRelease &&
              e.isSettled &&
              e.settledAt!.isAfter(monthAgo),
        )
        .fold<num>(0, (sum, e) => sum + e.amount);

    final onTime =
        delivered
            .where((s) => s.eta == null || !s.deliveredAt!.isAfter(s.eta!))
            .length;

    return DeliverySettlementSummary(
      activeShipments: _shipments.where((s) => !s.isDelivered).length,
      deliveredThisMonth:
          delivered.where((s) => s.deliveredAt!.isAfter(monthAgo)).length,
      inEscrow: _shipments.fold<num>(0, (sum, s) => sum + s.escrowAmount),
      // A release date is only booked once the consignment is with the courier.
      scheduled: _shipments
          .where((s) => s.isAwaitingSettlement && s.settledAt == null)
          .fold<num>(0, (sum, s) => sum + s.net),
      releasedThisPeriod: releasedThisPeriod,
      heldOrders: _shipments.where((s) => s.isOnHold).length,
      onTimeRate:
          delivered.isEmpty ? 0 : (onTime / delivered.length).toDouble(),
      nextReleaseAt: upcoming.isEmpty ? null : upcoming.first,
    );
  }

  SupplierSupplyRequest _find(String id) {
    for (final request in supplyRequestsNow) {
      if (request.id == id) return request;
    }
    throw ApiException('That supply request no longer exists');
  }

  /// Records a change to a seeded request so it survives being read again.
  SupplierSupplyRequest _remember(SupplierSupplyRequest request) {
    _overrides[request.id] = request;
    final index = _sessionRequests.indexWhere((r) => r.id == request.id);
    if (index >= 0) {
      _sessionRequests[index] = request;
    }
    return request;
  }

  /// The full request list without the latency, for [find] on the write paths.
  List<SupplierSupplyRequest> get supplyRequestsNow => [
    ..._sessionRequests,
    for (final seed in _seedRequestData) _overrides[seed.id] ?? _build(seed),
  ];

  // ── demo dataset ─────────────────────────────────────────────────────────

  static DateTime _ago(int days) =>
      DateTime.now().subtract(Duration(days: days));

  static DateTime _ahead(int days) => DateTime.now().add(Duration(days: days));

  static String? _clean(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  /// The consignments behind the settlement schedule.
  static const _orders = <_SeedShipment>[
    _SeedShipment(
      'MV-4821',
      'Kigali Market Kitchen',
      'Arabica Coffee Beans',
      8,
      100000,
      DeliveryStage.outForDelivery,
      daysAgo: 2,
      courier: 'Mvec Express',
      destination: 'KN 4 Rd, Kigali',
    ),
    _SeedShipment(
      'MV-4814',
      'Fresh Basket Ltd',
      'Fresh Avocados',
      24,
      21600,
      DeliveryStage.dispatched,
      daysAgo: 3,
      courier: 'Mvec Express',
      destination: 'KG 12 Ave, Kicukiro',
    ),
    _SeedShipment(
      'MV-4792',
      'Diaspora Foods',
      'Raw Forest Honey',
      6,
      46800,
      DeliveryStage.packed,
      daysAgo: 4,
      destination: 'KN 7 Rd, Kigali',
    ),
    _SeedShipment(
      'MV-4760',
      'Agro Fresh Rwanda',
      'Arabica Coffee Beans',
      4,
      50000,
      DeliveryStage.delivered,
      daysAgo: 12,
      courier: 'Mvec Express',
      destination: 'KN 4 Rd, Kigali',
    ),
    _SeedShipment(
      'MV-4745',
      'Kigali Market Kitchen',
      'Raw Forest Honey',
      7,
      52000,
      DeliveryStage.delivered,
      daysAgo: 15,
      courier: 'Mvec Express',
      destination: 'KN 4 Rd, Kigali',
      lateByDays: 1,
    ),
    _SeedShipment(
      'MV-4733',
      'Soko Fresh',
      'Arabica Coffee Beans',
      10,
      125000,
      DeliveryStage.delivered,
      daysAgo: 19,
      courier: 'Mvec Express',
      destination: 'KN 1 Ave, Kigali',
    ),
    _SeedShipment(
      'MV-4701',
      'Agro Fresh Rwanda',
      'Raw Forest Honey',
      6,
      46800,
      DeliveryStage.delivered,
      daysAgo: 26,
      courier: 'Mvec Express',
      destination: 'KG 12 Ave, Kicukiro',
      holdReason: 'Buyer reported two cracked jars — quality check pending',
    ),
  ];

  /// Withdrawals that have already left the cleared balance, so the schedule
  /// shows the outbound side of settlement as well as the inbound.
  static const _payouts = <_SeedPayout>[
    _SeedPayout('MTN Mobile Money', 1800000, 9, 0),
    _SeedPayout('Bank transfer', 1250000, 27, 1),
    _SeedPayout('Airtel Money', 420000, 2, -1),
  ];

  List<SupplierShipment> _seedShipments() => [
    for (final order in _orders)
      SupplierShipment(
        id: 'sup-ship-${order.number}',
        orderNumber: order.number,
        buyer: order.buyer,
        product: order.product,
        units: order.units,
        gross: order.gross,
        net: (order.gross * (1 - _commissionRate)).round(),
        destination: order.destination,
        stage: order.stage,
        milestones: _milestones(order),
        courier: order.courier,
        trackingNumber:
            order.courier == null ? null : 'MVX-${order.number.substring(3)}',
        eta:
            order.stage == DeliveryStage.delivered
                ? _ago(order.daysAgo - 1)
                : _ahead(
                  order.stage.index >= DeliveryStage.dispatched.index ? 1 : 3,
                ),
        deliveredAt:
            order.stage == DeliveryStage.delivered
                ? _ago(order.daysAgo - 1 + (order.lateByDays ?? 0))
                : null,
        // A held consignment has been delivered but its money is still locked.
        settledAt:
            order.stage == DeliveryStage.delivered && order.holdReason == null
                ? _ago(order.daysAgo - 2 + (order.lateByDays ?? 0))
                : null,
        holdReason: order.holdReason,
      ),
  ];

  /// Every stage up to and including the current one gets a date; the rest are
  /// left open, which is how the screen draws the part of the track still to
  /// come.
  static List<SupplierDeliveryMilestone> _milestones(_SeedShipment order) {
    final placedAt = _ago(order.daysAgo);
    return [
      for (var i = 0; i < DeliveryStage.values.length; i++)
        SupplierDeliveryMilestone(
          stage: DeliveryStage.values[i],
          at: i <= order.stage.index ? placedAt.add(Duration(days: i)) : null,
          note:
              i <= order.stage.index
                  ? '${DeliveryStage.values[i].owner} · '
                      '${DeliveryStage.values[i].label.toLowerCase()}'
                  : 'Waiting on ${DeliveryStage.values[i].owner.toLowerCase()}',
        ),
    ];
  }

  List<SupplierSupplyRequest> _seedRequests() => [
    for (final seed in _seedRequestData) _overrides[seed.id] ?? _build(seed),
  ];

  /// Builds a seeded request, including the history its status implies so the
  /// card's timeline is never empty.
  static SupplierSupplyRequest _build(_SeedRequest seed) {
    final createdAt = _ago(seed.createdAgo);
    final events = <SupplierSupplyRequestEvent>[
      SupplierSupplyRequestEvent(
        at: createdAt,
        title: 'Request submitted',
        detail: 'Sent to MVEC for review.',
      ),
    ];

    var at = createdAt;
    for (var step = 1; step < seed.step; step++) {
      at = at.add(const Duration(days: 3));
      events.add(
        SupplierSupplyRequestEvent(
          at: at,
          title: kSupplyProcessSteps[step].title,
          detail:
              '${kSupplyProcessSteps[step].mvecDoes} · '
              '${kSupplyProcessSteps[step].timeframe}',
        ),
      );
    }

    return SupplierSupplyRequest(
      id: seed.id,
      reference: seed.reference,
      createdAt: createdAt,
      status: seed.status,
      lines: seed.lines,
      neededBy: _ahead(seed.neededInDays),
      note: seed.note,
      decision: _decisionFor(seed.status),
      updatedAt: events.last.at,
      events: events,
    );
  }

  /// Only the statuses that ended in a decision carry one.
  static String? _decisionFor(SupplyRequestStatus status) => switch (status) {
    SupplyRequestStatus.rejected =>
      'We cannot source this volume for the date you need',
    SupplyRequestStatus.cancelled => 'Withdrawn by the supplier',
    SupplyRequestStatus.received => 'Goods received and checked',
    _ => null,
  };

  /// The seeded request history.
  static const _seedRequestData = <_SeedRequest>[
    _SeedRequest(
      'sup-req-2060',
      'SR-2060',
      createdAgo: 1,
      status: SupplyRequestStatus.submitted,
      step: 1,
      neededInDays: 9,
      note: 'Topping up before the Kigali trade fair.',
      lines: [
        SupplyRequestLine(
          product: 'Arabica Coffee Beans',
          category: 'Beverages',
          units: 40,
          unit: 'kg',
          unitPrice: 12500,
        ),
        SupplyRequestLine(
          product: 'Dried Red Kidney Beans',
          category: 'Grains & pulses',
          units: 150,
          unit: 'kg',
          unitPrice: 2400,
        ),
      ],
    ),
    _SeedRequest(
      'sup-req-2057',
      'SR-2057',
      createdAgo: 3,
      status: SupplyRequestStatus.underReview,
      step: 2,
      neededInDays: 14,
      note: 'Lot details for the Nyungwe harvest will follow.',
      lines: [
        SupplyRequestLine(
          product: 'Raw Forest Honey',
          category: 'Pantry',
          units: 60,
          unit: 'kg',
          unitPrice: 7800,
        ),
      ],
    ),
    _SeedRequest(
      'sup-req-2054',
      'SR-2054',
      createdAgo: 6,
      status: SupplyRequestStatus.sourcing,
      step: 4,
      neededInDays: 18,
      lines: [
        SupplyRequestLine(
          product: 'Fresh Avocados',
          category: 'Produce',
          units: 300,
          unit: 'kg',
          unitPrice: 900,
        ),
        SupplyRequestLine(
          product: 'Arabica Coffee Beans',
          category: 'Beverages',
          units: 20,
          unit: 'kg',
          unitPrice: 12500,
        ),
      ],
    ),
    _SeedRequest(
      'sup-req-2051',
      'SR-2051',
      createdAgo: 10,
      status: SupplyRequestStatus.inTransit,
      step: 5,
      neededInDays: 16,
      note: 'Deliver to the KG 12 Ave depot.',
      lines: [
        SupplyRequestLine(
          product: 'Dried Red Kidney Beans',
          category: 'Grains & pulses',
          units: 200,
          unit: 'kg',
          unitPrice: 2400,
        ),
      ],
    ),
    _SeedRequest(
      'sup-req-2048',
      'SR-2048',
      createdAgo: 24,
      status: SupplyRequestStatus.received,
      step: 6,
      neededInDays: -19,
      note: 'Checked and shelved, no breakages.',
      lines: [
        SupplyRequestLine(
          product: 'Raw Forest Honey',
          category: 'Pantry',
          units: 45,
          unit: 'kg',
          unitPrice: 7800,
        ),
      ],
    ),
    _SeedRequest(
      'sup-req-2043',
      'SR-2043',
      createdAgo: 31,
      status: SupplyRequestStatus.cancelled,
      step: 0,
      neededInDays: -13,
      note: 'Withdrawn — the buyer cancelled the standing order.',
      lines: [
        SupplyRequestLine(
          product: 'Arabica Coffee Beans',
          category: 'Beverages',
          units: 25,
          unit: 'kg',
          unitPrice: 12500,
        ),
      ],
    ),
  ];
}

/// A seed row for one consignment.
class _SeedShipment {
  const _SeedShipment(
    this.number,
    this.buyer,
    this.product,
    this.units,
    this.gross,
    this.stage, {
    required this.daysAgo,
    this.courier,
    this.destination = 'Kigali',
    this.lateByDays,
    this.holdReason,
  });

  final String number;
  final String buyer;
  final String product;
  final int units;
  final num gross;
  final DeliveryStage stage;

  /// Days since the order was placed.
  final int daysAgo;

  final String? courier;
  final String destination;

  /// How many days past the promised date the buyer signed, if it was late.
  final int? lateByDays;

  final String? holdReason;
}

/// A seed row for one withdrawal in the settlement schedule.
class _SeedPayout {
  const _SeedPayout(this.method, this.amount, this.daysAgo, this.arrivalOffset);

  final String method;
  final num amount;

  /// Days ago the withdrawal was requested.
  final int daysAgo;

  /// Days from the request to the money landing; negative means still in flight.
  final int arrivalOffset;
}

/// A seed row for one supply request.
class _SeedRequest {
  const _SeedRequest(
    this.id,
    this.reference, {
    required this.createdAgo,
    required this.status,
    required this.step,
    required this.neededInDays,
    this.note,
    this.lines = const <SupplyRequestLine>[],
  });

  final String id;
  final String reference;

  /// Days since the request was raised.
  final int createdAgo;

  final SupplyRequestStatus status;

  /// How many steps of [kSupplyProcessSteps] it has completed; 0 when it did not
  /// complete at all.
  final int step;

  /// Days from now the goods are needed by; negative when already past.
  final int neededInDays;

  final String? note;
  final List<SupplyRequestLine> lines;
}
