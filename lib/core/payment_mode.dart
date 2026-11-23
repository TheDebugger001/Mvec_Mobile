import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'format.dart';

/// Whether the server simulates payments (`GET /api/payments/mode`): true while
/// no gateway is connected and the backend runs with TEST_PAYMENTS. No money
/// moves then, so the app says so. An older server without the endpoint, or no
/// connection, counts as not in test mode.
final paymentTestModeProvider = FutureProvider<bool>((ref) async {
  try {
    return asMap(await Api.instance.get('/payments/mode'))['testMode'] == true;
  } catch (_) {
    return false;
  }
});
