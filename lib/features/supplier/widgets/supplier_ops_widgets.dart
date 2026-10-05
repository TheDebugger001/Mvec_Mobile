import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../../../widgets/mv_icon.dart';
import '../models/supplier_operations.dart';
import '../models/supplier_team.dart';

/// Metric card for the operations pages.
///
/// [SupplierFinanceMetric] formats its value as money, which is right for
/// Finance but wrong here: "3 consignments" and "100%" are just as common.
class SupplierOpsMetric extends StatelessWidget {
  const SupplierOpsMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tone,
  });

  final String label;
  final String value;
  final String icon;

  /// Small print under the value, e.g. "due by 14 Mar".
  final String? caption;

  /// Overrides the icon colour — used to flag a blocked release or a gap in
  /// team coverage.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final accent = tone ?? palette.accentDeep;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(child: MvIcon(icon, size: 17, color: accent)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 3),
              Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: palette.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps a row of [SupplierOpsMetric]s that reflows to two columns on a phone.
class SupplierOpsMetricRow extends StatelessWidget {
  const SupplierOpsMetricRow({super.key, required this.metrics});

  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 760 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ],
        );
      },
    );
  }
}

/// The milestone track for one consignment.
///
/// Horizontal when there is room for five labels, vertical below that, so the
/// step names are never truncated to initials on a phone.
class DeliveryStageTrack extends StatelessWidget {
  const DeliveryStageTrack({super.key, required this.shipment});

  final SupplierShipment shipment;

  @override
  Widget build(BuildContext context) {
    final stages = DeliveryStage.values;
    final done = shipment.stageIndex;
    final isVertical = MediaQuery.sizeOf(context).width < 560;

    if (isVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stages.length; i++)
            _verticalStep(context, stages[i], i, done),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stages.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _horizontalStep(context, stages[i], i, done),
            ),
          ),
      ],
    );
  }

  Widget _dot(BuildContext context, DeliveryStage stage, bool isDone) {
    final palette = context.mv;
    final colour =
        shipment.isOnHold && stage == shipment.nextStage
            ? MvColors.warningText
            : isDone
            ? palette.accentDeep
            : palette.border;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: isDone ? colour.withValues(alpha: .12) : Colors.transparent,
        border: Border.all(color: colour, width: isDone ? 2 : 1.4),
        shape: BoxShape.circle,
      ),
      child: Center(
        child:
            isDone
                ? Icon(Icons.check, size: 13, color: colour)
                : Text(
                  '${stage.index + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colour,
                  ),
                ),
      ),
    );
  }

  Widget _horizontalStep(
    BuildContext context,
    DeliveryStage stage,
    int index,
    int done,
  ) {
    final palette = context.mv;
    final isDone = index <= done;
    final milestone = shipment.milestoneFor(stage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _dot(context, stage, isDone),
            if (index < DeliveryStage.values.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: index < done ? palette.accentDeep : palette.border,
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          stage.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: isDone ? palette.text : palette.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          milestone?.at == null ? stage.owner : shortDate(milestone!.at!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: palette.textMuted),
        ),
      ],
    );
  }

  Widget _verticalStep(
    BuildContext context,
    DeliveryStage stage,
    int index,
    int done,
  ) {
    final palette = context.mv;
    final isDone = index <= done;
    final isLast = index == DeliveryStage.values.length - 1;
    final milestone = shipment.milestoneFor(stage);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _dot(context, stage, isDone),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: index < done ? palette.accentDeep : palette.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isDone ? palette.text : palette.textMuted,
                          ),
                        ),
                      ),
                      Text(
                        milestone?.at == null
                            ? stage.owner
                            : shortDate(milestone!.at!),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (milestone?.note != null)
                    Text(
                      milestone!.note!,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One consignment: header, milestone track and the money behind it.
class ShipmentCard extends StatelessWidget {
  const ShipmentCard({super.key, required this.shipment, this.onTap});

  final SupplierShipment shipment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${shipment.orderNumber} · ${shipment.buyer}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${plural(shipment.units, 'unit')} · '
                          '${shipment.product} · ${shipment.destination}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusChip(shipment.stage.slug),
                ],
              ),
              const SizedBox(height: 14),
              DeliveryStageTrack(shipment: shipment),
              const SizedBox(height: 14),
              Divider(height: 1, color: palette.border),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shipment.isDelivered
                          ? shipment.settledAt == null
                              ? 'Delivered · release pending'
                              : 'Delivered · released '
                                  '${shortDate(shipment.settledAt!)}'
                          : shipment.nextStage == null
                          ? 'Delivered'
                          : 'Next: ${shipment.nextStage!.label.toLowerCase()}'
                              '${shipment.eta == null ? '' : ' · due ${shortDate(shipment.eta!)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            shipment.isOnHold
                                ? MvColors.warningText
                                : palette.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    shipment.isDelivered
                        ? money(shipment.net)
                        : '${money(shipment.net)} in escrow',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                ],
              ),
              if (shipment.trackingNumber != null) ...[
                const SizedBox(height: 7),
                Text(
                  '${shipment.courier} · ${shipment.trackingNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                ),
              ],
              if (shipment.isOnHold) ...[
                const SizedBox(height: 9),
                InfoBox(shipment.holdReason!, icon: 'shield'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the settlement schedule: locked, scheduled, released or paused.
class SettlementRow extends StatelessWidget {
  const SettlementRow({super.key, required this.event});

  final SupplierSettlementEvent event;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final (tone, status, timing) = switch (event) {
      _ when event.isSettled => (
        MvColors.successText,
        'RELEASED',
        shortDate(event.settledAt!),
      ),
      _ when event.isScheduled => (
        MvColors.warningText,
        'SCHEDULED',
        'due ${shortDate(event.timelineAt)}',
      ),
      _ when event.isPaused => (MvColors.errorText, 'PAUSED', 'on hold'),
      _ => (palette.textMuted, 'LOCKED', shortDate(event.at)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: MvIcon(event.kind.icon, size: 16, color: tone),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${event.kind.label} · $timing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${event.kind.sign > 0 ? '+' : '−'}${money(event.amount)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
              const SizedBox(height: 4),
              StatusChip(status, overrideColor: tone),
            ],
          ),
        ],
      ),
    );
  }
}

