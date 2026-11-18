import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'rider_api.dart';
import 'rider_state.dart';

/// `/delivery`: go online, see today's numbers, and take the offers nearby.
class RiderHomePage extends ConsumerWidget {
  const RiderHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(riderLocationProvider);
    final board = ref.watch(riderBoardProvider);
    ref.listen(riderBoardProvider, (prev, next) {
      // A new offer arrives: a buzz, like KitchenLink's delivery app.
      final before = prev?.valueOrNull?.offers.length ?? 0;
      if ((next.valueOrNull?.offers.length ?? 0) > before) HapticFeedback.heavyImpact();
    });
    return board.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(riderBoardProvider)),
      data: (b) => PortalPage(
        eyebrow: 'DELIVERY',
        title: b.account.name.isEmpty ? 'Deliveries' : 'Hello, ${b.account.name.split(' ').first}',
        subtitle: 'Go online to receive parcels near you. You keep the whole delivery fee.',
        onRefresh: () => ref.read(riderBoardProvider.notifier).refresh(),
        children: [
          if (b.error != null) Notice(text: b.error!),
          if (!b.account.approved) _ApprovalCard(b.account) else ...[
            _OnlineCard(online: b.account.isOnline),
            const SizedBox(height: 12),
            MetricGrid(children: [
              MetricCard(label: 'Today', value: money(b.stats.todayEarnings), sub: '${b.stats.todayDeliveries} delivered', icon: 'wallet'),
              MetricCard(label: 'All time', value: money(b.stats.totalEarnings), sub: '${b.stats.totalDeliveries} delivered', icon: 'chart'),
            ]),
            if (b.active != null) ...[
              const SizedBox(height: 12),
              _ActiveCard(b.active!),
            ] else if (b.account.isOnline) ...[
              const SizedBox(height: 16),
              Section(
                title: 'Offers near you',
                subtitle: 'The first rider to accept gets the parcel.',
                children: [
                  if (b.offers.isEmpty) const EmptyState(title: 'No parcels right now', message: 'Stay online: new offers appear here and your phone buzzes.'),
                  for (final o in b.offers) _OfferCard(o),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard(this.account);
  final RiderAccount account;

  @override
  Widget build(BuildContext context) {
    final (title, text) = switch (account.status) {
      'REJECTED' => ('Application not approved', account.reviewNote.isEmpty ? 'Contact Ikiguzi support to find out more.' : account.reviewNote),
      'SUSPENDED' => ('Account suspended', account.reviewNote.isEmpty ? 'Contact Ikiguzi support.' : account.reviewNote),
      _ => ('Waiting for approval', 'Ikiguzi is checking your details. You will get a text message once you can start delivering.'),
    };
    return InfoBox(title: title, text: text, child: StatusChip.of(account.status));
  }
}

class _OnlineCard extends ConsumerStatefulWidget {
  const _OnlineCard({required this.online});
  final bool online;

  @override
  ConsumerState<_OnlineCard> createState() => _OnlineCardState();
}

class _OnlineCardState extends ConsumerState<_OnlineCard> {
  bool _busy = false;

  Future<void> _toggle(bool online) async {
    final messenger = ScaffoldMessenger.of(context);
    if (online) {
      final problem = await RiderLocation.ensureAccess();
      if (problem != null) {
        messenger.showSnackBar(SnackBar(content: Text(problem)));
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await ref.read(riderBoardProvider.notifier).setOnline(online);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final online = widget.online;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: online ? mv.accentDeep : mv.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: mv.border)),
      child: Row(children: [
        Icon(online ? Icons.two_wheeler_rounded : Icons.bedtime_outlined, color: online ? mv.onAccent : mv.textMuted, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(online ? "You're online" : "You're offline", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: online ? mv.onAccent : mv.text)),
            Text(online ? 'Your location is shared while you are online.' : 'Go online to receive delivery offers.', style: TextStyle(color: online ? mv.onAccent.withValues(alpha: .8) : mv.textMuted, fontSize: 12.5)),
          ]),
        ),
        _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)) : Switch(value: online, onChanged: _toggle),
      ]),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard(this.job);
  final DeliveryJob job;

  @override
  Widget build(BuildContext context) => RecordCard(
        title: 'Current delivery · ${job.orderNumber}',
        subtitle: job.statusLabel,
        amount: money(job.fee),
        onTap: () => context.push('/delivery/trip'),
        lines: ['Pick up: ${job.pickup.name}', 'Deliver to: ${job.dropoff.address}'],
      );
}

class _OfferCard extends ConsumerStatefulWidget {
  const _OfferCard(this.offer);
  final DeliveryJob offer;

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  String _busy = '';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The answer window counts down on the card.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _run(String what) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = what);
    try {
      final board = ref.read(riderBoardProvider.notifier);
      if (what == 'accept') {
        await board.accept(widget.offer.id);
        router.push('/delivery/trip');
      } else {
        await board.decline(widget.offer.id);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e))));
      ref.read(riderBoardProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final left = o.offerExpiresAt?.difference(DateTime.now()).inSeconds;
    return RecordCard(
      title: o.pickup.name,
      subtitle: [
        if (o.distanceToPickupKm != null) '${o.distanceToPickupKm} km from you',
        '${o.distanceKm} km trip',
        if (o.dropoff.address.isNotEmpty) 'to ${o.dropoff.address}',
      ].join(' · '),
      amount: money(o.fee),
      lines: [
        if (o.waitingForSeller) 'The seller is still preparing it',
        if (o.items.isNotEmpty) o.items.join(', '),
        if (left != null && left > 0) 'Answer within ${left}s',
      ],
      actions: [
        OutlineBtn(label: 'Decline', compact: true, loading: _busy == 'decline', onPressed: _busy.isEmpty ? () => _run('decline') : null),
        GradientButton(label: 'Accept', compact: true, loading: _busy == 'accept', onPressed: _busy.isEmpty ? () => _run('accept') : null),
      ],
    );
  }
}
