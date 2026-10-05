/// Inbound supply, delivery milestones and settlement for the supplier portal.
///
/// These three concerns share one file because they share one lifecycle: a
/// supply request brings goods in, those goods ship out on a vendor order, and
/// the money for that order moves through escrow until the delivery milestone
/// releases it. [SupplierSettlementEvent] reuses [SupplierLedgerKind] from the
/// finance module so a settlement row can be matched against the ledger row it
/// belongs to on the Payments page.
library;

import '../../../models/user.dart';
import 'supplier_finance.dart';

// ── delivery ───────────────────────────────────────────────────────────────

/// Where a consignment has got to. Ordered, so [index] is the progress.
enum DeliveryStage {
  confirmed,
  packed,
  dispatched,
  outForDelivery,
  delivered;

  String get slug => switch (this) {
    DeliveryStage.confirmed => 'CONFIRMED',
    DeliveryStage.packed => 'PACKED',
    DeliveryStage.dispatched => 'DISPATCHED',
    DeliveryStage.outForDelivery => 'OUT_FOR_DELIVERY',
    DeliveryStage.delivered => 'DELIVERED',
  };

  String get label => switch (this) {
    DeliveryStage.confirmed => 'Confirmed',
    DeliveryStage.packed => 'Packed & labelled',
    DeliveryStage.dispatched => 'Dispatched',
    DeliveryStage.outForDelivery => 'Out for delivery',
    DeliveryStage.delivered => 'Delivered',
  };

  String get icon => switch (this) {
    DeliveryStage.confirmed => 'check',
    DeliveryStage.packed => 'box',
    DeliveryStage.dispatched => 'cart',
    DeliveryStage.outForDelivery => 'arrow',
    DeliveryStage.delivered => 'wallet',
  };

  /// Who moves the consignment forward at this step.
  String get owner => switch (this) {
    DeliveryStage.confirmed => 'MVEC warehouse',
    DeliveryStage.packed => 'MVEC warehouse',
    DeliveryStage.dispatched => 'Courier',
    DeliveryStage.outForDelivery => 'Courier',
    DeliveryStage.delivered => 'Buyer',
  };

  static DeliveryStage parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll('-', '_');
    return switch (v) {
      'packed' || 'packaged' => DeliveryStage.packed,
      'dispatched' || 'shipped' => DeliveryStage.dispatched,
      'out_for_delivery' || 'outfordelivery' => DeliveryStage.outForDelivery,
      'delivered' || 'completed' => DeliveryStage.delivered,
      _ => DeliveryStage.confirmed,
    };
  }
}

/// One dated step on a shipment's track. Future steps carry no [at], which is
/// how the screen draws the dashed part of the line.
class SupplierDeliveryMilestone {
  const SupplierDeliveryMilestone({required this.stage, this.at, this.note});

  final DeliveryStage stage;
  final DateTime? at;
  final String? note;

  bool get isDone => at != null;

  factory SupplierDeliveryMilestone.fromJson(Map<String, dynamic> j) =>
      SupplierDeliveryMilestone(
        stage: DeliveryStage.parse('${j['stage'] ?? j['status'] ?? ''}'),
        at: parseDate(j['at'] ?? j['happenedAt'] ?? j['date']),
        note: j['note'] == null ? null : '${j['note']}',
      );
}

/// A consignment travelling to a vendor, and the money behind it.
class SupplierShipment {
  const SupplierShipment({
    required this.id,
    required this.orderNumber,
    required this.buyer,
    required this.product,
    required this.units,
    required this.gross,
    required this.net,
    required this.destination,
    required this.stage,
    this.milestones = const <SupplierDeliveryMilestone>[],
    this.courier,
    this.trackingNumber,
    this.eta,
    this.deliveredAt,
    this.settledAt,
    this.holdReason,
  });

  final String id;

  /// The vendor order this consignment fulfils — the join key back to the
  /// finance ledger and the Orders page.
  final String orderNumber;
  final String buyer;
  final String product;
  final int units;

  /// Order value before MVEC's wholesale commission.
  final num gross;

  /// [gross] less commission: what the supplier actually earns, and therefore
  /// what escrow holds for this order.
  final num net;

  final String destination;
  final DeliveryStage stage;
  final List<SupplierDeliveryMilestone> milestones;
  final String? courier;
  final String? trackingNumber;

  /// Promised delivery date. Compared against [deliveredAt] for on-time rate.
  final DateTime? eta;
  final DateTime? deliveredAt;

