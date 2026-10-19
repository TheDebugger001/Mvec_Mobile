import 'package:intl/intl.dart';

import 'config.dart';

final _rwf = NumberFormat.decimalPattern('en');

/// "12,500 RWF" — same as `money()` in the web app.
String money(dynamic n) {
  final v = num.tryParse('${n ?? 0}') ?? 0;
  return '${_rwf.format(v.round())} RWF';
}

/// "4.3" for a rating, "New" when nobody rated yet.
String ratingLabel(dynamic rating) {
  final v = num.tryParse('${rating ?? 0}') ?? 0;
  return v > 0 ? v.toStringAsFixed(1) : 'New';
}

/// dd/MM/yyyy, or empty for a missing/invalid date.
String formatDate(dynamic value) {
  final d = parseDate(value);
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
}

/// "12 Oct, 14:05".
String formatDateTime(dynamic value) {
  final d = parseDate(value);
  return d == null ? '' : DateFormat('dd MMM, HH:mm').format(d);
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final d = DateTime.tryParse('$value');
  return d?.toLocal();
}

/// "OUT_FOR_DELIVERY" -> "Out for delivery".
String statusLabel(dynamic status) {
  final s = '${status ?? ''}'.toLowerCase().replaceAll('_', ' ').trim();
  if (s.isEmpty) return '';
  return s[0].toUpperCase() + s.substring(1);
}

/// Compact number: 1.2K, 3.4M.
String compact(dynamic n) {
  final v = num.tryParse('${n ?? 0}') ?? 0;
  return NumberFormat.compact().format(v);
}

/// `_id` or `id` of a backend document as a string.
String idOf(dynamic doc) {
  if (doc is Map) return '${doc['id'] ?? doc['_id'] ?? ''}';
  return '${doc ?? ''}';
}

// ─── Images ──────────────────────────────────────────────────────────────────

final _uploaded = RegExp(r'^https?://[^/]+(/uploads/[^?#\s]+)$', caseSensitive: false);

/// Product and avatar uploads are served from the API origin (`/uploads`).
/// Old records may carry an absolute URL on a host that no longer exists, so
/// uploaded files are always re-pointed at the configured origin.
String resolveImageUrl(dynamic value) {
  if (value is! String) return '';
  final image = value.trim();
  if (image.isEmpty) return '';
  if (image.startsWith('data:') || image.startsWith('blob:')) return image;
  if (image.startsWith('//')) return 'https:$image';
  final m = _uploaded.firstMatch(image);
  if (m != null) return '$apiOrigin${m.group(1)}';
  if (RegExp(r'^[a-z][a-z\d+.-]*:', caseSensitive: false).hasMatch(image)) return image;
  return '$apiOrigin/${image.replaceFirst(RegExp(r'^/+'), '')}';
}

// ─── Phones ──────────────────────────────────────────────────────────────────

/// Rwandan mobile numbers: 078/079 (MTN) and 072/073 (Airtel).
bool isRwandanPhone(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^\d]'), '');
  final local = digits.startsWith('250') ? '0${digits.substring(3)}' : digits;
  return RegExp(r'^07[2389]\d{7}$').hasMatch(local);
}

/// "MTN MoMo" / "Airtel Money" / "" from a phone number.
String mobileProvider(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'[^\d]'), '');
  final local = digits.startsWith('250') ? '0${digits.substring(3)}' : digits;
  if (RegExp(r'^07[89]').hasMatch(local)) return 'MTN MoMo';
  if (RegExp(r'^07[23]').hasMatch(local)) return 'Airtel Money';
  return '';
}

bool isEmail(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

/// Reads `m[key]` as a map, or an empty one.
Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Reads a list of maps.
List<Map<String, dynamic>> asMaps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

num numOf(dynamic v, [num fallback = 0]) =>
    v is num ? v : (num.tryParse('${v ?? ''}') ?? fallback);

String strOf(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = '$v';
  return s.isEmpty ? fallback : s;
}
