import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/core/api_client.dart';

import 'helpers/fake_backend.dart';

/// When the app signs a person out on its own. Mirrors KitchenLink's
/// session rules: only a refused *signed-in* call ends the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<SessionEvent> events;
  setUp(() async {
    events = [];
    Api.instance.sessionEvents.listen(events.add);
    await TokenStore.instance.write('jwt-1');
  });

  void serve(int status, Object body) {
    Api.instance.dio.httpClientAdapter = FakeBackend({'GET /orders/my-orders': (_) => (status, body)});
  }

  Future<ApiException> fail() async {
    try {
      await Api.instance.get('/orders/my-orders');
    } on ApiException catch (e) {
      return e;
    }
    throw StateError('the call should have failed');
  }

  test('a 401 on a signed-in call ends the session', () async {
    serve(401, {'message': 'Not authorized, token failed'});
    final e = await fail();
    await pumpEventQueue();
    expect(e.message, 'Your session has ended. Please sign in again.');
    expect(await TokenStore.instance.read(), isNull);
    expect(events, [SessionEvent.expired]);
  });

  test('a blocked account is signed out and told why', () async {
    serve(403, {'message': 'This account is blocked.', 'code': 'ACCOUNT_BLOCKED'});
    final e = await fail();
    await pumpEventQueue();
    expect(e.code, 'ACCOUNT_BLOCKED');
    expect(events, [SessionEvent.blocked]);
  });

  test('a 401 with no token (a wrong password) does not raise a session event', () async {
    await TokenStore.instance.clear();
    serve(401, {'message': 'Invalid email or password.'});
    final e = await fail();
    await pumpEventQueue();
    expect(e.message, 'Invalid email or password.');
    expect(events, isEmpty);
  });

  test('a server error keeps the session and shows the support reference', () async {
    serve(500, {'message': 'Internal Server Error', 'reference': 'ERR-42'});
    final e = await fail();
    await pumpEventQueue();
    expect(e.message, contains('reference ERR-42'));
    expect(await TokenStore.instance.read(), 'jwt-1');
    expect(events, isEmpty);
  });

  test('other refusals keep the session', () async {
    serve(403, {'message': "Your account isn't allowed to do this."});
    await fail();
    await pumpEventQueue();
    expect(await TokenStore.instance.read(), 'jwt-1');
    expect(events, isEmpty);
  });
}