  /// When escrow released the [net] for this order.
  final DateTime? settledAt;

  /// Why the release is being held back, when a dispute or quality check has
  /// paused it.
  final String? holdReason;

  bool get isDelivered => stage == DeliveryStage.delivered;
  bool get isOnHold => holdReason != null;

  /// Money still locked in escrow for this consignment.
  num get escrowAmount => settledAt == null ? net : 0;

  int get stageIndex => stage.index;

  /// 0 at confirmed, 1 at delivered.
  double get progress => stageIndex / (DeliveryStage.values.length - 1);

  DeliveryStage? get nextStage =>
      isDelivered ? null : DeliveryStage.values[stageIndex + 1];

/// True when a release date is known but the money has not moved yet.
///
/// A consignment on hold is excluded: its release is paused, so there is no
/// date to be waiting for.
bool get isAwaitingSettlement =>
    settledAt == null && !isOnHold && stage.index >= DeliveryStage.dispatched.index;

  SupplierDeliveryMilestone? milestoneFor(DeliveryStage target) {
    for (final milestone in milestones) {
      if (milestone.stage == target) return milestone;
    }
    return null;
  }

  factory SupplierShipment.fromJson(Map<String, dynamic> j) => SupplierShipment(
    id: '${j['_id'] ?? j['id'] ?? ''}',
    orderNumber: '${j['orderNumber'] ?? j['order'] ?? ''}',
    buyer: '${j['buyer'] ?? 'Marketplace buyer'}',
    product: '${j['product'] ?? 'Wholesale item'}',
    units: (_num(j['units'] ?? j['quantity']) ?? 0).toInt(),
    gross: _num(j['gross'] ?? j['total']) ?? 0,
    net: _num(j['net'] ?? j['earnings']) ?? 0,
    destination: '${j['destination'] ?? 'Kigali'}',
    stage: DeliveryStage.parse('${j['stage'] ?? j['status'] ?? ''}'),
    milestones:
        _list(j['milestones']).map(SupplierDeliveryMilestone.fromJson).toList(),
    courier: j['courier'] == null ? null : '${j['courier']}',
    trackingNumber:
        j['trackingNumber'] == null ? null : '${j['trackingNumber']}',
    eta: parseDate(j['eta'] ?? j['expectedAt']),
    deliveredAt: parseDate(j['deliveredAt']),
    settledAt: parseDate(j['settledAt'] ?? j['releasedAt']),
    holdReason: j['holdReason'] == null ? null : '${j['holdReason']}',
  );
}

// ── settlement ─────────────────────────────────────────────────────────────

/// One movement of the settlement schedule: escrow held, released, or a
/// withdrawal on its way out.
///
/// [SupplierLedgerKind] is reused on purpose — an escrow release here and an
/// ESCROW_RELEASE row on the Payments ledger describe the same money, so a
/// supplier can reconcile the two pages by order number.
class SupplierSettlementEvent {
  const SupplierSettlementEvent({
    required this.id,
    required this.at,
    required this.kind,
    required this.amount,
    required this.description,
    this.orderNumber,
    this.expectedAt,
    this.settledAt,
  });

  final String id;

  /// When the event was booked.
  final DateTime at;
  final SupplierLedgerKind kind;
  final num amount;
  final String description;
  final String? orderNumber;

  /// When the money is due to move, for anything still in the future.
  final DateTime? expectedAt;

  /// When it actually moved. Null while the event is still outstanding.
  final DateTime? settledAt;

  bool get isSettled => settledAt != null;

  /// Outstanding: has a date but has not moved yet.
  bool get isScheduled => settledAt == null && expectedAt != null;

  /// Booked but stopped — a release MVEC has taken on and is not paying out,
  /// typically because the buyer raised a dispute. Carries no date, because no
  /// date can honestly be promised while it is paused.
  bool get isPaused =>
      settledAt == null &&
      expectedAt == null &&
      kind != SupplierLedgerKind.escrowHold;

  /// The date this event belongs to on the timeline.
  DateTime get timelineAt => settledAt ?? expectedAt ?? at;

