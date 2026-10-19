import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../core/api_client.dart';
import '../models/user.dart';

class AuthState {
  const AuthState({this.user, this.restoring = true, this.notice});

  final AppUser? user;

  /// True while a stored session is being checked on start-up.
  final bool restoring;

  /// Why the person was signed out (expired session, blocked account).
  final String? notice;

  bool get isLoggedIn => user != null;
}

/// Session owner: restores the token on launch, signs in/out, and reacts to the
/// API reporting an expired or blocked session (same flow as the web
/// `AuthContext`).
class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<SessionEvent>? _sub;

  @override
  AuthState build() {
    _sub = Api.instance.sessionEvents.listen((event) {
      state = AuthState(
        restoring: false,
        notice: event == SessionEvent.blocked
            ? 'Your account is blocked or suspended. Contact MVEC support.'
            : 'Your session has ended. Please sign in again.',
      );
    });
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(_restore);
    return const AuthState();
  }

  Future<void> _restore() async {
    final token = await TokenStore.instance.read();
    if (token == null || token.isEmpty) {
      state = const AuthState(restoring: false);
      return;
    }
    try {
      final me = await AuthApi.me();
      state = AuthState(user: me, restoring: false);
    } catch (e) {
      // A 401 already cleared the token; a network failure keeps it so the next
      // launch can try again, but this launch starts signed out.
      if (statusOf(e) == 401) await TokenStore.instance.clear();
      state = const AuthState(restoring: false);
    }
  }

  Future<void> _start(AuthSession s) async {
    await TokenStore.instance.write(s.token);
    state = AuthState(user: s.user, restoring: false);
  }

  Future<AppUser> login(String identity, String password) async {
    final s = await AuthApi.login(identity, password);
    await _start(s);
    return s.user;
  }

  Future<AppUser> register({
    required String fullName,
    required String phone,
    String? email,
    String? gender,
    required String role,
    String? companyName,
    required String password,
  }) async {
    final s = await AuthApi.register(
      fullName: fullName,
      phone: phone,
      email: email,
      gender: gender,
      role: role,
      companyName: companyName,
      password: password,
    );
    await _start(s);
    return s.user;
  }

  /// Starts a session from a code-verified phone (guest checkout / code login).
  Future<AppUser> startSession(AuthSession s) async {
    await _start(s);
    return s.user;
  }

  Future<void> logout() async {
    await TokenStore.instance.clear();
    state = const AuthState(restoring: false);
  }

  Future<AppUser> refresh() async {
    final me = await AuthApi.me();
    state = AuthState(user: me, restoring: false);
    return me;
  }

  void setUser(AppUser user) => state = AuthState(user: user, restoring: false);

  /// Swaps in the fresh token the server sends after a password change.
  Future<void> replaceToken(String token) => TokenStore.instance.write(token);

  void clearNotice() {
    if (state.notice != null) state = AuthState(user: state.user, restoring: state.restoring);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
