import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'rider_api.dart';
import 'rider_state.dart';
import 'rider_trip_page.dart' show ParcelProgress;

/// `/delivery/offers/:id`: the parcel a "New delivery" notification is about,
/// with accept and decline (web: the Offer view in `RiderDashboard.jsx`).
class RiderOfferPage extends ConsumerStatefulWidget {
  const RiderOfferPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RiderOfferPage> createState() => _RiderOfferPageState();
}

class _RiderOfferPageState extends ConsumerState<RiderOfferPage> {
  ParcelOffer? _offer;
  String? _gone;
  String _busy = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await RiderApi.offer(widget.id);
      if (mounted) setState(() { _offer = o; _gone = null; });
    } catch (e) {
      if (mounted) setState(() => _gone = errorText(e));
    }
  }

  Future<void> _run(String what) async {
    final router = GoRouter.of(context);
    final board = ref.read(riderBoardProvider.notifier);
    setState(() { _busy = what; _error = null; });
    try {
      if (what == 'online') {
        await board.setOnline(true);
        await _load();
      } else if (what == 'accept') {
        await board.accept(widget.id);
        router.go('/delivery/trip');
      } else {
        await board.decline(widget.id);
        router.go('/delivery');
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_gone != null) {
      return PortalPage(title: "This parcel isn't available", children: [
        EmptyState(
          title: _gone!,
          message: 'New parcels near you show on your dashboard.',
          action: GradientButton(label: 'See parcels near you', onPressed: () => context.go('/delivery')),
        ),
      ]);
    }
    final offer = _offer;
    if (offer == null) return const LoadingState(label: 'Loading the parcel…');
    final o = offer.job;
    if (offer.mine) {
      return PortalPage(eyebrow: 'DELIVERY · ${o.orderNumber}', title: 'This parcel is yours', subtitle: o.statusLabel, children: [
        GradientButton(label: 'Open the trip', expand: true, onPressed: () => context.go('/delivery/trip')),
      ]);
    }
    final busyElsewhere = ref.watch(riderBoardProvider).valueOrNull?.active != null;
    return PortalPage(
      eyebrow: 'NEW DELIVERY',
      title: '${o.pickup.name} · ${money(o.fee)}',
      subtitle: 'The first rider to accept gets the parcel.',
      onRefresh: _load,
      children: [
        if (_error != null) Notice(text: _error!),
        if (o.waitingForSeller) const Notice(info: true, text: "The seller is still preparing it. You can head over now: you'll get a message when it's ready."),
        Section(title: 'The parcel', children: [
          KV('Pick up at', [o.pickup.name, if (o.pickup.address.isNotEmpty) o.pickup.address].join(', ')),
          KV('Deliver to', o.dropoff.address.isEmpty ? 'Shown once you accept' : o.dropoff.address),
          KV('Distance', [if (o.distanceToPickupKm != null) '${o.distanceToPickupKm} km to the store', '${o.distanceKm} km trip'].join(' · ')),
          KV('You earn', money(o.fee)),
          if (o.items.isNotEmpty) KV('Items', o.items.join(', ')),
          if (o.pickup.lat != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Open the store in maps'),
                onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${o.pickup.lat},${o.pickup.lng}'), mode: LaunchMode.externalApplication),
              ),
            ),
        ]),
        if (busyElsewhere)
          const Notice(info: true, text: 'Finish your current delivery before taking another.')
        else if (!offer.online)
          GradientButton(label: 'Go online to take it', expand: true, loading: _busy == 'online', onPressed: _busy.isEmpty ? () => _run('online') : null)
        else ...[
          if (!offer.canTake) const Notice(info: true, text: 'This parcel is too far from where you are now.'),
          Row(children: [
            Expanded(child: OutlineBtn(label: 'Decline', expand: true, loading: _busy == 'decline', onPressed: _busy.isEmpty ? () => _run('decline') : null)),
            const SizedBox(width: 10),
            Expanded(child: GradientButton(label: 'Accept', expand: true, loading: _busy == 'accept', onPressed: _busy.isEmpty && offer.canTake ? () => _run('accept') : null)),
          ]),
        ],
        if (o.progress.isNotEmpty) Section(title: 'Order progress', children: [ParcelProgress(steps: o.progress)]),
      ],
    );
  }
}