  factory SupplierSettlementEvent.fromJson(Map<String, dynamic> j) =>
      SupplierSettlementEvent(
        id: '${j['_id'] ?? j['id'] ?? ''}',
        at: parseDate(j['at'] ?? j['createdAt'] ?? j['date']) ?? DateTime.now(),
        kind: SupplierLedgerKind.parse('${j['kind'] ?? j['type'] ?? ''}'),
        amount: (_num(j['amount'] ?? j['total']) ?? 0).abs(),
        description: '${j['description'] ?? j['note'] ?? 'Settlement'}',
        orderNumber: j['orderNumber'] == null ? null : '${j['orderNumber']}',
        expectedAt: parseDate(j['expectedAt'] ?? j['scheduledFor']),
        settledAt: parseDate(j['settledAt'] ?? j['releasedAt'] ?? j['paidAt']),
      );
}

/// Headline counters for the Delivery & Settlement page, all derived from the
/// shipments and settlement events underneath so the cards cannot disagree with
/// the lists below them.
class DeliverySettlementSummary {
  const DeliverySettlementSummary({
    this.activeShipments = 0,
    this.deliveredThisMonth = 0,
    this.inEscrow = 0,
    this.scheduled = 0,
    this.releasedThisPeriod = 0,
    this.heldOrders = 0,
    this.onTimeRate = 0,
    this.nextReleaseAt,
  });

  /// Consignments that have not reached the buyer yet.
  final int activeShipments;

  /// Consignments delivered in the last 30 days.
  final int deliveredThisMonth;

  /// Money MVEC is holding right now.
  final num inEscrow;

  /// Money with a release date already set, waiting on the delivery milestone.
  final num scheduled;

  /// Money that left escrow in the last 30 days.
  final num releasedThisPeriod;

  /// Consignments whose release is paused.
  final int heldOrders;

  /// Share of delivered consignments that landed on or before their [eta], as a
  /// fraction. Zero when nothing has been delivered yet.
  final double onTimeRate;

  /// Earliest date escrow is due to release anything.
  final DateTime? nextReleaseAt;

  /// Total value moving through the pipeline: locked now plus due later.
  num get pipelineValue => inEscrow + scheduled;

  /// Fraction of the pipeline already released, for the progress bar.
  double get releasedShare {
    final total = pipelineValue + releasedThisPeriod;
    return total == 0 ? 0 : releasedThisPeriod / total;
  }

  factory DeliverySettlementSummary.fromJson(Map<String, dynamic> j) =>
      DeliverySettlementSummary(
        activeShipments: (_num(j['activeShipments']) ?? 0).toInt(),
        deliveredThisMonth: (_num(j['deliveredThisMonth']) ?? 0).toInt(),
        inEscrow: _num(j['inEscrow']) ?? 0,
        scheduled: _num(j['scheduled']) ?? 0,
        releasedThisPeriod: _num(j['releasedThisPeriod']) ?? 0,
        heldOrders: (_num(j['heldOrders']) ?? 0).toInt(),
        onTimeRate: (_num(j['onTimeRate']) ?? 0).toDouble(),
        nextReleaseAt: parseDate(j['nextReleaseAt']),
      );
}

// ── supply requests ────────────────────────────────────────────────────────

/// Where a supply request has got to in [kSupplyProcessSteps].
enum SupplyRequestStatus {
  submitted,
  underReview,
  approved,
  sourcing,
  inTransit,
  received,
  rejected,
  cancelled;

  String get slug => switch (this) {
    SupplyRequestStatus.submitted => 'SUBMITTED',
    SupplyRequestStatus.underReview => 'UNDER_REVIEW',
    SupplyRequestStatus.approved => 'APPROVED',
    SupplyRequestStatus.sourcing => 'SOURCING',
    SupplyRequestStatus.inTransit => 'IN_TRANSIT',
    SupplyRequestStatus.received => 'RECEIVED',
    SupplyRequestStatus.rejected => 'REJECTED',
    SupplyRequestStatus.cancelled => 'CANCELLED',
  };

  String get label => switch (this) {
    SupplyRequestStatus.submitted => 'Submitted',
    SupplyRequestStatus.underReview => 'Under review',
    SupplyRequestStatus.approved => 'Approved',
    SupplyRequestStatus.sourcing => 'Sourcing',
    SupplyRequestStatus.inTransit => 'In transit',
    SupplyRequestStatus.received => 'Received',
    SupplyRequestStatus.rejected => 'Rejected',
    SupplyRequestStatus.cancelled => 'Cancelled',
  };

