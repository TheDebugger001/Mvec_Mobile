import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/utils.dart';
import '../models/user.dart';

class AuthState {
  const AuthState({this.session, this.loading = false, this.error});
  final AuthSession? session;
  final bool loading;
  final String? error;

  bool get isLoggedIn => session != null;
  bool get isAdmin => session?.user.role == 'super_admin';

  AuthState copyWith({AuthSession? session, bool? loading, String? error, bool clearSession = false, bool clearError = false}) =>
      AuthState(
        session: clearSession ? null : (session ?? this.session),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthState();
  }

  final _api = ApiClient.instance;

  Future<void> _restore() async {
    final token = await ApiClient.readToken();
    if (token == null) return;
    try {
      final me = await _api.get('/auth/me');
      final user = UserRecord.fromJson(singleJson(me, ['user']));
      state = state.copyWith(session: AuthSession(token: token, user: user));
    } catch (_) {
      await ApiClient.clearToken();
    }
  }

  Future<bool> login(String emailOrPhone, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final isEmail = emailOrPhone.contains('@');
      final body = {
        if (isEmail) 'email': emailOrPhone else 'phone': emailOrPhone,
        'password': password,
      };
      final res = await _api.post('/auth/login', body: body);
      final token = res['token'] as String?;
      final user = UserRecord.fromJson(singleJson(res, ['user']));
      if (token == null) throw ApiException('Login failed: no token returned');
      await ApiClient.writeToken(token);
      state = AuthState(session: AuthSession(token: token, user: user));
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: friendlyError(e));
      return false;
    }
  }

  Future<void> logout() async {
    await ApiClient.clearToken();
    state = const AuthState();
  }

  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _api.post('/auth/forgot-password', body: {'email': email});
      state = state.copyWith(loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: friendlyError(e));
      return false;
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final currentUserProvider = Provider<UserRecord?>((ref) => ref.watch(authControllerProvider).session?.user);