import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/upload.dart';
import '../models/user.dart';

/// A token plus the account it belongs to.
class AuthSession {
  const AuthSession(this.token, this.user);
  final String token;
  final AppUser user;
}

AuthSession _session(dynamic data) {
  final m = asMap(data);
  final token = strOf(m['token']);
  if (token.isEmpty) throw ApiException('Sign-in failed: the server sent no token.');
  return AuthSession(token, AppUser.fromJson(asMap(m['user'])));
}

/// `/api/auth/*` — same calls as `Mvec_frontend/src/API/auth.jsx`.
class AuthApi {
  AuthApi._();
  static final _api = Api.instance;

  static Future<AuthSession> register({
    required String fullName,
    required String phone,
    String? email,
    String? gender,
    required String role,
    String? companyName,
    required String password,
  }) async {
    final res = await _api.post('/auth/register', body: {
      'Fullname': fullName,
      if (email != null && email.isNotEmpty) 'email': email,
      'phone': phone,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
      'role': role,
      if (companyName != null && companyName.isNotEmpty) 'companyName': companyName,
      'password': password,
    });
    return _session(res);
  }

  /// Email or phone plus password.
  static Future<AuthSession> login(String identity, String password) async {
    final isEmail = identity.contains('@');
    final res = await _api.post('/auth/login', body: {
      if (isEmail) 'email': identity else 'phone': identity,
      'password': password,
    });
    return _session(res);
  }

  /// Sends a one-time code by text message and, for a new guest, to the email
  /// they gave (guest checkout / code login). The reply's `message` says where.
  static Future<Map<String, dynamic>> guestSendCode(String phone, {String email = ''}) async =>
      asMap(await _api.post('/auth/guest/send-code', body: {'phone': phone, if (email.trim().isNotEmpty) 'email': email.trim()}));

  static Future<AuthSession> guestVerify({
    required String phone,
    required String code,
    String? fullName,
    String? email,
  }) async {
    final res = await _api.post('/auth/guest/verify', body: {
      'phone': phone,
      'code': code,
      if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
      if (email != null && email.isNotEmpty) 'email': email,
    });
    return _session(res);
  }

  static Future<AppUser> me() async {
    final res = await _api.get('/auth/me');
    return AppUser.fromJson(asMap(asMap(res)['user']));
  }

  static Future<AppUser> updateProfile({String? fullName, String? email, String? gender}) async {
    final res = await _api.patch('/auth/me', body: {
      if (fullName != null) 'Fullname': fullName,
      if (email != null) 'email': email,
      if (gender != null) 'gender': gender,
    });
    return AppUser.fromJson(asMap(asMap(res)['user']));
  }

  /// Changing the password signs out other sessions; the server returns a
  /// fresh token for this one.
  static Future<String?> changePassword(String current, String next) async {
    final res = await _api.post('/auth/change-password', body: {
      'currentPassword': current,
      'newPassword': next,
    });
    final token = asMap(res)['token'];
    return token is String && token.isNotEmpty ? token : null;
  }

  /// Portal account settings (name, phone, preferences).
  static Future<Map<String, dynamic>> updateAccount(Map<String, dynamic> payload) async =>
      asMap(await _api.patch('/auth/profile', body: payload));

  static Future<String> uploadAvatar(XFile file) async {
    final part = await imagePart(file);
    final res = await _api.upload('/uploads/avatar', FormData.fromMap({'avatar': part}));
    return strOf(asMap(res)['avatarUrl']);
  }

  static Future<void> removeAvatar() async => _api.delete('/auth/avatar');

  static Future<void> logoutAll() async => _api.post('/auth/logout-all');

  static Future<Map<String, dynamic>> forgotPassword(String identity) async {
    final isEmail = identity.contains('@');
    return asMap(await _api.post('/auth/forgot-password',
        body: {if (isEmail) 'email': identity.trim() else 'phone': identity.trim()}));
  }

  static Future<String> verifyResetOtp(String identity, String code) async {
    final isEmail = identity.contains('@');
    final res = await _api.post('/auth/verify-reset-otp', body: {
      if (isEmail) 'email': identity.trim() else 'phone': identity.trim(),
      'code': code,
    });
    return strOf(asMap(res)['resetToken']);
  }

  static Future<void> resetPassword(String resetToken, String newPassword) async =>
      _api.post('/auth/reset-password', body: {'resetToken': resetToken, 'newPassword': newPassword});

  // ─── Saved addresses ───────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> addresses() async =>
      asMaps(asMap(await _api.get('/auth/addresses'))['addresses']);

  static Future<void> addAddress(Map<String, dynamic> payload) async =>
      _api.post('/auth/addresses', body: payload);

  static Future<void> updateAddress(String id, Map<String, dynamic> payload) async =>
      _api.put('/auth/addresses/$id', body: payload);

  static Future<void> removeAddress(String id) async => _api.delete('/auth/addresses/$id');

  // ─── Wishlist ──────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> wishlist() async =>
      asMaps(asMap(await _api.get('/auth/wishlist'))['items']);

  static Future<List<Map<String, dynamic>>> wishlistAdd(List<String> ids) async =>
      asMaps(asMap(await _api.post('/auth/wishlist', body: {'productIds': ids}))['items']);

  static Future<List<Map<String, dynamic>>> wishlistRemove(String id) async =>
      asMaps(asMap(await _api.delete('/auth/wishlist/$id'))['items']);
}