  String get icon => switch (this) {
    SupplyRequestStatus.submitted => 'plus',
    SupplyRequestStatus.underReview => 'eye',
    SupplyRequestStatus.approved => 'check',
    SupplyRequestStatus.sourcing => 'search',
    SupplyRequestStatus.inTransit => 'cart',
    SupplyRequestStatus.received => 'box',
    SupplyRequestStatus.rejected => 'shield',
    SupplyRequestStatus.cancelled => 'trash',
  };

  /// The step of the process this status sits on, or null once the request has
  /// ended without completing.
  SupplyProcessStage? get stage => switch (this) {
    SupplyRequestStatus.submitted => SupplyProcessStage.request,
    SupplyRequestStatus.underReview => SupplyProcessStage.review,
    SupplyRequestStatus.approved => SupplyProcessStage.approval,
    SupplyRequestStatus.sourcing => SupplyProcessStage.sourcing,
    SupplyRequestStatus.inTransit => SupplyProcessStage.dispatch,
    SupplyRequestStatus.received => SupplyProcessStage.receiving,
    SupplyRequestStatus.rejected || SupplyRequestStatus.cancelled => null,
  };

  /// 1-based position on the stepper, or 0 when the request did not complete.
  int get stepNumber => stage == null ? 0 : stage!.index + 1;

  bool get isOpen => stage != null;

  bool get canCancel =>
      this == SupplyRequestStatus.submitted ||
      this == SupplyRequestStatus.underReview ||
      this == SupplyRequestStatus.sourcing;

  bool get canResubmit => this == SupplyRequestStatus.cancelled;

  static SupplyRequestStatus parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll('-', '_');
    return switch (v) {
      'under_review' ||
      'review' ||
      'pending' => SupplyRequestStatus.underReview,
      'approved' || 'accepted' => SupplyRequestStatus.approved,
      'sourcing' || 'purchasing' => SupplyRequestStatus.sourcing,
      'in_transit' ||
      'shipped' ||
      'dispatched' => SupplyRequestStatus.inTransit,
      'received' || 'delivered' || 'completed' => SupplyRequestStatus.received,
      'rejected' || 'declined' => SupplyRequestStatus.rejected,
      'cancelled' || 'canceled' => SupplyRequestStatus.cancelled,
      _ => SupplyRequestStatus.submitted,
    };
  }
}

/// The fixed stages behind every supply request.
enum SupplyProcessStage {
  request,
  review,
  approval,
  sourcing,
  dispatch,
  receiving;

  String get label => switch (this) {
    SupplyProcessStage.request => 'Raise the request',
    SupplyProcessStage.review => 'MVEC reviews it',
    SupplyProcessStage.approval => 'Quote & approval',
    SupplyProcessStage.sourcing => 'Sourcing & quality check',
    SupplyProcessStage.dispatch => 'Dispatch to your store',
    SupplyProcessStage.receiving => 'Receive & settle',
  };

  String get shortLabel => switch (this) {
    SupplyProcessStage.request => 'Request',
    SupplyProcessStage.review => 'Review',
    SupplyProcessStage.approval => 'Approval',
    SupplyProcessStage.sourcing => 'Sourcing',
    SupplyProcessStage.dispatch => 'Dispatch',
    SupplyProcessStage.receiving => 'Settle',
  };
}

/// One step of the supply-request flow, with both sides' responsibilities.
class SupplyProcessStep {
  const SupplyProcessStep({
    required this.stage,
    required this.youDo,
    required this.mvecDoes,
    required this.timeframe,
  });

  final SupplyProcessStage stage;

  /// What the supplier does at this step.
  final String youDo;

  /// What MVEC does at this step.
  final String mvecDoes;

  /// How long the step normally takes.
  final String timeframe;

  String get title => stage.label;

  int get number => stage.index + 1;

  factory SupplyProcessStep.fromJson(Map<String, dynamic> j) =>
      SupplyProcessStep(
        stage: switch ('${j['stage'] ?? ''}') {
          'review' => SupplyProcessStage.review,
          'approval' => SupplyProcessStage.approval,
          'sourcing' => SupplyProcessStage.sourcing,
          'dispatch' => SupplyProcessStage.dispatch,
          'receiving' => SupplyProcessStage.receiving,
          _ => SupplyProcessStage.request,
        },
        youDo: '${j['youDo'] ?? j['supplier'] ?? ''}',
        mvecDoes: '${j['mvecDoes'] ?? j['platform'] ?? ''}',
        timeframe: '${j['timeframe'] ?? j['sla'] ?? ''}',
      );
}

