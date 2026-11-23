import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';

void main() {
  testWidgets('storefront shows the test-mode strip while payments are simulated', (tester) async {
    await pumpApp(tester, FakeBackend({...baseRoutes(), 'GET /payments/mode': (_) => (200, {'testMode': true})}));
    expect(find.textContaining('Payments are simulated'), findsOneWidget);
  });

  testWidgets('no strip when payments are real or the server has no mode endpoint', (tester) async {
    await pumpApp(tester, FakeBackend({...baseRoutes(), 'GET /payments/mode': (_) => (200, {'testMode': false})}));
    expect(find.textContaining('Payments are simulated'), findsNothing);
    await pumpApp(tester, FakeBackend(baseRoutes()));
    expect(find.textContaining('Payments are simulated'), findsNothing);
  });
}
