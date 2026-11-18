import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import 'rider_api.dart';

/// Everything the rider's home screen shows, refreshed every 10 seconds
/// (KitchenLink's delivery-worker rhythm). A failed refresh keeps the last
/// good board and only shows the error.
class RiderBoard {
  const RiderBoard({required this.account, required this.stats, required this.active, required this.offers, this.error});
  final RiderAccount account;
  final RiderStats stats;
  final DeliveryJob? active;
  final List<DeliveryJob> offers;
  final String? error;

  RiderBoard copyWith({RiderAccount? account, DeliveryJob? active, bool clearActive = false, List<DeliveryJob>? offers, String? error}) => RiderBoard(
        account: account ?? this.account,
        stats: stats,
        active: clearActive ? null : (active ?? this.active),
        offers: offers ?? this.offers,
        error: error,
      );
}

class RiderBoardNotifier extends AsyncNotifier<RiderBoard> {
  Timer? _timer;

  @override
  Future<RiderBoard> build() async {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    return _load();
  }

  Future<RiderBoard> _load() async {
    final account = await RiderApi.me();
    if (!account.approved) {
      return RiderBoard(account: account, stats: const RiderStats(todayDeliveries: 0, todayEarnings: 0, totalDeliveries: 0, totalEarnings: 0), active: null, offers: const []);
    }
    final results = await Future.wait<dynamic>([RiderApi.stats(), RiderApi.active()]);
    final active = results[1] as DeliveryJob?;
    // One parcel at a time: no offers while a trip is open.
    final offers = account.isOnline && active == null ? await RiderApi.available() : const <DeliveryJob>[];
    return RiderBoard(account: account, stats: results[0] as RiderStats, active: active, offers: offers);
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await _load());
    } catch (e) {
      final last = state.valueOrNull;
      state = last == null ? AsyncError(e, StackTrace.current) : AsyncData(last.copyWith(error: errorText(e)));
    }
  }

  Future<void> setOnline(bool online) async {
    final account = await RiderApi.setOnline(online);
    state = AsyncData(state.requireValue.copyWith(account: account));
    await refresh();
  }

  Future<DeliveryJob> accept(String id) async {
    final job = await RiderApi.accept(id);
    state = AsyncData(state.requireValue.copyWith(active: job, offers: const []));
    return job;
  }

  Future<void> decline(String id) async {
    await RiderApi.decline(id);
    state = AsyncData(state.requireValue.copyWith(offers: state.requireValue.offers.where((o) => o.id != id).toList()));
  }

  Future<void> handBack(String id) async {
    await RiderApi.handBack(id);
    await refresh();
  }

  Future<void> step(String id, String status) async {
    final job = await RiderApi.step(id, status);
    state = AsyncData(state.requireValue.copyWith(active: job));
  }

  Future<num> confirm(String id, String code) async {
    final earned = await RiderApi.confirm(id, code);
    await refresh();
    return earned;
  }
}

final riderBoardProvider = AsyncNotifierProvider<RiderBoardNotifier, RiderBoard>(RiderBoardNotifier.new);

/* --------------------------------- GPS -------------------------------- */

/// One GPS reading.
class GeoFix {
  const GeoFix(this.lat, this.lng, this.at);
  final double lat;
  final double lng;
  final DateTime at;

  double metresTo(GeoFix o) {
    double rad(double d) => d * math.pi / 180;
    final x = rad(o.lng - lng) * math.cos(rad((lat + o.lat) / 2));
    final y = rad(o.lat - lat);
    return math.sqrt(x * x + y * y) * 6371000;
  }
}

/// When a live fix is worth sending during a delivery: at most every 4 s when
/// the rider moved 8 m or more, and at least every 15 s while standing still
/// (KitchenLink's rules). Pure, so it can be tested.
bool shouldSendLiveFix({required GeoFix fix, GeoFix? lastSent}) {
  if (lastSent == null) return true;
  final since = fix.at.difference(lastSent.at);
  if (since < const Duration(seconds: 4)) return false;
  return fix.metresTo(lastSent) >= 8 || since >= const Duration(seconds: 15);
}

/// The phone's position while the rider is online, foreground only: once a
/// minute while waiting for offers, and a live stream during a trip.
class RiderLocation {
  RiderLocation(this.send);
  final Future<void> Function(double lat, double lng, {double? heading, double? speedMps, double? accuracyM}) send;

  /// Heading only means something while moving; negative values mean "unknown".
  static ({double? heading, double? speedMps, double? accuracyM}) readings(Position p) => (
        heading: p.speed > 0.5 && p.heading >= 0 ? p.heading : null,
        speedMps: p.speed >= 0 ? p.speed : null,
        accuracyM: p.accuracy >= 0 ? p.accuracy : null,
      );
  Timer? _timer;
  StreamSubscription<Position>? _live;
  GeoFix? _lastSent;
  String _mode = 'off';

  /// Follows the board: offline → nothing, online → once a minute, on a trip → live.
  void follow(RiderBoard board) {
    final mode = !board.account.approved || !board.account.isOnline ? 'off' : board.active != null ? 'trip' : 'waiting';
    if (mode == _mode) return;
    _mode = mode;
    if (mode == 'off') {
      stop();
    } else if (mode == 'trip') {
      onTrip();
    } else {
      waiting();
    }
  }

  /// Null when allowed; otherwise what to tell the rider.
  static Future<String?> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'Turn on location on your phone to receive deliveries near you.';
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) return "Allow location for Ikiguzi in your phone's settings to receive deliveries.";
    if (permission == LocationPermission.denied) return 'Allow location so Ikiguzi can offer you deliveries nearby.';
    return null;
  }

  Future<void> _sendNow() async {
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      final r = readings(p);
      await send(p.latitude, p.longitude, heading: r.heading, speedMps: r.speedMps, accuracyM: r.accuracyM);
      _lastSent = GeoFix(p.latitude, p.longitude, DateTime.now());
    } catch (_) {
      // No fix this time; the next tick tries again.
    }
  }

  /// Online, waiting: the position first (so the first offers are nearby), then once a minute.
  Future<void> waiting() async {
    _live?.cancel();
    _live = null;
    await _sendNow();
    // Stopped (or on a trip) while the first fix was coming in.
    if (_mode != 'waiting') return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _sendNow());
  }

  /// During a trip: every meaningful move, so the buyer can follow the parcel.
  void onTrip() {
    _timer?.cancel();
    _timer = null;
    _live ??= Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen((p) {
      final fix = GeoFix(p.latitude, p.longitude, DateTime.now());
      if (!shouldSendLiveFix(fix: fix, lastSent: _lastSent)) return;
      _lastSent = fix;
      final r = readings(p);
      send(fix.lat, fix.lng, heading: r.heading, speedMps: r.speedMps, accuracyM: r.accuracyM).catchError((_) {});
    });
  }

  void stop() {
    _mode = 'off';
    _timer?.cancel();
    _live?.cancel();
    _timer = null;
    _live = null;
  }
}

/// Kept alive by the rider screens; follows the board.
final riderLocationProvider = Provider<RiderLocation>((ref) {
  final location = RiderLocation(RiderApi.sendLocation);
  ref.onDispose(location.stop);
  ref.listen(riderBoardProvider, (_, next) {
    final board = next.valueOrNull;
    if (board != null) location.follow(board);
  }, onError: (_, _) {}, fireImmediately: true); // the screens show a failed load
  return location;
});