/// The step-by-step flow shown at the top of the Supply Requests page.
///
/// Kept as one constant so the guide, the per-request stepper and the status
/// badges can never tell the supplier different stories.
const kSupplyProcessSteps = <SupplyProcessStep>[
  SupplyProcessStep(
    stage: SupplyProcessStage.request,
    youDo:
        'Pick the items, the quantities and the date you need them in. MVEC '
        'checks availability against your live catalogue as you build the '
        'request.',
    mvecDoes:
        'Logs the request under a reference number and locks the catalogue '
        'prices so the quote cannot move under you.',
    timeframe: 'About 2 minutes',
  ),
  SupplyProcessStep(
    stage: SupplyProcessStage.review,
    youDo:
        'Answer whatever the category manager asks — grade, pack size or the '
        'delivery window you can actually receive at.',
    mvecDoes:
        'A reviewer checks stock, grading and whether the volume is worth '
        'holding for you before quoting.',
    timeframe: 'Same working day',
  ),
  SupplyProcessStep(
    stage: SupplyProcessStage.approval,
    youDo:
        'Accept or decline the quote. Nothing is charged and nothing is '
        'reserved until you accept.',
    mvecDoes:
        'Issues the quote with bulk discount and escrow terms attached, valid '
        'for 7 days.',
    timeframe: '1–2 business days',
  ),
  SupplyProcessStep(
    stage: SupplyProcessStage.sourcing,
    youDo:
        'Send the lot or harvest details if you are reselling a specific '
        'batch, so buyers can be told what they are getting.',
    mvecDoes:
        'Sources the goods, quality checks them and photographs them before '
        'anything is packed.',
    timeframe: '3–7 business days',
  ),
  SupplyProcessStep(
    stage: SupplyProcessStage.dispatch,
    youDo:
        'Confirm the receiving window and who will sign for the delivery at '
        'your store.',
    mvecDoes:
        'Books the consignment with the courier and issues a tracking number '
        'you can follow from the Delivery page.',
    timeframe: '1–2 business days',
  ),
  SupplyProcessStep(
    stage: SupplyProcessStage.receiving,
    youDo:
        'Inspect on arrival and raise a dispute within 48 hours if the goods '
        'do not match the quote.',
    mvecDoes:
        'Releases the funds from escrow to your payout balance once delivery '
        'is confirmed.',
    timeframe: 'Within 24h of confirmation',
  ),
];

/// One line on a supply request.
class SupplyRequestLine {
  const SupplyRequestLine({
    required this.product,
    required this.category,
    required this.units,
    required this.unit,
    required this.unitPrice,
    this.note,
  });

  final String product;
  final String category;
  final int units;
  final String unit;
  final num unitPrice;
  final String? note;

  num get lineTotal => unitPrice * units;

  factory SupplyRequestLine.fromJson(Map<String, dynamic> j) =>
      SupplyRequestLine(
        product: '${j['product'] ?? j['name'] ?? 'Item'}',
        category: '${j['category'] ?? 'General'}',
        units: (_num(j['units'] ?? j['quantity']) ?? 0).toInt(),
        unit: '${j['unit'] ?? 'kg'}',
        unitPrice: _num(j['unitPrice'] ?? j['price']) ?? 0,
        note: j['note'] == null ? null : '${j['note']}',
      );
}

/// One entry in a request's history — what changed, when, and why.
class SupplierSupplyRequestEvent {
  const SupplierSupplyRequestEvent({
    required this.at,
    required this.title,
    required this.detail,
  });

  final DateTime at;
  final String title;
  final String detail;

  factory SupplierSupplyRequestEvent.fromJson(Map<String, dynamic> j) =>
      SupplierSupplyRequestEvent(
        at: parseDate(j['at'] ?? j['createdAt']) ?? DateTime.now(),
        title: '${j['title'] ?? j['status'] ?? 'Updated'}',
        detail: '${j['detail'] ?? j['note'] ?? ''}',
      );
}

/// Stock the supplier has asked MVEC to supply.
class SupplierSupplyRequest {
  const SupplierSupplyRequest({
    required this.id,
    required this.reference,
    required this.createdAt,
    required this.status,
    required this.lines,
    this.neededBy,
    this.note,
    this.decision,
    this.updatedAt,
    this.events = const <SupplierSupplyRequestEvent>[],
  });

  final String id;

  /// Short supplier-facing code, e.g. `SR-2057`.
  final String reference;
  final DateTime createdAt;
  final SupplyRequestStatus status;
  final List<SupplyRequestLine> lines;

