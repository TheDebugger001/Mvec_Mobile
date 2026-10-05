/// Lenient JSON field access for backend payloads.
///
/// The app cannot know which casing a given endpoint uses, and guessing wrong is
/// not loud: the request succeeds and the field simply renders blank. Rather
/// than hand-listing every alias in every row mapper, callers name the field and
/// this resolves it across the spellings a Node/Express or Laravel backend
/// realistically sends.
///
/// [field] takes the names in order of preference, so the canonical spelling
/// stays first and the fallback only exists for the shapes we have not seen
/// shipped yet.
library;

/// The first present, non-null value among [names].
///
/// Returns null when the payload carries none of them, which every typed reader
/// here turns into its own "absent" value (a dash, a zero, false).
Object? field(Map<String, dynamic> json, List<String> names) {
  for (final name in names) {
    final value = json[name];
    if (value != null) return value;
  }
  return null;
}

String? stringField(Map<String, dynamic> json, List<String> names) {
  for (final name in names) {
    final value = json[name];
    if (value == null) continue;
    // An empty string means "not sent", not "sent as blank": a row whose
    // optional field arrived empty must still resolve to the later alias.
    if (value is String && value.isEmpty) continue;
    return value.toString();
  }
  return null;
}

num? numField(Map<String, dynamic> json, List<String> names) {
  final value = field(json, names);
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

int? intField(Map<String, dynamic> json, List<String> names) {
  final value = numField(json, names);
  return value?.round();
}

bool boolField(Map<String, dynamic> json, List<String> names) {
  final value = field(json, names);
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalised = value.toLowerCase();
    return normalised == 'true' || normalised == '1' || normalised == 'yes';
  }
  return false;
}

/// [stringField] with a dash for absent values, for table cells.
String cellText(Map<String, dynamic> json, List<String> names) =>
    stringField(json, names) ?? '—';

/// [intField] with a zero for absent values.
int cellInt(Map<String, dynamic> json, List<String> names) =>
    intField(json, names) ?? 0;

/// The snake_case spelling of [name], for passing alongside the camelCase one.
///
/// `refundRate` -> `['refundRate', 'refund_rate']`
List<String> spellings(String name) => <String>[
  name,
  _snake(name),
];

List<String> spellingsOf(String name, List<String> extra) =>
    <String>[...spellings(name), ...extra];

String _snake(String name) => name.replaceAllMapped(
  RegExp('[A-Z]'),
  (match) => '_${match.group(0)!.toLowerCase()}',
);