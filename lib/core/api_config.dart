import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API base URL used by the app.
///
/// Resolution order (highest priority first):
/// 1. `--dart-define=API_BASE_URL=...` — wins so a build can target a
///    different host (e.g. `10.0.2.2` for the Android emulator) without
///    editing `.env`.
/// 2. `API_BASE_URL` from `.env` (loaded at startup via `dotenv.load()`).
/// 3. a localhost fallback for development.
String get kApiBaseUrl {
  // A compile-time define must beat the checked-in `.env`, otherwise
  // `flutter run --dart-define=API_BASE_URL=...` is silently ignored.
  const defined = String.fromEnvironment('API_BASE_URL');
  if (defined.trim().isNotEmpty) return defined.trim();

  try {
    final envUrl = dotenv.maybeGet('API_BASE_URL');
    if (envUrl != null && envUrl.trim().isNotEmpty) return envUrl.trim();
  } catch (_) {
    // dotenv is not loaded (e.g. tests) — fall back to the default below.
  }
  return 'http://localhost:4000/api';
}

/// The admin credentials the login screen offers to prefill during development.
///
/// Deliberately empty by default so a production build ships no working
/// credential in the binary. Supply them per build with
/// `--dart-define=ADMIN_EMAIL=... --dart-define=ADMIN_PASSWORD=...`, or leave
/// them out and let the autofill button do nothing.
const String kAdminEmail = String.fromEnvironment('ADMIN_EMAIL');

const String kAdminPassword = String.fromEnvironment('ADMIN_PASSWORD');