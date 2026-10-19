import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';

const compareMax = 4;
const _key = 'mvec_compare';

/// Products picked to compare (up to four), remembered on this device.
class CompareNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final raw = ref.read(sharedPreferencesProvider)?.getStringList(_key) ?? const [];
    return raw.take(compareMax).toList();
  }

  void _save(List<String> ids) {
    state = ids;
    ref.read(sharedPreferencesProvider)?.setStringList(_key, ids);
  }

  ({bool ok, String message}) toggle(String id) {
    if (state.contains(id)) {
      _save(state.where((x) => x != id).toList());
      return (ok: true, message: 'Removed from compare.');
    }
    if (state.length >= compareMax) {
      return (ok: false, message: 'You can compare up to $compareMax products. Remove one first.');
    }
    _save([...state, id]);
    return (ok: true, message: 'Added to compare.');
  }

  void remove(String id) => _save(state.where((x) => x != id).toList());
  void clear() => _save(const []);
}

final compareProvider = NotifierProvider<CompareNotifier, List<String>>(CompareNotifier.new);
