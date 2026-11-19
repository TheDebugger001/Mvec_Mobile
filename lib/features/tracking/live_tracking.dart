import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// One parcel's live view (`/orders/:id/live`, `/rider/deliveries/:id/navigation`):
/// where the rider is, the road still to go and how long it takes.
class LiveParcel {
  LiveParcel({
    required this.deliveryId,
    required this.active,
    required this.status,
    required this.statusLabel,
    this.waitingForRider = false,
    this.offeredAt,
    required this.phase,
    required this.phaseLabel,
    required this.target,
    required this.storeName,
    required this.store,
    required this.destination,
    required this.riderName,
    required this.riderPhone,
    required this.vehicle,
    required this.plateNumber,
    required this.rider,
    required this.heading,
    required this.stale,
    required this.seenAt,
    required this.route,
    required this.distanceM,
    required this.durationS,
    required this.etaAt,
    required this.steps,
    required this.refreshAfter,
  });

  final String deliveryId, status, statusLabel, phase, phaseLabel, target;
  final bool active;

  /// No rider took it yet: the seller may deliver it instead.
  final bool waitingForRider;
  final DateTime? offeredAt;
  final String storeName, riderName, riderPhone, vehicle, plateNumber;
  final LatLng? store, destination, rider;
  final double? heading;
  final bool stale;
  final DateTime? seenAt, etaAt;
  final List<LatLng> route;
  final int? distanceM, durationS;

  /// Turn-by-turn, the rider's view only: (instruction, metres to it).
  final List<(String, int)> steps;
  final Duration refreshAfter;

  static LatLng? _point(dynamic v) {
    final m = asMap(v);
    final lat = m['lat'], lng = m['lng'];
    return lat is num && lng is num ? LatLng(lat.toDouble(), lng.toDouble()) : null;
  }

  factory LiveParcel.fromJson(Map<String, dynamic> j) {
    final rider = asMap(j['rider']);
    final loc = asMap(rider['location']);
    final route = asMap(j['route']);
    return LiveParcel(
      deliveryId: strOf(j['deliveryId']),
      active: j['active'] == true,
      status: strOf(j['status']),
      statusLabel: strOf(j['statusLabel']),
      waitingForRider: j['waitingForRider'] == true,
      offeredAt: DateTime.tryParse(strOf(j['offeredAt'])),
      phase: strOf(j['phase']),
      phaseLabel: strOf(j['phaseLabel']),
      target: strOf(j['target']),
      storeName: strOf(asMap(j['store'])['name']),
      store: _point(j['store']),
      destination: _point(j['destination']),
      riderName: strOf(rider['name'], 'Ikiguzi rider'),
      riderPhone: strOf(rider['phone']),
      vehicle: const {'MOTORBIKE': 'Motorbike', 'BICYCLE': 'Bicycle', 'CAR': 'Car', 'ON_FOOT': 'On foot'}[rider['vehicleType']] ?? 'Rider',
      plateNumber: strOf(rider['plateNumber']),
      rider: loc.isEmpty ? null : _point(loc),
      heading: loc['heading'] is num ? (loc['heading'] as num).toDouble() : null,
      stale: loc['stale'] == true,
      seenAt: DateTime.tryParse(strOf(loc['at']))?.toLocal(),
      route: [
        for (final p in (route['geometry'] as List? ?? const []))
          if (p is List && p.length == 2 && p[0] is num && p[1] is num) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
      ],
      distanceM: route['distanceM'] is num ? (route['distanceM'] as num).round() : null,
      durationS: route['durationS'] is num ? (route['durationS'] as num).round() : null,
      etaAt: DateTime.tryParse(strOf(route['etaAt']))?.toLocal(),
      steps: [for (final s in asMaps(route['steps'])) (strOf(s['instruction']), numOf(s['distanceM']).round())],
      refreshAfter: Duration(seconds: numOf(j['refreshAfterS'], 4).toInt().clamp(2, 30)),
    );
  }

  /// "7 min" from the time left.
  String get minutesLeft => '${((durationS ?? 0) / 60).round().clamp(1, 999)} min';
  String get timeAt => etaAt == null ? '' : '${etaAt!.hour.toString().padLeft(2, '0')}:${etaAt!.minute.toString().padLeft(2, '0')}';
}

