import '../../core/api_client.dart';
import '../../core/format.dart';

/// The rider's own account (`/api/rider/me`).
class RiderAccount {
  const RiderAccount({required this.name, required this.phone, required this.vehicleType, required this.plateNumber, required this.status, required this.reviewNote, required this.isOnline});

  final String name;
  final String phone;
  final String vehicleType;
  final String plateNumber;

  /// PENDING, APPROVED, REJECTED or SUSPENDED.
  final String status;
  final String reviewNote;
  final bool isOnline;

  bool get approved => status == 'APPROVED';

  factory RiderAccount.fromJson(Map<String, dynamic> r) => RiderAccount(
        name: strOf(r['name']),
        phone: strOf(r['phone']),
        vehicleType: strOf(r['vehicleType'], 'MOTORBIKE'),
        plateNumber: strOf(r['plateNumber']),
        status: strOf(r['status'], 'PENDING'),
        reviewNote: strOf(r['reviewNote']),
        isOnline: r['isOnline'] == true,
      );
}

class Place {
  const Place({required this.name, required this.address, this.lat, this.lng});
  final String name;
  final String address;
  final double? lat;
  final double? lng;

  factory Place.fromJson(Map<String, dynamic> m) => Place(
        name: strOf(m['name']),
        address: strOf(m['address']),
        lat: m['lat'] == null ? null : numOf(m['lat']).toDouble(),
        lng: m['lng'] == null ? null : numOf(m['lng']).toDouble(),
      );
}

/// One seller's parcel to deliver. The server decides which step comes next
/// ([allowedNextStatuses]) and when the code can be entered ([canConfirm]).
class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.allowedNextStatuses,
    required this.canConfirm,
    required this.fee,
    required this.distanceKm,
    required this.distanceToPickupKm,
    required this.pickup,
    required this.dropoff,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.offerExpiresAt,
    required this.deliveredAt,
  });

  final String id;
  final String orderNumber;
  final String status;
  final String statusLabel;
  final List<String> allowedNextStatuses;
  final bool canConfirm;
  final num fee;
  final num distanceKm;
  final num? distanceToPickupKm;
  final Place pickup;
  final Place dropoff;
  final String customerName;
  final String customerPhone;
  final List<String> items;
  final DateTime? offerExpiresAt;
  final DateTime? deliveredAt;

  factory DeliveryJob.fromJson(Map<String, dynamic> d) {
    final customer = asMap(d['customer']);
    return DeliveryJob(
      id: strOf(d['id']),
      orderNumber: strOf(d['orderNumber']),
      status: strOf(d['status']),
      statusLabel: strOf(d['statusLabel']),
      allowedNextStatuses: [for (final s in (d['allowedNextStatuses'] as List? ?? const [])) '$s'],
      canConfirm: d['canConfirm'] == true,
      fee: numOf(d['fee']),
      distanceKm: numOf(d['distanceKm']),
      distanceToPickupKm: d['distanceToPickupKm'] == null ? null : numOf(d['distanceToPickupKm']),
      pickup: Place.fromJson(asMap(d['pickup'])),
      dropoff: Place.fromJson(asMap(d['dropoff'])),
      customerName: strOf(customer['name']),
      customerPhone: strOf(customer['phone']),
      items: [for (final i in asMaps(d['items'])) '${numOf(i['quantity']).toInt()} × ${strOf(i['name'])}'],
      offerExpiresAt: parseDate(d['offerExpiresAt']),
      deliveredAt: parseDate(d['deliveredAt']),
    );
  }
}

class RiderStats {
  const RiderStats({required this.todayDeliveries, required this.todayEarnings, required this.totalDeliveries, required this.totalEarnings});
  final int todayDeliveries;
  final num todayEarnings;
  final int totalDeliveries;
  final num totalEarnings;