/// The step-by-step supply flow, as a numbered vertical timeline.
///
/// Each step names both sides' job, because the supplier's most common question
/// is "what is MVEC doing with my request right now?".
class SupplyProcessTimeline extends StatelessWidget {
  const SupplyProcessTimeline({super.key, required this.steps});

  final List<SupplyProcessStep> steps;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: palette.accentDeep.withValues(alpha: .12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${steps[i].number}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: palette.accentDeep,
                        ),
                      ),
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(width: 2, color: palette.border),
                      ),
                  ],
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < steps.length - 1 ? 20 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                steps[i].title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: palette.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              steps[i].timeframe,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: palette.accentDeep,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        _responsibility(
                          context,
                          'You',
                          steps[i].youDo,
                          palette.accentDeep,
                        ),
                        const SizedBox(height: 5),
                        _responsibility(
                          context,
                          'MVEC',
                          steps[i].mvecDoes,
                          palette.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _responsibility(
    BuildContext context,
    String who,
    String body,
    Color tone,
  ) {
    final palette = context.mv;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            who,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
              color: tone,
            ),
          ),
        ),
        Expanded(
          child: Text(
            body,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: who == 'You' ? palette.text : palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A compact six-dot progress read-out for one supply request.
class SupplyStepDots extends StatelessWidget {
  const SupplyStepDots({super.key, required this.request});

  final SupplierSupplyRequest request;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final reached = request.stepNumber;
    return Row(
      children: [
        for (var i = 0; i < kSupplyProcessSteps.length; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(
                right: i < kSupplyProcessSteps.length - 1 ? 4 : 0,
              ),
              decoration: BoxDecoration(
                color: i < reached ? palette.accentDeep : palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

/// One supply request with its position on the flow and its lifecycle actions.
class SupplyRequestCard extends StatelessWidget {
  const SupplyRequestCard({
    super.key,
    required this.request,
    this.onCancel,
    this.onResubmit,
    this.onTap,
  });

  final SupplierSupplyRequest request;
  final VoidCallback? onCancel;
  final VoidCallback? onResubmit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final days = request.daysUntilNeeded(DateTime.now());

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.reference,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${plural(request.totalUnits, 'unit')} · '
                          '${money(request.totalValue)} · raised '
                          '${shortDate(request.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusChip(request.status.slug),
                ],
              ),
              const SizedBox(height: 12),
              SupplyStepDots(request: request),
              const SizedBox(height: 9),
              Text(
                request.stage == null
                    ? request.status.label
                    : 'Step ${request.stepNumber} of ${kSupplyProcessSteps.length} · '
                        '${request.stage!.label}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 10),
              for (final line in request.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.product,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: palette.text),
                        ),
                      ),
                      Text(
                        '${line.units} ${line.unit} · ${money(line.lineTotal)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              if (request.neededBy != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Needed by ${shortDate(request.neededBy!)}'
                  '${days == null
                      ? ''
                      : days < 0
                      ? ' · ${-days}d overdue'
                      : ' · in ${days}d'}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color:
                        days != null && days < 0
                            ? MvColors.errorText
                            : palette.textMuted,
                  ),
                ),
              ],
              if (request.decision != null) ...[
                const SizedBox(height: 9),
                InfoBox(request.decision!, icon: 'bell'),
              ],
              if (onCancel != null || onResubmit != null) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: palette.border),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onResubmit != null)
                      OutlineMvButton(
                        label: 'Resubmit',
                        icon: 'plus',
                        onPressed: onResubmit,
                      ),
                    if (onResubmit != null && onCancel != null)
                      const SizedBox(width: 8),
                    if (onCancel != null)
                      OutlineMvButton(
                        label: 'Withdraw',
                        icon: 'trash',
                        onPressed: onCancel,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The request's own history, newest first.
class SupplyRequestTimeline extends StatelessWidget {
  const SupplyRequestTimeline({super.key, required this.request});

  final SupplierSupplyRequest request;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final events = request.events.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < events.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == 0 ? palette.accentDeep : palette.border,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              events[i].title,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: palette.text,
                              ),
                            ),
                          ),
                          Text(
                            shortDate(events[i].at),
                            style: TextStyle(
                              fontSize: 10,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (events[i].detail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          events[i].detail,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Circular initials avatar for a team member.
class TeamAvatar extends StatelessWidget {
  const TeamAvatar({super.key, required this.member, this.size = 38});

  final TeamMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final colour =
        member.status == TeamMemberStatus.active
            ? palette.accentDeep
            : palette.textMuted;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .12),
        shape: BoxShape.circle,
        border: Border.all(color: colour.withValues(alpha: .3)),
      ),
      alignment: Alignment.center,
      child: Text(
        member.initials,
        style: TextStyle(
          fontSize: size * .34,
          fontWeight: FontWeight.w800,
          color: colour,
        ),
      ),
    );
  }
}

