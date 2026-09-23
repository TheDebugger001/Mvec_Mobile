import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (e, handler) {
          final api = DioException(
            requestOptions: e.requestOptions,
            response: e.response,
            type: e.type,
            error: ApiException(_messageFrom(e), statusCode: e.response?.statusCode),
          );
          handler.reject(api);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'mvec_admin_token';

  Dio get dio => _dio;

  static Future<String?> readToken() => _storage.read(key: _tokenKey);
  static Future<void> writeToken(String t) => _storage.write(key: _tokenKey, value: t);
  static Future<void> clearToken() => _storage.delete(key: _tokenKey);

  static String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. Check your connection.';
    }
    if (e.response != null) return 'Request failed (${e.response!.statusCode})';
    return e.message ?? 'Network error';
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final r = await _dio.get(path, queryParameters: query);
    return r.data;
  }

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async {
    final r = await _dio.post(path, data: body, queryParameters: query);
    return r.data;
  }

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) async {
    final r = await _dio.patch(path, data: body, queryParameters: query);
    return r.data;
  }

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query}) async {
    final r = await _dio.put(path, data: body, queryParameters: query);
    return r.data;
  }

  Future<dynamic> delete(String path, {Object? body}) async {
    final r = await _dio.delete(path, data: body);
    return r.data;
  }
}

final apiProvider = Provider<ApiClient>((ref) => ApiClient.instance);

/// A page of list results, normalised across the backend's three envelopes:
/// `{data, meta}`, `{success, data}` and bare `{orders}` / arrays.
class Paged<T> {
  Paged({required this.items, this.total, this.page, this.pages, this.pageSize});

  final List<T> items;
  final int? total;
  final int? page;
  final int? pages;
  final int? pageSize;

  factory Paged.parse(dynamic json, T Function(Map<String, dynamic>) map) {
    List<dynamic> raw = [];
    int? total, page, pages, pageSize;

    if (json is List) {
      raw = json;
    } else if (json is Map) {
      final data = json['data'] ?? json['orders'] ?? json['entries'] ?? json['categories'] ?? json['cases'] ?? json['conversations'] ?? json['notifications'];
      if (data is List) raw = data;
      final meta = json['meta'];
      if (meta is Map) {
        total = _int(meta['total'] ?? meta['count']);
        page = _int(meta['page'] ?? meta['currentPage']);
        pages = _int(meta['pages'] ?? meta['totalPages'] ?? meta['pageCount']);
        pageSize = _int(meta['limit'] ?? meta['pageSize']);
      }
      total ??= _int(json['total']);
      page ??= _int(json['page']);
      pages ??= _int(json['totalPages']);
      if (raw.isEmpty) {
        for (final k in ['items', 'commissions', 'payouts', 'reports', 'reviews', 'rows', 'rules', 'subs']) {
          if (json[k] is List) {
            raw = json[k] as List;
            break;
          }
        }
      }
    }

    return Paged(
      items: raw.map((e) => map(Map<String, dynamic>.from(e as Map))).toList(),
      total: total,
      page: page,
      pages: pages,
      pageSize: pageSize,
    );
  }

  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
}

/// Extracts a single object from common single-item envelopes.
Map<String, dynamic> singleJson(dynamic json, List<String> keys) {
  if (json is Map) {
    for (final k in keys) {
      final v = json[k];
      if (v is Map) return Map<String, dynamic>.from(v);
    }
    return Map<String, dynamic>.from(json);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> listJson(dynamic json, List<String> keys) {
  if (json is List) return json.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (json is Map) {
    for (final k in [...keys, 'data', 'items', 'results']) {
      final v = json[k];
      if (v is List) return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }
  return [];
}