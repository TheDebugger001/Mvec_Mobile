import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mvec_mobile/features/rider/rider_state.dart';

import 'helpers/fake_backend.dart';

Map<String, dynamic> _rider({String status = 'APPROVED', bool online = true}) => {
      'rider': {'name': 'Eric Moto', 'phone': '0788555222', 'vehicleType': 'MOTORBIKE', 'plateNumber': 'RAB123A', 'status': status, 'isOnline': online},
    };

Map<String, dynamic> _job({String status = 'READY_FOR_PICKUP', List<String> next = const []}) => {
      'id': 'd1',
      'orderNumber': 'ORD-1',
      'status': status,
      'statusLabel': status == 'ASSIGNED' ? 'Rider on the way to the store' : 'Waiting for a rider',
      'allowedNextStatuses': next,
      'canConfirm': false,
      'fee': 1300,
      'distanceKm': 2.8,
      'distanceToPickupKm': 0.3,
      'pickup': {'name': 'Kigali Gadgets', 'address': 'KG 7 Ave', 'lat': -1.95, 'lng': 30.09},
      'dropoff': {'address': 'Gasabo', 'lat': null, 'lng': null},
      'customer': null,
      'items': [{'name': 'Headphones', 'quantity': 1}],
    };

Future<void> _openDashboard(WidgetTester tester, FakeBackend backend) async {
  await pumpApp(tester, backend, token: 'jwt-rider');
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/delivery');
  await settle(tester);
}

void main() {
  testWidgets('an online rider sees a nearby offer, accepts it and gets the trip with the first step', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'GET /auth/me': (_) => (200, {'user': userJson('delivery', name: 'Eric Moto')}),
      'GET /rider/me': (_) => (200, _rider()),
      'GET /rider/stats': (_) => (200, {'todayDeliveries': 2, 'todayEarnings': 2600, 'totalDeliveries': 9, 'totalEarnings': 11700}),
      'GET /rider/deliveries/active': (_) => (200, {'delivery': null}),
      'GET /rider/deliveries/available': (_) => (200, {'deliveries': [_job()]}),
      'POST /rider/deliveries/d1/accept': (_) => (200, {'delivery': _job(status: 'ASSIGNED', next: ['PICKED_UP'])}),
    });
    await _openDashboard(tester, backend);

    expect(find.text("You're online"), findsOneWidget);
    expect(find.text('Kigali Gadgets'), findsOneWidget);
    expect(find.textContaining('0.3 km from you'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await settle(tester);

    expect(backend.where('POST', '/rider/deliveries/d1/accept'), hasLength(1));
    expect(find.text('Slide when you have the parcel'), findsOneWidget);
    expect(find.text('Directions to the store'), findsOneWidget);

    // Close the app and let the GPS request's 10-second time limit run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('a rider waiting for approval sees why they get no offers', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'GET /auth/me': (_) => (200, {'user': userJson('delivery')}),
      'GET /rider/me': (_) => (200, _rider(status: 'PENDING', online: false)),
    });
    await _openDashboard(tester, backend);

    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(backend.where('GET', '/rider/deliveries/available'), isEmpty);
  });

  group('live location during a trip (KitchenLink rules)', () {
    final t0 = DateTime(2026, 11, 13, 10);
    const lat = -1.95, lng = 30.09;
    final sent = GeoFix(lat, lng, t0);

    test('the first fix is always sent', () {
      expect(shouldSendLiveFix(fix: sent), isTrue);
    });

    test('never more often than every 4 seconds', () {
      expect(shouldSendLiveFix(fix: GeoFix(lat + 0.001, lng, t0.add(const Duration(seconds: 3))), lastSent: sent), isFalse);
    });

    test('after 4 seconds only when the rider moved 8 m, but at least every 15 seconds', () {
      expect(shouldSendLiveFix(fix: GeoFix(lat + 0.0001, lng, t0.add(const Duration(seconds: 5))), lastSent: sent), isTrue); // ~11 m
      expect(shouldSendLiveFix(fix: GeoFix(lat, lng, t0.add(const Duration(seconds: 10))), lastSent: sent), isFalse);
      expect(shouldSendLiveFix(fix: GeoFix(lat, lng, t0.add(const Duration(seconds: 15))), lastSent: sent), isTrue);
    });
  });

  testWidgets('a notification opens the parcel; an offline rider goes online and accepts it there', (tester) async {
    var online = false;
    final backend = FakeBackend({
      ...baseRoutes(),
      'GET /auth/me': (_) => (200, {'user': userJson('delivery', name: 'Eric Moto')}),
      'GET /rider/me': (_) => (200, _rider(online: online)),
      'GET /rider/stats': (_) => (200, {'todayDeliveries': 0, 'todayEarnings': 0, 'totalDeliveries': 0, 'totalEarnings': 0}),
      'GET /rider/deliveries/active': (_) => (200, {'delivery': null}),
      'GET /rider/deliveries/available': (_) => (200, {'deliveries': []}),
      'PATCH /rider/availability': (_) {
        online = true;
        return (200, _rider(online: true));
      },
      'GET /rider/deliveries/d1': (_) => (200, {'delivery': _job(), 'mine': false, 'canTake': true, 'online': online}),
      'POST /rider/deliveries/d1/accept': (_) => (200, {'delivery': _job(status: 'ASSIGNED', next: ['PICKED_UP'])}),
    });
    await _openDashboard(tester, backend);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/delivery/offers/d1');
    await settle(tester);

    expect(find.textContaining('Kigali Gadgets'), findsWidgets);
    expect(find.text('Accept'), findsNothing);
    await tester.tap(find.text('Go online to take it'));
    await settle(tester);
    await tester.tap(find.text('Accept'));
    await settle(tester);
    expect(backend.where('POST', '/rider/deliveries/d1/accept'), hasLength(1));
    expect(find.text('Slide when you have the parcel'), findsOneWidget);
    // The location timers stop with the app.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('a parcel another rider took says so', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'GET /auth/me': (_) => (200, {'user': userJson('delivery', name: 'Eric Moto')}),
      'GET /rider/me': (_) => (200, _rider()),
      'GET /rider/stats': (_) => (200, {'todayDeliveries': 0, 'todayEarnings': 0, 'totalDeliveries': 0, 'totalEarnings': 0}),
      'GET /rider/deliveries/active': (_) => (200, {'delivery': null}),
      'GET /rider/deliveries/available': (_) => (200, {'deliveries': []}),
      'GET /rider/deliveries/d1': (_) => (410, {'message': 'Another rider already took this parcel.'}),
    });
    await _openDashboard(tester, backend);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/delivery/offers/d1');
    await settle(tester);
    expect(find.text('Another rider already took this parcel.'), findsOneWidget);
    expect(find.text('See parcels near you'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });
}