String kmLeft(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${(m / 10).round() * 10} m';

/// `/orders/:id/live` and the rider's navigation.
class LiveTrackingApi {
  LiveTrackingApi._();
  static Future<List<LiveParcel>> order(String orderId) async =>
      asMaps(asMap(await Api.instance.get('/orders/$orderId/live'))['parcels']).map(LiveParcel.fromJson).toList();
  static Future<LiveParcel> navigation(String deliveryId) async =>
      LiveParcel.fromJson(asMap(await Api.instance.get('/rider/deliveries/$deliveryId/navigation')));
}

/// The map: the rider (pointing where they're heading), the store, the buyer's
/// pin once the parcel is on its way, and the road still to go. It fits the
/// pins when they first appear and when the trip moves to its next leg.
class LiveDeliveryMap extends StatelessWidget {
  const LiveDeliveryMap({super.key, required this.parcel, this.height = 260});
  final LiveParcel parcel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = parcel;
    final pins = <LatLng>[
      if (p.rider != null) p.rider!,
      if (p.store != null) p.store!,
      if (p.phase == 'to_buyer' && p.destination != null) p.destination!,
    ];
    if (pins.isEmpty) return const SizedBox.shrink();
    final brand = Theme.of(context).colorScheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: height,
        // A new key per leg refits the camera; within a leg the viewer keeps their view.
        child: FlutterMap(
          key: ValueKey('${p.deliveryId}-${p.phase}-${p.rider != null}'),
          options: MapOptions(
            initialCenter: pins.first,
            initialZoom: 15,
            initialCameraFit: pins.length > 1 ? CameraFit.coordinates(coordinates: pins, padding: const EdgeInsets.all(40), maxZoom: 16) : null,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom),
          ),
          children: [
            TileLayer(urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', userAgentPackageName: 'com.ikiguzi.app', retinaMode: true),
            if (p.route.length > 1)
              PolylineLayer(polylines: [Polyline(points: p.route, strokeWidth: 5, color: brand, borderStrokeWidth: 2, borderColor: Colors.white)]),
            MarkerLayer(markers: [
              if (p.store != null) Marker(point: p.store!, width: 22, height: 22, child: const _Pin(kind: 'store')),
              if (p.phase == 'to_buyer' && p.destination != null) Marker(point: p.destination!, width: 26, height: 26, child: const _Pin(kind: 'buyer')),
              if (p.rider != null) Marker(point: p.rider!, width: 34, height: 34, child: _RiderPin(heading: p.heading, stale: p.stale, color: brand)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) => kind == 'store'
      ? Container(decoration: BoxDecoration(color: const Color(0xFF12232B), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white, width: 3)))
      : const Icon(Icons.location_on_rounded, color: Color(0xFFE0457B), size: 26);
}

class _RiderPin extends StatelessWidget {
  const _RiderPin({required this.heading, required this.stale, required this.color});
  final double? heading;
  final bool stale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = stale ? Colors.grey : color;
    if (heading == null || stale) {
      return Center(child: Container(width: 18, height: 18, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))));
    }
    return Transform.rotate(angle: heading! * 3.1415926535 / 180, child: Icon(Icons.navigation_rounded, color: c, size: 30));
  }
}

/// Refreshes `load` every `refreshAfter` of the last answer while mounted.
mixin _Polling<T extends StatefulWidget, R> on State<T> {
  R? data;
  Timer? _timer;
  Future<R> load();
  Duration nextAfter(R value);

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    var wait = const Duration(seconds: 15);
    try {
      final value = await load();
      if (!mounted) return;
      setState(() => data = value);
      wait = nextAfter(value);
    } catch (_) {
      // Keep the last view; try again later.
    }
    if (mounted) _timer = Timer(wait, _tick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The buyer's (or seller's) view of an order's riders; nothing when no
/// parcel goes with an Ikiguzi rider.
class OrderLiveTracking extends StatefulWidget {
  const OrderLiveTracking({super.key, required this.orderId, this.seller = false, this.onChanged});
  final String orderId;
  final bool seller;

  /// After the seller takes a parcel over (the order page reloads).
  final VoidCallback? onChanged;

  @override
  State<OrderLiveTracking> createState() => _OrderLiveTrackingState();
}

class _OrderLiveTrackingState extends State<OrderLiveTracking> with _Polling<OrderLiveTracking, List<LiveParcel>> {
  bool _takingOver = false;

  @override
  Future<List<LiveParcel>> load() => LiveTrackingApi.order(widget.orderId);

  String _waited(LiveParcel p) {
    final at = p.offeredAt;
    if (at == null) return '';
    final m = DateTime.now().difference(at).inMinutes;
    return m > 0 ? ' ($m min so far)' : '';
  }

  /// The seller delivers a parcel no rider has taken (and keeps the fee).
  Future<void> _takeOver() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deliver it yourself?'),
        content: const Text("Ikiguzi stops looking for a rider, the delivery fee goes to you, and you confirm the hand-over with the buyer's 6-digit code."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep waiting')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Deliver it myself')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _takingOver = true);
    try {
      final r = asMap(await Api.instance.post('/orders/vendor/${widget.orderId}/self-deliver'));
      messenger.showSnackBar(SnackBar(content: Text(strOf(r['message'], "You're delivering this parcel."))));
      final fresh = await load();
      if (mounted) setState(() => data = fresh);
      widget.onChanged?.call();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _takingOver = false);
    }
  }

  @override
  Duration nextAfter(List<LiveParcel> value) {
    final live = value.where((p) => p.active);
    return live.isEmpty ? const Duration(seconds: 30) : live.first.refreshAfter;
  }

  @override
  Widget build(BuildContext context) {
    final parcels = data ?? const <LiveParcel>[];
    final live = parcels.where((p) => p.active).toList();
    final waiting = parcels.where((p) => !p.active && p.status == 'READY_FOR_PICKUP').toList();
    if (live.isEmpty && waiting.isEmpty) return const SizedBox.shrink();
    final mv = context.mv;
    return Column(children: [
      for (final p in live)
        DataCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.seller && p.phase == 'to_store' ? 'A rider is coming for your parcel' : p.phaseLabel, style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                  Text('From ${p.storeName}', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                ]),
              ),
              if (p.durationS != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(p.minutesLeft, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: mv.text)),
                  Text('${kmLeft(p.distanceM ?? 0)} · about ${p.timeAt}', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                ]),
            ]),
            const SizedBox(height: 10),
            Text('${p.riderName} · ${p.vehicle}${p.plateNumber.isEmpty ? '' : ' · ${p.plateNumber}'}', style: TextStyle(color: mv.text, fontSize: 13)),
            if (p.rider == null) Text("Waiting for the rider's location.", style: TextStyle(color: mv.textMuted, fontSize: 12)),
            if (p.stale && p.seenAt != null)
              Text('Last seen at ${p.seenAt!.hour.toString().padLeft(2, '0')}:${p.seenAt!.minute.toString().padLeft(2, '0')}.', style: TextStyle(color: mv.textMuted, fontSize: 12)),
            const SizedBox(height: 10),
            LiveDeliveryMap(parcel: p),
            if (p.riderPhone.isNotEmpty) ...[
              const SizedBox(height: 10),
              OutlineBtn(label: 'Call the rider', icon: Icons.call_outlined, compact: true, onPressed: () => launchUrl(Uri.parse('tel:${p.riderPhone}'))),
            ],
          ]),
        ),
      for (final p in waiting)
        DataCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.seller ? 'Looking for a rider' : p.statusLabel, style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
            const SizedBox(height: 2),
            Text(
              widget.seller
                  ? 'Ikiguzi is offering the parcel from ${p.storeName} to riders near your store${_waited(p)}. Riders who come online nearby get it too.'
                  : 'Ikiguzi is finding a rider for the parcel from ${p.storeName}.',
              style: TextStyle(color: mv.textMuted, fontSize: 12),
            ),
            if (widget.seller && p.waitingForRider) ...[
              const SizedBox(height: 10),
              OutlineBtn(label: 'Deliver it myself', icon: Icons.delivery_dining_outlined, compact: true, loading: _takingOver, onPressed: _takingOver ? null : _takeOver),
            ],
          ]),
        ),
    ]);
  }
}

