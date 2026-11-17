import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/fake_backend.dart';

Map<String, dynamic> _order() => {
      'id': 'o1',
      '_id': 'o1',
      'orderNumber': 'ORD-LIVE-1',
      'orderStatus': 'OUT_FOR_DELIVERY',
      'paymentStatus': 'PAID',
      'totalAmount': 31060,
      'createdAt': DateTime.now().toIso8601String(),
      'items': [
        {'name': 'Wireless Earbuds', 'price': 30000, 'quantity': 1, 'product': 'p1'},
      ],
    };

Map<String, dynamic> _live() => {
      'parcels': [
        {
          'active': true,
          'deliveryId': 'd1',
          'status': 'OUT_FOR_DELIVERY',
          'statusLabel': 'On the way to the buyer',
          'phase': 'to_buyer',
          'phaseLabel': 'On the way to the buyer',
          'target': 'buyer',
          'rider': {
            'name': 'Jean Rider',
            'phone': '0788555003',
            'vehicleType': 'MOTORBIKE',
            'plateNumber': 'RAB 123 A',
            'location': {'lat': -1.955, 'lng': 30.099, 'heading': 75, 'stale': false, 'at': DateTime.now().toIso8601String()},
          },
          'store': {'name': 'Kigali Tech Store', 'lat': -1.9536, 'lng': 30.0936},
          'destination': {'address': 'KG 11 Ave', 'lat': -1.9578, 'lng': 30.1127},
          'route': {
            'source': 'straight',
            'geometry': [
              [30.099, -1.955],
              [30.1127, -1.9578],
            ],
            'distanceM': 1600,
            'durationS': 400,
            'etaAt': DateTime.now().add(const Duration(minutes: 7)).toIso8601String(),
          },
          'refreshAfterS': 4,
        },
        {'active': false, 'deliveryId': 'd2', 'status': 'READY_FOR_PICKUP', 'statusLabel': 'Waiting for a rider', 'store': {'name': 'Urban Closet'}},
      ],
    };

void main() {
  testWidgets('the buyer follows the rider: who, how long, the map; a parcel without a rider says so', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'GET /auth/me': (_) => (200, {'user': userJson('buyer')}),
      'GET /orders/o1': (_) => (200, {'order': _order()}),
      'GET /orders/o1/live': (_) => (200, _live()),
    });
    await pumpApp(tester, backend, token: 'jwt-buyer');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/orders/o1');
    await settle(tester);

    expect(backend.where('GET', '/orders/o1/live'), isNotEmpty);
    expect(find.text('On the way to the buyer'), findsOneWidget);
    expect(find.text('Jean Rider · Motorbike · RAB 123 A'), findsOneWidget);
    expect(find.text('7 min'), findsOneWidget);
    expect(find.textContaining('1.6 km'), findsOneWidget);
    expect(find.text('Call the rider'), findsOneWidget);
    expect(find.text('Ikiguzi is finding a rider for the parcel from Urban Closet.'), findsOneWidget);

    // It keeps following the rider.
    final calls = backend.where('GET', '/orders/o1/live').length;
    await tester.pump(const Duration(seconds: 5));
    expect(backend.where('GET', '/orders/o1/live').length, greaterThan(calls));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });
}
