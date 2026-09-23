import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API base URL used by the app.
///
/// Resolution order:
/// 1. `API_BASE_URL` from `.env` (loaded at startup via `dotenv.load()`),
/// 2. the `--dart-define=API_BASE_URL=...` compile-time override,
/// 3. a localhost fallback for development.
String get kApiBaseUrl {
  try {
    final envUrl = dotenv.maybeGet('API_BASE_URL');
    if (envUrl != null && envUrl.trim().isNotEmpty) return envUrl.trim();
  } catch (_) {
    // dotenv is not loaded (e.g. tests) — fall back to compile-time value.
  }
  return const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:4000/api',
  );
}

const String kAdminEmail = String.fromEnvironment(
  'ADMIN_EMAIL',
  defaultValue: 'admin@gmail.com',
);

const String kAdminPassword = String.fromEnvironment(
  'ADMIN_PASSWORD',
  defaultValue: 'admin!',
);