/// The rider's trip: the next turn, time left and the map, refreshed every few seconds.
class RiderNavigation extends StatefulWidget {
  const RiderNavigation({super.key, required this.deliveryId});
  final String deliveryId;

  @override
  State<RiderNavigation> createState() => _RiderNavigationState();
}

class _RiderNavigationState extends State<RiderNavigation> with _Polling<RiderNavigation, LiveParcel> {
  @override
  Future<LiveParcel> load() => LiveTrackingApi.navigation(widget.deliveryId);

  @override
  Duration nextAfter(LiveParcel value) => value.refreshAfter;

  @override
  Widget build(BuildContext context) {
    final p = data;
    if (p == null || !p.active) return const SizedBox.shrink();
    final mv = context.mv;
    final next = p.steps.where((s) => s.$2 > 0).firstOrNull ?? p.steps.firstOrNull;
    return DataCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.target == 'store' ? 'To ${p.storeName}' : 'To the buyer', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text))),
          if (p.durationS != null) Text('${p.minutesLeft} · ${kmLeft(p.distanceM ?? 0)}', style: TextStyle(fontWeight: FontWeight.w700, color: mv.text)),
        ]),
        // Straight-line routes have no real turns to show.
        if (next != null && p.steps.length > 1) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(10)),
            child: Text('${next.$1}${next.$2 > 0 ? ' in ${kmLeft(next.$2)}' : ''}', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
          ),
        ],
        if (p.rider == null) Text('Allow location so the map can follow you.', style: TextStyle(color: mv.textMuted, fontSize: 12)),
        const SizedBox(height: 10),
        LiveDeliveryMap(parcel: p, height: 300),
      ]),
    );
  }
}
