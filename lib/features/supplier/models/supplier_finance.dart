/// Money domain for the supplier "Finance & Insights" module: what a
/// wholesale supplier earned, what MVEC holds in escrow, and how the supplier
/// withdraws the cleared part.
///
/// Modelled on the vendor finance module (`features/vendor/models/
/// vendor_finance.dart`) because a supplier earns through the same pipeline —
/// a vendor order, the platform's cut, escrow, then a withdrawal — with one
/// difference: the supplier side is wholesale, so [SupplierLedgerKind.sale]
/// rows carry bulk quantities and the commission rate is the wholesale rate
/// rather than the retail one.
library;

import '../../../models/user.dart';

/// How money reaches the supplier.
enum SupplierPayoutMethod {
  mtnMomo,
  airtelMoney,
  bankTransfer;

  String get slug => switch (this) {
    SupplierPayoutMethod.mtnMomo => 'MTN_MOMO',
    SupplierPayoutMethod.airtelMoney => 'AIRTEL_MONEY',
    SupplierPayoutMethod.bankTransfer => 'BANK_TRANSFER',
  };

  String get label => switch (this) {
    SupplierPayoutMethod.mtnMomo => 'MTN Mobile Money',
    SupplierPayoutMethod.airtelMoney => 'Airtel Money',
    SupplierPayoutMethod.bankTransfer => 'Bank transfer',
  };

  /// Masked destination shown next to the method as a placeholder, so the payout
  /// form shows the expected shape without inventing an account to withdraw to.
  String get hint => switch (this) {
    SupplierPayoutMethod.mtnMomo => 'MTN MoMo · +250 7•• ••• •••',
    SupplierPayoutMethod.airtelMoney => 'Airtel Money · +250 7•• ••• •••',
    SupplierPayoutMethod.bankTransfer => 'Bank account · •••• ••••',
  };

  /// Mobile money settles instantly, bank transfers take a day or two.
  String get settlementNote => switch (this) {
    SupplierPayoutMethod.mtnMomo =>
      'Arrives on your MoMo wallet within minutes.',
    SupplierPayoutMethod.airtelMoney =>
      'Arrives on your Airtel wallet within minutes.',
    SupplierPayoutMethod.bankTransfer => 'Settles within 1–2 business days.',
  };

  static SupplierPayoutMethod parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll('-', '_');
    return switch (v) {
      'airtel_money' || 'airtel' => SupplierPayoutMethod.airtelMoney,
      'bank' ||
      'bank_transfer' ||
      'banktransfer' => SupplierPayoutMethod.bankTransfer,
      _ => SupplierPayoutMethod.mtnMomo,
    };
  }
}

/// What a single ledger line represents.
enum SupplierLedgerKind {
  sale,
  commission,
  escrowHold,
  escrowRelease,
  payout,
  refund,
  adjustment;

  String get slug => switch (this) {
    SupplierLedgerKind.sale => 'SALE',
    SupplierLedgerKind.commission => 'COMMISSION',
    SupplierLedgerKind.escrowHold => 'ESCROW_HOLD',
    SupplierLedgerKind.escrowRelease => 'ESCROW_RELEASE',
    SupplierLedgerKind.payout => 'PAYOUT',
    SupplierLedgerKind.refund => 'REFUND',
    SupplierLedgerKind.adjustment => 'ADJUSTMENT',
  };

  String get label => switch (this) {
    SupplierLedgerKind.sale => 'Wholesale order',
    SupplierLedgerKind.commission => 'Platform commission',
    SupplierLedgerKind.escrowHold => 'Funds held in escrow',
    SupplierLedgerKind.escrowRelease => 'Escrow released',
    SupplierLedgerKind.payout => 'Withdrawal',
    SupplierLedgerKind.refund => 'Refund',
    SupplierLedgerKind.adjustment => 'Adjustment',
  };

  /// Icon key for the shared icon set, chosen so the row reads at a glance.
  String get icon => switch (this) {
    SupplierLedgerKind.sale => 'cart',
    SupplierLedgerKind.commission => 'tag',
    SupplierLedgerKind.escrowHold => 'shield',
    SupplierLedgerKind.escrowRelease => 'shield',
    SupplierLedgerKind.payout => 'wallet',
    SupplierLedgerKind.refund => 'arrow',
    SupplierLedgerKind.adjustment => 'edit',
  };

