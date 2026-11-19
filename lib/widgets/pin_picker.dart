import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../features/rider/rider_state.dart' show RiderLocation;
import '../portal/kit.dart';

/// A place on the map: tap where it is, pinch to zoom (the website's
/// PinPicker). With [allowGps], a button drops it where the phone is. With
/// [searchText] (the street, sector and district typed beside it), the pin
/// follows the address (`/api/geo/search`) until it's placed by hand.
class PinPicker extends StatefulWidget {
  const PinPicker({super.key, required this.value, required this.onChanged, required this.label, this.help, this.allowGps = false, this.searchText = ''});

  final String searchText;

  /// `(lat, lng)` or null.
  final (double, double)? value;
  final ValueChanged<(double, double)?> onChanged;
  final String label;
  final String? help;
  final bool allowGps;

  @override
  State<PinPicker> createState() => _PinPickerState();
}

const _kigali = LatLng(-1.9441, 30.0619);
double _round(double v) => (v * 1e6).roundToDouble() / 1e6;

class _PinPickerState extends State<PinPicker> {
  final _map = MapController();
  String? _status;
  String? _found;
  Timer? _debounce;
  // Placed by hand (tap, GPS): typing the address no longer moves it.
  late bool _byHand = widget.value != null;

  void _set(LatLng p) {
    _byHand = true;
    _found = null;
    widget.onChanged((_round(p.latitude), _round(p.longitude)));
  }

  String _query(String s) => s.replaceAll(RegExp(r'[\s,]+'), ' ').trim();

  @override
  void didUpdateWidget(PinPicker old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v != null && v != old.value) {
      try {
        _map.move(LatLng(v.$1, v.$2), 16);
      } catch (_) {
        // The map isn't laid out yet; it starts on the pin.
      }
    }
    final q = _query(widget.searchText);
    if (q == _query(old.searchText) || q.length < 4 || _byHand) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () async {
      try {
        final results = asMaps(asMap(await Api.instance.get('/geo/search', query: {'q': widget.searchText}))['results']);
        if (!mounted || _byHand || results.isEmpty) return;
        final best = results.first;
        setState(() => _found = strOf(best['label']));
        widget.onChanged((_round(numOf(best['lat']).toDouble()), _round(numOf(best['lng']).toDouble())));
      } catch (_) {
        // No match or no connection: the person taps the map instead.
      }
    });
  }

  /// "Find on map": pins the typed address now, even over a pin placed by hand.
  bool _finding = false;
  Future<void> _findTyped() async {
    setState(() {
      _finding = true;
      _status = null;
    });
    try {
      final results = asMaps(asMap(await Api.instance.get('/geo/search', query: {'q': widget.searchText}))['results']);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _status = "We couldn't find that address on the map. Add the sector, or tap the spot on the map.");
        return;
      }
      final best = results.first;
      final here = LatLng(numOf(best['lat']).toDouble(), numOf(best['lng']).toDouble());
      _byHand = false;
      setState(() => _found = strOf(best['label']));
      widget.onChanged((_round(here.latitude), _round(here.longitude)));
    } catch (_) {
      if (mounted) setState(() => _status = "The map search isn't answering. Tap the spot on the map instead.");
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    final problem = await RiderLocation.ensureAccess();
    if (problem != null) return setState(() => _status = problem);
    setState(() => _status = 'Finding you…');
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      final here = LatLng(p.latitude, p.longitude);
      _set(here);
      _map.move(here, 16);
      if (mounted) setState(() => _status = null);
    } catch (_) {
      if (mounted) setState(() => _status = "We couldn't get your location. Tap the map where you are instead.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final v = widget.value;
    final point = v == null ? null : LatLng(v.$1, v.$2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text)),
        if (widget.help != null) Tiny(widget.help!),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: point ?? _kigali,
                initialZoom: point == null ? 12 : 16,
                onTap: (_, p) => _set(p),
                // Inside a scrolling form a drag scrolls the page; pinch to zoom, tap to pin.
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
              ),
              children: [
                TileLayer(urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', userAgentPackageName: 'com.ikiguzi.app', retinaMode: true),
                if (point != null)
                  MarkerLayer(markers: [
                    Marker(point: point, width: 40, height: 40, alignment: Alignment.topCenter, child: Icon(Icons.location_on_rounded, color: mv.accentDeep, size: 40)),
                  ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap, © CARTO')]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_query(widget.searchText).length >= 4)
            FilledButton.tonalIcon(
              onPressed: _finding ? null : _findTyped,
              icon: _finding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore_rounded, size: 18),
              label: Text(_finding ? 'Finding…' : 'Find on map'),
            ),
          if (widget.allowGps) TextButton.icon(onPressed: _useMyLocation, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('Use my location')),
          if (v != null)
            TextButton(
              onPressed: () {
                _byHand = false;
                _found = null;
                widget.onChanged(null);
              },
              child: const Text('Remove pin'),
            ),
          Tiny(_status ??
              (_found != null && v != null
                  ? "Pinned from the address ($_found). Tap the map if it's off."
                  : v == null
                      ? (widget.searchText.isEmpty ? 'Tap the map to drop the pin.' : 'Type the street and the pin follows, or tap the map.')
                      : 'Pin set at ${v.$1}, ${v.$2}')),
        ]),
      ]),
    );
  }
}
