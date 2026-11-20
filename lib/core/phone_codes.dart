import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'format.dart';

/// Whether guest checkout, "follow my order" and rider sign-up ask for a text
/// code (`GET /api/auth/phone-codes`). Off until SMS is set up on the server;
/// an older server without the endpoint keeps codes on.
final phoneCodesProvider = FutureProvider<bool>((ref) async {
  try {
    return asMap(await Api.instance.get('/auth/phone-codes'))['required'] == true;
  } catch (_) {
    return true;
  }
});