  /// Sign convention applied to the amount when rendering. `0` marks a row that
  /// reclassifies money rather than moving it: an escrow hold moves the balance
  /// from "cleared" to "held", so the amount is shown neutral instead of as a
  /// credit or a debit.
  int get sign => switch (this) {
    SupplierLedgerKind.commission ||
    SupplierLedgerKind.payout ||
    SupplierLedgerKind.refund => -1,
    SupplierLedgerKind.escrowHold => 0,
    _ => 1,
  };

  static SupplierLedgerKind parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll('-', '_');
    return switch (v) {
      'commission' || 'fee' || 'platform_fee' => SupplierLedgerKind.commission,
      'escrow_hold' || 'hold' || 'held' => SupplierLedgerKind.escrowHold,
      'escrow_release' ||
      'escrow' ||
      'release' => SupplierLedgerKind.escrowRelease,
      'payout' || 'withdrawal' || 'withdraw' => SupplierLedgerKind.payout,
      'refund' => SupplierLedgerKind.refund,
      'adjustment' || 'adjust' => SupplierLedgerKind.adjustment,
      _ => SupplierLedgerKind.sale,
    };
  }
}

/// One point on the earnings chart.
class SupplierEarningsPoint {
  const SupplierEarningsPoint({
    required this.at,
    required this.net,
    this.units = 0,
  });

  /// Start of the bucket this point covers.
  final DateTime at;

  /// Net earnings for the bucket, after commission.
  final num net;

  /// Units sold in the bucket — lets the analytics page pair revenue with volume.
  final int units;

  factory SupplierEarningsPoint.fromJson(Map<String, dynamic> j) =>
      SupplierEarningsPoint(
        at: parseDate(j['at'] ?? j['date'] ?? j['_id']) ?? DateTime.now(),
        net: _num(j['net'] ?? j['value'] ?? j['amount']) ?? 0,
        units: (_num(j['units']) ?? 0).toInt(),
      );
}

/// The headline money numbers on the supplier Payments page.
class SupplierFinanceSummary {
  const SupplierFinanceSummary({
    this.grossSales = 0,
    this.commission = 0,
    this.netEarnings = 0,
    this.escrowHeld = 0,
    this.availablePayout = 0,
    this.pendingPayouts = 0,
    this.commissionRate = 0.05,
    this.salesDelta = 0,
    this.earningsDelta = 0,
    this.series = const <SupplierEarningsPoint>[],
    this.lastPayoutAt,
  });

  /// Everything the vendors paid for goods, before the platform takes its cut.
  final num grossSales;

  /// MVEC commission deducted across the same period.
  final num commission;

  /// [grossSales] minus [commission] — the supplier's true take.
  final num netEarnings;

  /// Net value MVEC holds for orders that are paid but not yet delivered.
  final num escrowHeld;

  /// Cleared money the supplier can withdraw right now.
  final num availablePayout;

  /// Sum of withdrawal requests still processing, reserved from
  /// [availablePayout] so the same money cannot be requested twice.
  final num pendingPayouts;

  /// Wholesale commission rate, shown as a footnote under the commission card.
  final num commissionRate;

  /// Period-over-period change, as a fraction (`0.12` = +12%).
  final num salesDelta;
  final num earningsDelta;

  /// Daily net earnings for the chart on the payments page.
  final List<SupplierEarningsPoint> series;

  /// When the last settled withdrawal landed, if any.
  final DateTime? lastPayoutAt;

  /// Total MVEC is holding for the supplier: escrow plus in-flight withdrawals.
  /// Explains why gross sales exceed the withdrawable balance.
  num get totalHeld => escrowHeld + pendingPayouts;

  /// Sanity invariant asserted in tests: the net figure must equal gross minus
  /// commission.
  bool get isConsistent => (netEarnings - (grossSales - commission)).abs() < 1;

  factory SupplierFinanceSummary.fromJson(
    Map<String, dynamic> j,
  ) => SupplierFinanceSummary(
    grossSales: _num(j['grossSales'] ?? j['totalRevenue'] ?? j['revenue']) ?? 0,
    commission:
        _num(j['commission'] ?? j['platformCommission'] ?? j['fees']) ?? 0,
    netEarnings: _num(j['netEarnings'] ?? j['earnings']) ?? 0,
    escrowHeld: _num(j['escrowHeld'] ?? j['protectedFunds']) ?? 0,
    availablePayout:
        _num(
          j['availablePayout'] ?? j['availableBalance'] ?? j['payoutBalance'],
        ) ??
        0,
    pendingPayouts: _num(j['pendingPayouts'] ?? j['processingPayouts']) ?? 0,
    commissionRate: _num(j['commissionRate'] ?? j['platformFeeRate']) ?? 0.05,
    salesDelta: _num(j['salesDelta'] ?? j['revenueDelta']) ?? 0,
    earningsDelta: _num(j['earningsDelta']) ?? 0,
    series:
        _list(
          j['series'] ?? j['trend'],
        ).map(SupplierEarningsPoint.fromJson).toList(),
    lastPayoutAt: parseDate(j['lastPayoutAt'] ?? j['lastPayout']),
  );
}

