import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Where the Ikiguzi backend lives (the `/api` root).
///
/// Resolution order, highest priority first:
///  1. `--dart-define=API_BASE_URL=...`  (a build can target any host)
///  2. `API_BASE_URL` in the bundled `.env`
///  3. `http://localhost:4000/api`
///
/// `localhost` means "this device" on a phone. On the Android emulator the
/// host machine is `10.0.2.2`, so a localhost URL is rewritten for Android
/// automatically; on a real device set a LAN IP or the hosted URL.
String get apiBaseUrl {
  const defined = String.fromEnvironment('API_BASE_URL');
  var url = defined.trim();
  if (url.isEmpty) {
    try {
      url = (dotenv.maybeGet('API_BASE_URL') ?? '').trim();
    } catch (_) {
      // dotenv not loaded (tests).
    }
  }
  if (url.isEmpty) url = 'http://localhost:4000/api';
  url = url.replaceAll(RegExp(r'/+$'), '');
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    url = url.replaceFirst(RegExp(r'//(localhost|127\.0\.0\.1)'), '//10.0.2.2');
  }
  return url;
}

/// Origin that serves the REST API and `/uploads` (the base URL minus `/api`).
String get apiOrigin => apiBaseUrl.replaceFirst(RegExp(r'/api$'), '');

/// Key the session token is stored under.
const String kTokenKey = 'huska_token';
