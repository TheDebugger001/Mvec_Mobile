/// Rwanda's 5 provinces (incl. Kigali City) and 30 districts.
/// Same list as `Mvec_frontend/src/data/rwandaLocations.js` and the backend.
const Map<String, List<String>> rwandaLocations = {
  'Kigali City': ['Gasabo', 'Kicukiro', 'Nyarugenge'],
  'Northern Province': ['Burera', 'Gakenke', 'Gicumbi', 'Musanze', 'Rulindo'],
  'Southern Province': [
    'Gisagara',
    'Huye',
    'Kamonyi',
    'Muhanga',
    'Nyamagabe',
    'Nyanza',
    'Nyaruguru',
    'Ruhango',
  ],
  'Eastern Province': [
    'Bugesera',
    'Gatsibo',
    'Kayonza',
    'Kirehe',
    'Ngoma',
    'Nyagatare',
    'Rwamagana',
  ],
  'Western Province': [
    'Karongi',
    'Ngororero',
    'Nyabihu',
    'Nyamasheke',
    'Rubavu',
    'Rusizi',
    'Rutsiro',
  ],
};

List<String> get provinces => rwandaLocations.keys.toList();

/// Province and district matching [name] (case-insensitive), if any.
({String province, String district})? findDistrict(String? name) {
  final wanted = (name ?? '').trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final entry in rwandaLocations.entries) {
    for (final d in entry.value) {
      if (d.toLowerCase() == wanted) return (province: entry.key, district: d);
    }
  }
  return null;
}