/// A movement on the supplier's money ledger.
///
/// [amount] is always stored as a positive magnitude;
/// [SupplierLedgerKind.sign] decides the direction, so the ledger never
/// double-negates a backend value.
class SupplierLedgerEntry {
  const SupplierLedgerEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.amount,
    required this.description,
    this.orderNumber,
    this.balanceAfter,
    this.units = 0,
    this.payoutMethod,
    this.payoutStatus,
  });

  final String id;
  final DateTime at;
  final SupplierLedgerKind kind;
  final num amount;
  final String description;

  /// Set on rows that belong to a vendor order, so the row can be reconciled
  /// against the Orders page.
  final String? orderNumber;

  /// Units moved, for order rows — the wholesale counterpart of [amount].
  final int units;

  /// Running cleared balance once this entry posted — makes the ledger
  /// self-checking.
  final num? balanceAfter;

  final SupplierPayoutMethod? payoutMethod;

  /// `PENDING` / `PAID` / `FAILED` for withdrawal rows.
  final String? payoutStatus;

  /// Signed amount for display: positive for money in, negative for money out,
  /// and the plain magnitude for an escrow hold.
  num get signedAmount => amount * kind.sign;

  /// True for rows that leave the supplier's cleared balance.
  bool get isCredit => kind.sign > 0;

  /// True for rows that reclassify money instead of moving it.
  bool get isNeutral => kind.sign == 0;

  factory SupplierLedgerEntry.fromJson(Map<String, dynamic> j) {
    final method = j['method'] ?? j['payoutMethod'];
    return SupplierLedgerEntry(
      id: '${j['_id'] ?? j['id'] ?? ''}',
      at: parseDate(j['at'] ?? j['createdAt'] ?? j['date']) ?? DateTime.now(),
      kind: SupplierLedgerKind.parse('${j['kind'] ?? j['type'] ?? ''}'),
      amount: (_num(j['amount'] ?? j['total']) ?? 0).abs(),
      description:
          '${j['description'] ?? j['note'] ?? j['title'] ?? 'Transaction'}',
      orderNumber: j['orderNumber'] == null ? null : '${j['orderNumber']}',
      units: (_num(j['units'] ?? j['quantity']) ?? 0).toInt(),
      balanceAfter: _num(j['balanceAfter'] ?? j['balance']),
      payoutMethod:
          method == null ? null : SupplierPayoutMethod.parse('$method'),
      payoutStatus: j['payoutStatus'] == null ? null : '${j['payoutStatus']}',
    );
  }
}

/// A withdrawal the supplier has requested.
class SupplierPayoutRequest {
  const SupplierPayoutRequest({
    required this.id,
    required this.amount,
    required this.method,
    required this.requestedAt,
    this.status = 'PENDING',
    this.destination,
    this.note,
    this.arrivedAt,
  });

  final String id;
  final num amount;
  final SupplierPayoutMethod method;
  final DateTime requestedAt;

  /// `PENDING` | `PAID` | `FAILED` | `REJECTED`.
  final String status;

  /// The phone number or bank account the money goes to.
  final String? destination;
  final String? note;
  final DateTime? arrivedAt;

  bool get isPending => status == 'PENDING';
  bool get isSettled => status == 'PAID';

  factory SupplierPayoutRequest.fromJson(Map<String, dynamic> j) =>
      SupplierPayoutRequest(
        id: '${j['_id'] ?? j['id'] ?? ''}',
        amount: (_num(j['amount']) ?? 0),
        method: SupplierPayoutMethod.parse(
          '${j['method'] ?? j['payoutMethod'] ?? ''}',
        ),
        requestedAt:
            parseDate(j['requestedAt'] ?? j['createdAt'] ?? j['date']) ??
            DateTime.now(),
        status: '${j['status'] ?? 'PENDING'}'.toUpperCase(),
        destination: j['destination'] == null ? null : '${j['destination']}',
        note: j['note'] == null ? null : '${j['note']}',
        arrivedAt: parseDate(j['arrivedAt'] ?? j['paidAt']),
      );
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