/// One staff member: who they are, what they can do, and what you can do to
/// them. The owner has no actions — the account must always have somebody who
/// can manage the team.
class TeamMemberTile extends StatelessWidget {
  const TeamMemberTile({
    super.key,
    required this.member,
    this.onEdit,
    this.onRemove,
  });

  final TeamMember member;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TeamAvatar(member: member),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: palette.text,
                        ),
                      ),
                    ),
                    if (member.isOwner) ...[
                      const SizedBox(width: 7),
                      const StatusChip('OWNER'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  member.role.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.accentDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${member.phone}'
                  '${member.email == null ? '' : ' · ${member.email}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                ),
                if (member.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    member.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: palette.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final permission in TeamPermission.values)
                      Tooltip(
                        message:
                            '${permission.description}\n'
                            'Granted by the ${member.role.label} role',
                        child: _PermissionChip(
                          label: permission.label,
                          granted: member.permissions.contains(permission),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onEdit != null || onRemove != null)
            Column(
              children: [
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 17,
                      color: MvColors.primaryDeep,
                    ),
                    tooltip: 'Edit ${member.fullName}',
                  ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 17,
                      color: MvColors.dangerIcon,
                    ),
                    tooltip: 'Remove ${member.fullName}',
                  ),
              ],
            )
          else
            Tooltip(
              message: 'The account owner cannot be edited or removed',
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({required this.label, required this.granted});

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    final colour = granted ? palette.accentDeep : palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: granted ? colour.withValues(alpha: .1) : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(granted ? Icons.check : Icons.remove, size: 10, color: colour),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether each permission has somebody active who holds it.
class TeamCoverageList extends StatelessWidget {
  const TeamCoverageList({super.key, required this.coverage});

  final List<TeamPermissionCoverage> coverage;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in coverage)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  entry.isCovered ? Icons.check_circle : Icons.error_outline,
                  size: 15,
                  color:
                      entry.isCovered
                          ? MvColors.successText
                          : MvColors.warningText,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    entry.permission.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    entry.isCovered
                        ? entry.holders.map((m) => m.fullName).join(', ')
                        : 'Nobody',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 10.5, color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The role picker used by the add and edit forms.
///
/// Each option spells out its permissions inline, because picking a role is the
/// one decision on this page with consequences the supplier cannot see after the
/// fact.
class TeamRolePicker extends StatelessWidget {
  const TeamRolePicker({
    super.key,
    required this.role,
    required this.onChanged,
    this.enabledRoles = TeamRole.values,
  });

  final TeamRole role;
  final ValueChanged<TeamRole> onChanged;

  /// Roles offered — the owner is excluded when adding, since it already exists.
  final List<TeamRole> enabledRoles;

  @override
  Widget build(BuildContext context) {
    final palette = context.mv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in enabledRoles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onChanged(option),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: option == role ? palette.soft : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: option == role ? palette.accentDeep : palette.border,
                    width: option == role ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          option == role
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 15,
                          color:
                              option == role
                                  ? palette.accentDeep
                                  : palette.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: palette.text,
                            ),
                          ),
                        ),
                        MvIcon(option.icon, size: 15, color: palette.textMuted),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      option.description,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: palette.textMuted,
                      ),
                    ),
                    if (option == role) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final permission in option.permissions)
                            _PermissionChip(
                              label: permission.label,
                              granted: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
