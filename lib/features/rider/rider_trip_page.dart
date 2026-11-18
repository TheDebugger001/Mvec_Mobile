import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'rider_api.dart';
import 'rider_state.dart';
import 'slide_to_confirm.dart';
import '../tracking/live_tracking.dart';

/// `/delivery/trip`: the parcel being delivered. Each step is a slide (it
/// can't be undone), offered only when the server allows it.
class RiderTripPage extends ConsumerWidget {
  const RiderTripPage({super.key});

  static const _stepLabels = {'PICKED_UP': 'Slide when you have the parcel', 'OUT_FOR_DELIVERY': 'Slide to start the delivery'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(riderLocationProvider);
    final board = ref.watch(riderBoardProvider);
    final job = board.valueOrNull?.active;
    if (board.isLoading && job == null) return const LoadingState();
    if (job == null) {
      return PortalPage(title: 'Current delivery', children: [
        EmptyState(
          title: 'No delivery in progress',
          message: 'Accept an offer on your dashboard to start one.',
          action: GradientButton(label: 'See offers', onPressed: () => context.go('/delivery')),
        ),
      ]);
    }
    final next = job.allowedNextStatuses.isEmpty ? null : job.allowedNextStatuses.first;
    final atStore = job.status == 'ASSIGNED';
    return PortalPage(
      eyebrow: 'DELIVERY · ${job.orderNumber}',
      title: job.statusLabel,
      subtitle: 'You earn ${money(job.fee)} for this parcel (${job.distanceKm} km).',
      onRefresh: () => ref.read(riderBoardProvider.notifier).refresh(),
      children: [
        if (job.waitingForSeller)
          const Notice(info: true, text: "The seller is still preparing this parcel. Head over if you like: you'll get a message the moment it's ready to collect."),
        RiderNavigation(key: ValueKey(job.id), deliveryId: job.id),
        if (job.progress.isNotEmpty) Section(title: 'Order progress', children: [ParcelProgress(steps: job.progress)]),
        Section(
          title: atStore ? 'Pick up here' : 'Picked up from',
          children: [
            KV('Store', job.pickup.name),
            KV('Address', job.pickup.address),
            if (atStore) _MapButton(place: job.pickup, label: 'Directions to the store'),
          ],
        ),
        Section(
          title: 'Deliver to',
          children: [
            KV('Buyer', job.customerName),
            KV('Address', job.dropoff.address),
            if (job.items.isNotEmpty) KV('Parcel', job.items.join(', ')),
            Wrap(spacing: 10, runSpacing: 8, children: [
              if (job.customerPhone.isNotEmpty)
                OutlineBtn(label: 'Call the buyer', icon: Icons.call_rounded, compact: true, onPressed: () => launchUrl(Uri.parse('tel:${job.customerPhone}'))),
              if (!atStore) _MapButton(place: job.dropoff, label: 'Directions to the buyer'),
            ]),
          ],
        ),
        const SizedBox(height: 8),
        if (next != null)
          SlideToConfirm(
            key: ValueKey(next),
            label: _stepLabels[next] ?? 'Slide to continue',
            onConfirmed: () => _run(context, () => ref.read(riderBoardProvider.notifier).step(job.id, next)),
          )
        else if (job.canConfirm) ...[
          const InfoBox(title: "The buyer's code", text: 'Ask for the 6-digit code on their order only when the parcel is in their hands. Five wrong codes lock the delivery for Ikiguzi support.'),
          GradientButton(label: "Enter the buyer's code", icon: Icons.pin_outlined, expand: true, onPressed: () => _confirm(context, ref, job)),
        ],
        if (atStore) ...[
          const SizedBox(height: 8),
          OutlineBtn(label: 'Hand it back', icon: Icons.undo_rounded, expand: true, onPressed: () => _handBack(context, ref, job)),
        ],
      ],
    );
  }

  static Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  static Future<void> _handBack(BuildContext context, WidgetRef ref, DeliveryJob job) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hand this parcel back?'),
        content: const Text("Another rider will get it, and it won't be offered to you again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hand it back')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(riderBoardProvider.notifier).handBack(job.id);
      if (context.mounted) context.go('/delivery');
    });
  }

  static Future<void> _confirm(BuildContext context, WidgetRef ref, DeliveryJob job) async {
    final earned = await showModalBottomSheet<num>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CodeSheet(job: job),
    );
    if (earned == null || !context.mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delivered. You earned ${money(earned)}.')));
    context.go('/delivery');
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.place, required this.label});
  final Place place;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (place.lat == null || place.lng == null) return const SizedBox.shrink();
    return OutlineBtn(
      label: label,
      icon: Icons.navigation_outlined,
      compact: true,
      onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lng}'), mode: LaunchMode.externalApplication),
    );
  }
}

class _CodeSheet extends ConsumerStatefulWidget {
  const _CodeSheet({required this.job});
  final DeliveryJob job;

  @override
  ConsumerState<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends ConsumerState<_CodeSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'The code has 6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final earned = await ref.read(riderBoardProvider.notifier).confirm(widget.job.id, _code.text.trim());
      if (mounted) Navigator.of(context).pop(earned);
    } catch (e) {
      HapticFeedback.vibrate();
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("Buyer's delivery code", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Tiny('Order ${widget.job.orderNumber} · ${widget.job.customerName}'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w800),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(counterText: '', errorText: _error, hintText: '••••••'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          GradientButton(label: 'Confirm delivery', expand: true, loading: _busy, onPressed: _busy ? null : _submit),
        ]),
      );
}

/// The parcel's story as a vertical timeline: done steps in the brand colour.
class ParcelProgress extends StatelessWidget {
  const ParcelProgress({super.key, required this.steps});
  final List<ParcelStep> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    final muted = theme.colorScheme.outline;
    String time(DateTime d) => '${d.toLocal().hour.toString().padLeft(2, '0')}:${d.toLocal().minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Column(children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: s.done ? brand : null, border: Border.all(color: s.done ? brand : muted, width: 2)),
                    ),
                    if (i < steps.length - 1) Expanded(child: Container(width: 2, color: (s.done ? brand : muted).withValues(alpha: 0.35))),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(s.label, style: TextStyle(fontWeight: s.done ? FontWeight.w600 : FontWeight.w400, color: s.done ? null : muted)),
                  ),
                ),
                if (s.done && s.at != null) Text(time(s.at!), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ),
      ],
    );
  }
}
