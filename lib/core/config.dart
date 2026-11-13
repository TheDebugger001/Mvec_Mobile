import 'package:flutter/foundation.dart';

/// Where the Ikiguzi backend lives (the `/api` root).
///
/// Set at build time with `--dart-define=API_BASE_URL=...`; otherwise
/// `http://localhost:4000/api`. Nothing secret is built into the app.
///
/// `localhost` means "this device" on a phone. On the Android emulator the
/// host machine is `10.0.2.2`, so a localhost URL is rewritten for Android
/// automatically; on a real device set a LAN IP or the hosted URL.
String get apiBaseUrl {
  const defined = String.fromEnvironment('API_BASE_URL');
  var url = defined.trim();
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

/// Where the Ikiguzi website lives, for links people share (payment links,
/// affiliate links). `--dart-define=WEB_URL=...`; otherwise the local web
/// dev server next to the API.
String get webOrigin {
  const defined = String.fromEnvironment('WEB_URL');
  var url = defined.trim();
  if (url.isEmpty) url = apiOrigin.replaceFirst(RegExp(r':4000$'), ':5173');
  return url.replaceAll(RegExp(r'/+$'), '');
}
