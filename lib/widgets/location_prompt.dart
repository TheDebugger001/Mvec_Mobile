import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../features/rider/rider_state.dart' show RiderLocation;
import '../state/auth_state.dart';
import 'common.dart';

const _why = {
  'buyer': 'so riders find your door and checkout starts with your pin',
  'vendor': 'so Ikiguzi riders can collect your parcels at your store',
  'supplier': 'so Ikiguzi riders can collect your parcels at your store',
  'delivery': 'so you get parcels near you',
};

/// The position this phone last shared, as checkout's starting pin.
class LastPin {
  static const _key = 'ikiguzi.lastPin';

  static (double, double)? read(SharedPreferences? prefs) {
    final parts = (prefs?.getString(_key) ?? '').split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    return lat == null || lng == null ? null : (lat, lng);
  }

  static Future<void> write(SharedPreferences? prefs, (double, double) pin) async => prefs?.setString(_key, '${pin.$1},${pin.$2}');
}

/// Once per account on this phone, after sign-in: share your location? A yes
/// pins it wherever the account has no pin yet (`POST /api/geo/me`); a pin the
/// person placed is never moved. Admins and affiliates aren't asked.
/// (web: `components/LocationPrompt.jsx`)
class LocationPrompt extends ConsumerStatefulWidget {
  const LocationPrompt({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LocationPrompt> createState() => _LocationPromptState();
}

class _LocationPromptState extends ConsumerState<LocationPrompt> {
  bool _open = false;
  bool _busy = false;
  String? _text;
  bool _done = false;
  String _userId = '';

  String _askedKey(String id) => 'ikiguzi.locationAsked.$id';

  void _check() {
    final user = ref.read(authProvider).user;
    final id = user?.id ?? '';
    if (id == _userId) return;
    _userId = id;
    final prefs = ref.read(sharedPreferencesProvider);
    final ask = user != null && _why.containsKey(user.role) && prefs != null && !prefs.containsKey(_askedKey(id));
    setState(() {
      _open = ask;
      _text = null;
      _done = false;
    });
  }

  Future<void> _close() async {
    await ref.read(sharedPreferencesProvider)?.setString(_askedKey(_userId), DateTime.now().toIso8601String());
    if (mounted) setState(() => _open = false);
  }

  Future<void> _share() async {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() {
      _busy = true;
      _text = 'Finding you…';
    });
    await prefs?.setString(_askedKey(_userId), DateTime.now().toIso8601String());
    String message;
    final problem = await RiderLocation.ensureAccess();
    if (problem != null) {
      message = "Location wasn't shared. You can pin it on the map any time.";
    } else {
      try {
        final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
        final pin = ((p.latitude * 1e6).roundToDouble() / 1e6, (p.longitude * 1e6).roundToDouble() / 1e6);
        await LastPin.write(prefs, pin);
        try {
          final r = asMap(await Api.instance.post('/geo/me', body: {'lat': pin.$1, 'lng': pin.$2}));
          message = strOf(r['message'], 'Location saved.');
        } catch (_) {
          message = 'Location saved on this phone. Checkout will start from it.';
        }
      } catch (_) {
        message = "We couldn't get your location. You can pin it on the map any time.";
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = true;
      _text = message;
    });
    await Future<void>.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (_, __) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
    if (!_open) return widget.child;
    final mv = context.mv;
    final role = ref.read(authProvider).user?.role ?? '';
    return Stack(children: [
      widget.child,
      Positioned(
        left: 16,
        right: 16,
        bottom: 96 + MediaQuery.paddingOf(context).bottom,
        child: SafeArea(
          top: false,
          child: Material(
            elevation: 8,
            color: mv.surface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Share your location?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: mv.text)),
                const SizedBox(height: 4),
                Text(_text ?? 'Ikiguzi pins it on the map ${_why[role] ?? ''}. You can move the pin any time.', style: TextStyle(color: mv.textMuted, fontSize: 13.5, height: 1.4)),
                if (!_done) ...[
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Flexible(child: OutlineBtn(label: 'Not now', compact: true, onPressed: _busy ? null : _close)),
                    const SizedBox(width: 8),
                    Flexible(child: GradientButton(label: 'Share location', compact: true, loading: _busy, onPressed: _busy ? null : _share)),
                  ]),
                ],
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