  factory RiderStats.fromJson(Map<String, dynamic> s) => RiderStats(
        todayDeliveries: numOf(s['todayDeliveries']).toInt(),
        todayEarnings: numOf(s['todayEarnings']),
        totalDeliveries: numOf(s['totalDeliveries']).toInt(),
        totalEarnings: numOf(s['totalEarnings']),
      );
}

/// `/api/rider/*`, one method per endpoint.
class RiderApi {
  RiderApi._();
  static final _api = Api.instance;

  /// Step 1 of signing up: a code to the phone.
  static Future<void> sendCode(String phone, {required bool signUp}) async =>
      _api.post('/auth/send-otp', body: {'phone': phone, 'purpose': signUp ? 'registration' : 'login'});

  /// Sign in with the code: returns the raw `{ token, user }` reply.
  static Future<Map<String, dynamic>> signIn(String phone, String code) async =>
      asMap(await _api.post('/auth/verify-otp', body: {'phone': phone, 'code': code, 'purpose': 'login'}));

  /// Sign up: verify the code, then create the rider account.
  static Future<Map<String, dynamic>> signUp({
    required String phone,
    required String code,
    required String fullName,
    required String vehicleType,
    required String plateNumber,
  }) async {
    final verified = asMap(await _api.post('/auth/verify-otp', body: {'phone': phone, 'code': code, 'purpose': 'registration', 'role': 'delivery'}));
    return asMap(await _api.post('/rider/register', body: {
      'verificationToken': strOf(verified['verificationToken']),
      'fullName': fullName,
      'vehicleType': vehicleType,
      'plateNumber': plateNumber,
    }));
  }

  static Future<RiderAccount> me() async => RiderAccount.fromJson(asMap(asMap(await _api.get('/rider/me'))['rider']));

  static Future<RiderAccount> setOnline(bool online) async =>
      RiderAccount.fromJson(asMap(asMap(await _api.patch('/rider/availability', body: {'isOnline': online}))['rider']));

  static Future<void> sendLocation(double lat, double lng) async => _api.patch('/rider/location', body: {'lat': lat, 'lng': lng});

  static Future<RiderStats> stats() async => RiderStats.fromJson(asMap(await _api.get('/rider/stats')));

  static Future<List<DeliveryJob>> available() async =>
      [for (final d in asMaps(asMap(await _api.get('/rider/deliveries/available'))['deliveries'])) DeliveryJob.fromJson(d)];

  static Future<DeliveryJob?> active() async {
    final d = asMap(await _api.get('/rider/deliveries/active'))['delivery'];
    return d is Map ? DeliveryJob.fromJson(asMap(d)) : null;
  }

  static Future<List<DeliveryJob>> history() async =>
      [for (final d in asMaps(asMap(await _api.get('/rider/deliveries/history'))['deliveries'])) DeliveryJob.fromJson(d)];

  static Future<DeliveryJob> accept(String id) async =>
      DeliveryJob.fromJson(asMap(asMap(await _api.post('/rider/deliveries/$id/accept'))['delivery']));

  static Future<void> decline(String id) async => _api.post('/rider/deliveries/$id/reject');

  static Future<DeliveryJob> step(String id, String status) async =>
      DeliveryJob.fromJson(asMap(asMap(await _api.patch('/rider/deliveries/$id/status', body: {'status': status}))['delivery']));

  /// The buyer's 6-digit code completes the parcel; returns what was earned.
  static Future<num> confirm(String id, String code) async => numOf(asMap(await _api.post('/rider/deliveries/$id/confirm', body: {'code': code}))['earned']);

  static Future<Map<String, dynamic>> wallet() async => asMap(asMap(await _api.get('/rider/wallet'))['wallet']);

  static Future<List<Map<String, dynamic>>> withdrawals() async => asMaps(asMap(await _api.get('/rider/wallet/withdrawals'))['payouts']);

  static Future<String> withdraw({required num amount, required String accountName, required String number}) async =>
      strOf(asMap(await _api.post('/rider/wallet/withdrawals', body: {
        'amount': amount,
        'payoutDetails': {'accountName': accountName, 'accountNumber': number},
      }))['message']);
}
