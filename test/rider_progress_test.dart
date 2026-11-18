import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/features/rider/rider_api.dart';
import 'package:mvec_mobile/features/rider/rider_trip_page.dart';

void main() {
  final job = DeliveryJob.fromJson({
    'id': 'd1',
    'orderNumber': 'IKG-1',
    'status': 'ASSIGNED',
    'statusLabel': 'Rider on the way to the store',
    'allowedNextStatuses': <String>[],
    'pickup': {'name': 'Kigali Gadgets'},
    'dropoff': {'address': 'Remera'},
    'ready': false,
    'waitingForSeller': true,
    'progress': [
      {'key': 'PLACED', 'label': 'Order placed', 'done': true, 'at': '2026-11-18T08:00:00Z'},
      {'key': 'PROCESSING', 'label': 'Seller preparing it', 'done': true},
      {'key': 'READY_FOR_SHIPMENT', 'label': 'Ready for pickup', 'done': false},
    ],
  });

  test('an early job says the seller is still preparing it and carries its progress', () {
    expect(job.ready, isFalse);
    expect(job.waitingForSeller, isTrue);
    expect(job.progress.map((s) => (s.key, s.done)), [('PLACED', true), ('PROCESSING', true), ('READY_FOR_SHIPMENT', false)]);
    expect(job.progress.first.at, isNotNull);
    // Older servers send neither: the job counts as ready.
    expect(DeliveryJob.fromJson({'id': 'x', 'pickup': {}, 'dropoff': {}}).ready, isTrue);
  });

  testWidgets('the timeline lists every step', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ParcelProgress(steps: job.progress))));
    for (final label in ['Order placed', 'Seller preparing it', 'Ready for pickup']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
