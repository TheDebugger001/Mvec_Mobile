import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// A failed API call, with a message a person can act on.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code, this.data});

  final String message;
  final int? statusCode;

  /// Machine code from the server body (e.g. `ACCOUNT_BLOCKED`).
  final String? code;
  final dynamic data;

  @override
  String toString() => message;
}

/// The bearer token, kept in platform-secure storage and mirrored in memory.
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  static const _storage = FlutterSecureStorage();
  String? _cached;
  bool _loaded = false;

  Future<String?> read() async {
    if (_loaded) return _cached;
    try {
      _cached = await _storage.read(key: kTokenKey);
    } catch (_) {
      // Secure storage is unavailable (some desktop/test hosts): in-memory only.
    }
    _loaded = true;
    return _cached;
  }

  Future<void> write(String token) async {
    _cached = token;
    _loaded = true;
    try {
      await _storage.write(key: kTokenKey, value: token);
    } catch (_) {}
  }

  Future<void> clear() async {
    _cached = null;
    _loaded = true;
    try {
      await _storage.delete(key: kTokenKey);
    } catch (_) {}
  }
}

/// Fired when the server says the session is over (401) or the account was
/// blocked, so the app can sign out and send the person to log in.
enum SessionEvent { expired, blocked }

/// Thin wrapper over Dio that talks to the Ikiguzi REST API.
///
/// Mirrors the web client (`Mvec_frontend/src/API/client.jsx`): same base URL
/// rules, `Authorization: Bearer <token>`, and the same plain-language error
/// messages.
class Api {
  Api._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStore.instance.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          final status = e.response?.statusCode;
          final data = e.response?.data;
          final blocked =
              status == 403 && data is Map && data['code'] == 'ACCOUNT_BLOCKED';
          final hadToken = (await TokenStore.instance.read())?.isNotEmpty ?? false;
          if ((status == 401 || blocked) && hadToken) {
            await TokenStore.instance.clear();
            _events.add(blocked ? SessionEvent.blocked : SessionEvent.expired);
          }
          handler.next(e);
        },
      ),
    );
  }

  static final Api instance = Api._();
  late final Dio _dio;
  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get sessionEvents => _events.stream;
  Dio get dio => _dio;

  /// Base URL the client was built with (for diagnostics).
  String get baseUrl => _dio.options.baseUrl;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _run(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _run(() => _dio.post(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> put(String path, {Object? body}) =>
      _run(() => _dio.put(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _run(() => _dio.patch(path, data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _run(() => _dio.delete(path, data: body));

  /// Multipart upload ([FormData] sets its own content type and boundary).
  Future<dynamic> upload(String path, FormData form) =>
      _run(() => _dio.post(path, data: form));

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.isEmpty) return;
      out[k] = v;
    });
    return out;
  }

  Future<dynamic> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      throw describeError(e);
    }
  }
}

/// Turns a transport failure into an [ApiException] the UI can show as is.
/// (Same rules as `extractErrorMessage` in the web client.)
ApiException describeError(DioException e, {String? fallback}) {
  final res = e.response;
  final data = res?.data;
  final status = res?.statusCode;

  String serverMessage = '';
  String? code;
  if (data is String && data.length < 300 && !data.trim().startsWith('<')) {
    serverMessage = data;
  } else if (data is Map) {
    code = data['code']?.toString();
    final m = data['message'];
    final err = data['error'];
    if (m is String && m.isNotEmpty) {
      serverMessage = m;
    } else if (err is Map && err['message'] is String) {
      serverMessage = err['message'] as String;
    } else if (err is String) {
      serverMessage = err;
    } else if (data['errors'] is List) {
      serverMessage = (data['errors'] as List)
          .map((x) => x is Map ? (x['msg'] ?? x['message'] ?? '') : x)
          .where((x) => x.toString().isNotEmpty)
          .join(' ');
    }
  }

  if (res == null) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiException(
        'The server took too long to answer. Check your connection and try again; if you were paying, check My orders before paying again.',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown) {
      return ApiException(
        "We can't reach MVEC right now. Check your internet connection and try again in a moment.",
      );
    }
    return ApiException(fallback ?? e.message ?? 'Something went wrong. Please try again.');
  }

  String message;
  switch (status) {
    case 401:
      message = serverMessage.isEmpty ||
              RegExp(r'not authori[sz]ed|token|session', caseSensitive: false)
                  .hasMatch(serverMessage)
          ? 'Your session has ended. Please sign in again.'
          : serverMessage;
      break;
    case 403:
      message = serverMessage.isNotEmpty
          ? serverMessage
          : "Your account isn't allowed to do this.";
      break;
    case 404:
      message = serverMessage.isNotEmpty
          ? serverMessage
          : "We couldn't find what you were looking for. It may have been removed.";
      break;
    case 413:
      message = 'That file is too large. Choose a smaller one and try again.';
      break;
    case 429:
      message = serverMessage.isNotEmpty
          ? serverMessage
          : 'Too many attempts. Wait a minute and try again.';
      break;
    default:
      if ((status ?? 0) >= 500) {
        final generic = serverMessage.isEmpty ||
            RegExp(r'^(internal )?server error$', caseSensitive: false)
                .hasMatch(serverMessage);
        message = generic
            ? (fallback ??
                'Something went wrong on our side, not yours. Please try again in a moment; if it keeps happening, contact MVEC support.')
            : serverMessage;
        final ref = data is Map ? data['reference']?.toString() : null;
        if (ref != null && ref.isNotEmpty && !message.contains(ref)) {
          message = '${message.replaceFirst(RegExp(r'\.$'), '')} (reference $ref).';
        }
      } else {
        message = serverMessage.isNotEmpty
            ? serverMessage
            : (fallback ?? 'Something went wrong. Please try again.');
      }
  }
  return ApiException(message, statusCode: status, code: code, data: data);
}

/// Message for any thrown object, for showing in the UI.
String errorText(Object error, [String? fallback]) {
  if (error is ApiException) return error.message;
  if (error is DioException) return describeError(error, fallback: fallback).message;
  if (kDebugMode) debugPrint('Unexpected error: $error');
  return fallback ?? 'Something went wrong. Please try again.';
}

/// HTTP status behind a failure, or null when the request never reached the server.
int? statusOf(Object error) => error is ApiException ? error.statusCode : null;
