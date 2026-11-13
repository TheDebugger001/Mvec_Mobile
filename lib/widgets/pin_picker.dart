import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';
import '../features/rider/rider_state.dart' show RiderLocation;
import '../portal/kit.dart';

/// A place on the map: tap where it is, pinch to zoom (the website's
/// PinPicker). With [allowGps], a button drops it where the phone is (buyers
/// at home); a store's pin is never taken from GPS, since the seller may be away.
class PinPicker extends StatefulWidget {
  const PinPicker({super.key, required this.value, required this.onChanged, required this.label, this.help, this.allowGps = false});

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

  void _set(LatLng p) => widget.onChanged((_round(p.latitude), _round(p.longitude)));

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
          if (widget.allowGps) TextButton.icon(onPressed: _useMyLocation, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('Use my location')),
          if (v != null) TextButton(onPressed: () => widget.onChanged(null), child: const Text('Remove pin')),
          Tiny(_status ?? (v == null ? 'Tap the map to drop the pin.' : 'Pin set at ${v.$1}, ${v.$2}')),
        ]),
      ]),
    );
  }
}
