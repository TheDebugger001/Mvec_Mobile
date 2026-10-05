import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme.dart';
import '../../../../providers/auth_provider.dart';
import 'interest_profile.dart';

/// Per-account record of what someone buys, keyed by user id.
///
/// Personalisation is only offered to accounts: a guest has nobody to tie the
/// history to, and tying it to the device would follow them around a shared
/// handset and leak one person's taste into another's session. Everything here
/// no-ops when [userId] is null.
///
/// The store is local. There is no `/me/interests` endpoint, so this is the
/// client's best model of the account and the shape the server should mirror
/// when it lands.
class InterestStore {
  const InterestStore({required this.userId, required this.profiles});

  final String? userId;

  /// userId -> profile. Only the signed-in entry is ever read, but keeping the
  /// others means signing out and back in does not lose the history.
  final Map<String, InterestProfile> profiles;

  static const empty = InterestStore(userId: null, profiles: {});

  /// This account's profile, or null when there is no session.
  ///
  /// Null is the important part: every consumer treats it as "no
  /// personalisation available" rather than as an empty-but-present profile.
  InterestProfile? get current {
    final id = userId;
    if (id == null) return null;
    return profiles[id] ?? InterestProfile.empty;
  }

  /// Records one observation against the signed-in account.
  ///
  /// Returns the unchanged store for a guest, so callers can fire this from
  /// every interaction without checking who is signed in first.
  InterestStore record({
    required int? categoryId,
    required int? productId,
    required InterestSignal signal,
    DateTime? now,
  }) {
    final id = userId;
    if (id == null) return this;
    final existing = current ?? InterestProfile.empty;
    final updated = existing.record(
      categoryId: categoryId,
      signal: signal,
      productId: productId,
      now: now,
    );
    return InterestStore(
      userId: id,
      profiles: <String, InterestProfile>{...profiles, id: updated},
    );
  }

  /// Marks products as already surfaced so a notification is not repeated.
  InterestStore markSeen(Iterable<int> productIds, {DateTime? now}) {
    final id = userId;
    if (id == null || productIds.isEmpty) return this;
    final current = this.current;
    if (current == null) return this;
    return InterestStore(
      userId: id,
      profiles: <String, InterestProfile>{
        ...profiles,
        id: current.markSeen(productIds),
      },
    );
  }

  static String _key(String userId) => 'mvec.interests.$userId';

  Map<String, String> toStorage() => <String, String>{
    for (final entry in profiles.entries)
      _key(entry.key): jsonEncode(entry.value.toJson()),
  };

  static InterestStore fromStorage({
    String? userId,
    required Map<String, String> raw,
  }) {
    final profiles = <String, InterestProfile>{};
    for (final entry in raw.entries) {
      if (!entry.key.startsWith('mvec.interests.')) continue;
      final id = entry.key.substring('mvec.interests.'.length);
      final profile = InterestProfile.fromJson(_decode(entry.value));
      if (!profile.isEmpty) profiles[id] = profile;
    }
    return InterestStore(userId: userId, profiles: profiles);
  }
}

dynamic _decode(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    // A corrupt or half-written entry must not take the app down; the shopper
    // just starts over with no personalisation.
    return null;
  }
}

class InterestStoreController extends Notifier<InterestStore> {
  @override
  InterestStore build() {
    final user = ref.watch(currentUserProvider);
    final stored = ref.watch(sharedPreferencesProvider);
    final store = InterestStore.fromStorage(
      userId: user?.id,
      raw: _allKeys(stored),
    );
    // The account changed underneath us: keep the profiles, re-point the store.
    return InterestStore(userId: user?.id, profiles: store.profiles);
  }

  static Map<String, String> _allKeys(SharedPreferences? prefs) {
    if (prefs == null) return const <String, String>{};
    final out = <String, String>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.getString(key);
      if (value != null) out[key] = value;
    }
    return out;
  }

  /// Feeds one interaction into the signed-in account's profile.
  void record({
    required int? categoryId,
    required int? productId,
    required InterestSignal signal,
    DateTime? now,
  }) {
    final next = state.record(
      categoryId: categoryId,
      productId: productId,
      signal: signal,
      now: now,
    );
    if (identical(next, state)) return;
    state = next;
    _persist(next);
  }

  void markSeen(Iterable<int> productIds) {
    final next = state.markSeen(productIds);
    if (identical(next, state)) return;
    state = next;
    _persist(next);
  }

  void _persist(InterestStore store) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs == null) return;
    for (final entry in store.toStorage().entries) {
      prefs.setString(entry.key, entry.value);
    }
  }
}

final interestStoreProvider =
    NotifierProvider<InterestStoreController, InterestStore>(
      InterestStoreController.new,
    );

/// This account's interests, or null for a guest.
final myInterestProvider = Provider<InterestProfile?>((ref) {
  return ref.watch(interestStoreProvider).current;
});
