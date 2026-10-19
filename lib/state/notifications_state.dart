import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/account_api.dart';
import 'auth_state.dart';

/// Unread notification count, refreshed every minute while signed in
/// (the web header polls the same endpoint).
class UnreadNotifier extends Notifier<int> {
  Timer? _timer;

  @override
  int build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen<String?>(authProvider.select((a) => a.user?.id), (prev, next) {
      _restart(next);
    });
    Future.microtask(() => _restart(ref.read(authProvider).user?.id));
    return 0;
  }

  void _restart(String? userId) {
    _timer?.cancel();
    if (userId == null) {
      state = 0;
      return;
    }
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  Future<void> refresh() async {
    if (ref.read(authProvider).user == null) return;
    try {
      final res = await NotificationsApi.mine(limit: 1);
      state = res.unread;
    } catch (_) {}
  }

  void set(int n) => state = n;
}

final unreadProvider = NotifierProvider<UnreadNotifier, int>(UnreadNotifier.new);
