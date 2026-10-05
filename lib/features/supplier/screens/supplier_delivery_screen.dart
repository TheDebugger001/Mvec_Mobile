import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../models/supplier_operations.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_ops_widgets.dart';

/// Delivery milestones and the escrow schedule they drive.
///
/// The two halves of the page answer the two questions a supplier asks about a
/// consignment: "where is it?" and "when does the money land?". Every figure in
/// the header is derived from the same shipments and settlement rows rendered
/// below, and the rows carry the same order numbers as the finance ledger, so
/// the two pages can always be reconciled by order.
class SupplierDeliveryScreen extends ConsumerStatefulWidget {
  const SupplierDeliveryScreen({super.key});

  @override
  ConsumerState<SupplierDeliveryScreen> createState() =>
      _SupplierDeliveryScreenState();
}

class _SupplierDeliveryScreenState
    extends ConsumerState<SupplierDeliveryScreen> {
  _ShipmentFilter _shipmentFilter = _ShipmentFilter.onTheRoad;
  _SettlementFilter _settlementFilter = _SettlementFilter.all;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(supplierDeliverySummaryProvider);
    final shipmentsAsync = ref.watch(supplierShipmentsProvider);
    final settlementsAsync = ref.watch(supplierSettlementsProvider);
    final fallback = ref.watch(supplierOperationsModuleProvider).fallbackReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'OPERATIONS',
          title: 'Delivery & settlement',
          subtitle:
              'Follow every consignment to the buyer and watch the escrow it '
              'holds, release by release.',
        ),
        if (fallback != null) ...[
          InfoBox(fallback, icon: 'bell'),
          const SizedBox(height: 14),
        ],
        switch (summaryAsync) {
          AsyncLoading() => const SizedBox(height: 120, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierDeliverySummaryProvider),
          ),
          AsyncData(:final value) => _metrics(context, value),
          _ => const SizedBox(height: 120, child: LoadingState()),
        },
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Consignments',
                style: context.mvH1.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _shipmentChips(context),
        const SizedBox(height: 12),
        switch (shipmentsAsync) {
          AsyncLoading() => const SizedBox(height: 170, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierShipmentsProvider),
          ),
          AsyncData(:final value) => _shipments(context, value),
          _ => const SizedBox(height: 170, child: LoadingState()),
        },
        const SizedBox(height: 18),
        Text('Settlement schedule', style: context.mvH1.copyWith(fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Escrow held per order, the release each delivery triggers, and the '
          'withdrawals on their way out.',
          style: TextStyle(fontSize: 11.5, color: context.mv.textMuted),
        ),
        const SizedBox(height: 10),
        _settlementChips(context),
        const SizedBox(height: 12),
        switch (settlementsAsync) {
          AsyncLoading() => const SizedBox(height: 170, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierSettlementsProvider),
          ),
          AsyncData(:final value) => _settlements(context, value),
          _ => const SizedBox(height: 170, child: LoadingState()),
        },
      ],
    );
  }

  Widget _metrics(BuildContext context, DeliverySettlementSummary value) {
    return SupplierOpsMetricRow(
      metrics: [
        SupplierOpsMetric(
          label: 'Held in escrow',
          value: money(value.inEscrow),
          icon: 'shield',
          caption:
              value.heldOrders == 0
                  ? 'across ${plural(value.activeShipments, 'consignment')} in transit'
                  : '${plural(value.heldOrders, 'release')} paused',
          tone: value.heldOrders == 0 ? null : MvColors.warningText,
        ),
        SupplierOpsMetric(
          label: 'Releasing next',
          value: money(value.scheduled),
          icon: 'arrow',
          caption:
              value.nextReleaseAt == null
                  ? 'nothing dated yet'
                  : 'first on ${shortDate(value.nextReleaseAt!)}',
        ),
        SupplierOpsMetric(
          label: 'Released · 30 days',
          value: money(value.releasedThisPeriod),
          icon: 'wallet',
          caption: '${plural(value.deliveredThisMonth, 'delivery')} confirmed',
          tone: MvColors.successText,
        ),
        SupplierOpsMetric(
          label: 'On-time delivery',
          value: '${(value.onTimeRate * 100).toStringAsFixed(0)}%',
          icon: 'chart',
          caption: 'landed on or before the promise',
        ),
      ],
    );
  }

  Widget _shipmentChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _ShipmentFilter.values)
          ChoiceChip(
            label: Text(option.label),
            selected: option == _shipmentFilter,
            onSelected: (_) => setState(() => _shipmentFilter = option),
            selectedColor: context.mv.accentDeep,
            labelStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color:
                  option == _shipmentFilter
                      ? context.mv.onAccent
                      : context.mv.text,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }

  Widget _settlementChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _SettlementFilter.values)
          ChoiceChip(
            label: Text(option.label),
            selected: option == _settlementFilter,
            onSelected: (_) => setState(() => _settlementFilter = option),
            selectedColor: context.mv.accentDeep,
            labelStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color:
                  option == _settlementFilter
                      ? context.mv.onAccent
                      : context.mv.text,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }

  Widget _shipments(BuildContext context, List<SupplierShipment> shipments) {
    final visible =
        shipments.where(_shipmentFilter.matches).toList()
          // Undelivered first, most urgent at the top; delivered newest first.
          ..sort((a, b) {
            if (a.isDelivered != b.isDelivered) return a.isDelivered ? 1 : -1;
            return _placedAt(b).compareTo(_placedAt(a));
          });

    if (visible.isEmpty) {
      return const DataCard(
        child: EmptyState(message: 'No consignments in this view.'),
      );
    }
    return Column(
      children: [
        for (final shipment in visible) ...[
          ShipmentCard(
            shipment: shipment,
            onTap: () => _openShipment(context, shipment),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _settlements(
    BuildContext context,
    List<SupplierSettlementEvent> events,
  ) {
    final visible = events.where(_settlementFilter.matches).toList();
    if (visible.isEmpty) {
      return const DataCard(
        child: EmptyState(message: 'Nothing scheduled in this view.'),
      );
    }
    return DataCard(
      title: 'Settlement ledger',
      subtitle:
          'Newest first · a scheduled row has a date MVEC has committed to.',
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.mv.border),
            SettlementRow(event: visible[i]),
          ],
        ],
      ),
    );
  }

  /// When a consignment was placed, falling back to the epoch when the API did
  /// not send a confirmed milestone.
  static DateTime _placedAt(SupplierShipment shipment) =>
      shipment.deliveredAt ??
      shipment.milestoneFor(DeliveryStage.confirmed)?.at ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// The full consignment sheet: milestones, money and tracking in one place.
  void _openShipment(BuildContext context, SupplierShipment shipment) {
    showMvDetailModal(
      context,
      title: '${shipment.orderNumber} · ${shipment.buyer}',
      children: [
        Row(
          children: [
            StatusChip(shipment.stage.slug),
            const SizedBox(width: 8),
            if (shipment.isOnHold) const StatusChip('ON HOLD'),
          ],
        ),
        const SizedBox(height: 16),
        KeyValueGrid(
          entries: [
            MapEntry(
              'Item',
              '${plural(shipment.units, 'unit')} ${shipment.product}',
            ),
            MapEntry('Destination', shipment.destination),
            MapEntry('Order value', money(shipment.gross)),
            MapEntry('Commission', money(shipment.gross - shipment.net)),
            MapEntry(
              'Escrow',
              shipment.settledAt == null
                  ? '${money(shipment.net)} held'
                  : '${money(shipment.net)} released',
            ),
            if (shipment.courier != null)
              MapEntry('Courier', shipment.courier!),
            if (shipment.trackingNumber != null)
              MapEntry('Tracking', shipment.trackingNumber!),
            MapEntry(
              'Promised',
              shipment.eta == null ? '—' : shortDate(shipment.eta!),
            ),
          ],
        ),
        if (shipment.trackingNumber != null) ...[
          const SizedBox(height: 14),
          OutlineMvButton(
            label: 'Copy tracking number',
            icon: 'copy',
            onPressed: () => copyToClipboard(context, shipment.trackingNumber!),
          ),
        ],
        if (shipment.isOnHold) ...[
          const SizedBox(height: 14),
          InfoBox(shipment.holdReason!, icon: 'shield'),
        ],
        const SizedBox(height: 18),
        Text('Milestones', style: context.mvH1.copyWith(fontSize: 14)),
        const SizedBox(height: 10),
        ..._milestoneRows(context, shipment),
        const SizedBox(height: 10),
        InfoBox(
          'Escrow for this order is released automatically once delivery is '
          'confirmed. If the buyer raises a dispute, the release is paused '
          'until it is resolved.',
          icon: 'shield',
        ),
      ],
    );
  }

  /// Every stage of the track, dated where it happened and explained where it
  /// has not.
  List<Widget> _milestoneRows(BuildContext context, SupplierShipment shipment) {
    final palette = context.mv;
    return [
      for (final stage in DeliveryStage.values)
        Builder(
          builder: (context) {
            final milestone = shipment.milestoneFor(stage);
            final isDone = milestone?.at != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isDone ? Icons.check_circle : Icons.circle_outlined,
                    size: 15,
                    color: isDone ? MvColors.successText : palette.textMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: palette.text,
                          ),
                        ),
                        Text(
                          switch (milestone?.at ?? shipment.eta) {
                            final at? =>
                              '${shortDateTime(at)}'
                                  '${milestone?.note == null ? '' : ' · ${milestone?.note}'}',
                            _ => 'Waiting on ${stage.owner.toLowerCase()}',
                          },
                          style: TextStyle(
                            fontSize: 10.5,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ];
  }
}

/// How the consignment list is narrowed.
enum _ShipmentFilter {
  onTheRoad('On the road'),
  confirmed('Awaiting dispatch'),
  delivered('Delivered'),
  onHold('On hold');

  const _ShipmentFilter(this.label);

  final String label;

  bool matches(SupplierShipment shipment) => switch (this) {
    _ShipmentFilter.onTheRoad => !shipment.isDelivered,
    _ShipmentFilter.confirmed =>
      !shipment.isDelivered && shipment.stage == DeliveryStage.confirmed,
    _ShipmentFilter.delivered => shipment.isDelivered,
    _ShipmentFilter.onHold => shipment.isOnHold,
  };
}

/// How the settlement schedule is narrowed.
enum _SettlementFilter {
  all('All'),
  scheduled('Scheduled'),
  released('Released'),
  paused('Paused');

  const _SettlementFilter(this.label);

  final String label;

  bool matches(SupplierSettlementEvent event) => switch (this) {
    _SettlementFilter.all => true,
    _SettlementFilter.scheduled => event.isScheduled,
    _SettlementFilter.released => event.isSettled,
    _SettlementFilter.paused => event.isPaused,
  };
}