  /// When the supplier needs the goods in their store.
  final DateTime? neededBy;

  final String? note;

  /// Why MVEC approved, rejected or paused the request.
  final String? decision;
  final DateTime? updatedAt;

  /// Full history, oldest first.
  final List<SupplierSupplyRequestEvent> events;

  num get totalValue => lines.fold<num>(0, (sum, line) => sum + line.lineTotal);

  int get totalUnits => lines.fold<int>(0, (sum, line) => sum + line.units);

  SupplyProcessStage? get stage => status.stage;

  /// 1-based step the request has reached, or 0 when it did not complete.
  int get stepNumber => status.stepNumber;

  bool get canCancel => status.canCancel;

  bool get canResubmit => status.canResubmit;

  bool get isOpen => status.isOpen;

  /// Days until the goods are needed; negative when the date has passed.
  int? daysUntilNeeded(DateTime now) => neededBy?.difference(now).inDays;

  SupplierSupplyRequest copyWith({
    SupplyRequestStatus? status,
    String? decision,
    DateTime? updatedAt,
    List<SupplierSupplyRequestEvent>? events,
  }) => SupplierSupplyRequest(
    id: id,
    reference: reference,
    createdAt: createdAt,
    status: status ?? this.status,
    lines: lines,
    neededBy: neededBy,
    note: note,
    decision: decision ?? this.decision,
    updatedAt: updatedAt ?? this.updatedAt,
    events: events ?? this.events,
  );

  factory SupplierSupplyRequest.fromJson(Map<String, dynamic> j) =>
      SupplierSupplyRequest(
        id: '${j['_id'] ?? j['id'] ?? ''}',
        reference: '${j['reference'] ?? j['code'] ?? ''}',
        createdAt:
            parseDate(j['createdAt'] ?? j['requestedAt'] ?? j['at']) ??
            DateTime.now(),
        status: SupplyRequestStatus.parse('${j['status'] ?? ''}'),
        lines:
            _list(
              j['lines'] ?? j['items'],
            ).map(SupplyRequestLine.fromJson).toList(),
        neededBy: parseDate(j['neededBy'] ?? j['requiredBy']),
        note: j['note'] == null ? null : '${j['note']}',
        decision: j['decision'] == null ? null : '${j['decision']}',
        updatedAt: parseDate(j['updatedAt'] ?? j['statusChangedAt']),
        events:
            _list(
              j['events'] ?? j['history'],
            ).map(SupplierSupplyRequestEvent.fromJson).toList(),
      );
}

/// Counts for the Supply Requests header strip.
class SupplyRequestSummary {
  const SupplyRequestSummary({
    this.open = 0,
    this.awaitingAction = 0,
    this.inProgress = 0,
    this.closed = 0,
    this.pipelineValue = 0,
    this.oldestOpenDays = 0,
  });

  /// Requests still moving through the six steps.
  final int open;

  /// Submitted or under review — the ones MVEC owes an answer to.
  final int awaitingAction;

  /// Approved, sourcing or in transit.
  final int inProgress;

  /// Received, rejected or cancelled.
  final int closed;

  /// Value of everything still open.
  final num pipelineValue;

  /// Age of the longest-running open request, in days.
  final int oldestOpenDays;

  factory SupplyRequestSummary.fromRequests(List<SupplierSupplyRequest> rows) {
    final open = rows.where((r) => r.isOpen).toList();
    final now = DateTime.now();
    return SupplyRequestSummary(
      open: open.length,
      awaitingAction:
          rows
              .where(
                (r) =>
                    r.status == SupplyRequestStatus.submitted ||
                    r.status == SupplyRequestStatus.underReview,
              )
              .length,
      inProgress:
          rows
              .where(
                (r) =>
                    r.status == SupplyRequestStatus.approved ||
                    r.status == SupplyRequestStatus.sourcing ||
                    r.status == SupplyRequestStatus.inTransit,
              )
              .length,
      closed: rows.where((r) => !r.isOpen).length,
      pipelineValue: open.fold<num>(0, (sum, r) => sum + r.totalValue),
      oldestOpenDays:
          open.isEmpty
              ? 0
              : open
                  .map((r) => now.difference(r.createdAt).inDays)
                  .reduce((a, b) => a > b ? a : b),
    );
  }
}

// ── parsing helpers ────────────────────────────────────────────────────────
num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);

List<Map<String, dynamic>> _list(dynamic value) =>
    value is List
        ? value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];
