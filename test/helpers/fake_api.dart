// A tiny in-memory HTTP transport for tests.
//
// [ApiClient] wraps a `Dio`, and `Dio` lets the transport be swapped out. This
// helper installs an adapter that answers requests from a routing table instead
// of the network, so the shipped `Api*Service` classes can be exercised for
// real — the paths they request, the query they send, and how they parse and
// map errors — without a backend or an extra mocking dependency.
//
// Usage:
//   final api = fakeApi([
//     FakeRoute('GET', '/vendor/orders', body: {'data': {'orders': []}}),
//   ]);
//   addTearDown(restoreApiTransport);
//   final service = ApiVendorOrderService(api.client);
//
// A route that is not registered answers 404, so an unexpected request shows up
// as a failing assertion rather than a silent pass.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/core/api_client.dart';

/// One canned response, matched on method + path.
class FakeRoute {
  FakeRoute(this.method, this.path, {this.body, this.status = 200})
    : assert(method == method.toUpperCase());

  final String method;
  final String path;

  /// Decoded and re-encoded as JSON. `null` sends an empty object body.
  final Object? body;
  final int status;
}

/// A request the fake transport saw, for asserting on what a service sent.
class RecordedRequest {
  RecordedRequest(this.method, this.path, {this.query = const {}});

  final String method;
  final String path;
  final Map<String, dynamic> query;

  @override
  String toString() => '$method $path${query.isEmpty ? '' : ' $query'}';
}

/// A fake transport plus the client it is installed on.
///
/// `recorded` lists every request that reached it, so a test can assert on the
/// path, method and query a service actually sent.
class FakeTransport {
  FakeTransport(this.client, this.adapter);

  final ApiClient client;
  final FakeAdapter adapter;

  /// Every request that reached the transport, in order.
  List<RecordedRequest> get recorded => adapter.recorded;
}

/// Installs a fake transport onto [ApiClient.instance].
///
/// [ApiClient] attaches a bearer token on every request by reading
/// `FlutterSecureStorage`, which is a platform channel and unavailable in a plain
/// unit test — the read would fail and reject the request before it ever reached
/// the transport. The channel is stubbed to "no token" here so the tests exercise
/// the real request path.
FakeTransport fakeApi(List<FakeRoute> routes) {
  _stubSecureStorage();
  final api = ApiClient.instance;
  _originalAdapter ??= api.dio.httpClientAdapter;
  final adapter = FakeAdapter(routes);
  api.dio.httpClientAdapter = adapter;
  return FakeTransport(api, adapter);
}

const _secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _stubSecureStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        // A signed-out client simply has nothing to attach.
        return null;
      });
}

/// Removes the secure-storage stub and restores the default transport.
void restoreApiTransport() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  final original = _originalAdapter;
  if (original != null) {
    ApiClient.instance.dio.httpClientAdapter = original;
    _originalAdapter = null;
  }
}

HttpClientAdapter? _originalAdapter;

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  final List<FakeRoute> routes;

  /// Every request that reached the transport, in order.
  final List<RecordedRequest> recorded = <RecordedRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method.toUpperCase();
    final path = options.path.startsWith('/')
        ? options.path
        : '/${options.path}';
    recorded.add(
      RecordedRequest(method, path, query: Map<String, dynamic>.from(options.queryParameters)),
    );

    final match = routes.where(
      (r) => r.method == method && r.path == path,
    );
    if (match.isEmpty) {
      return ResponseBody.fromString(
        jsonEncode({'message': 'No fake route registered for $method $path'}),
        404,
        headers: _jsonHeaders,
      );
    }

    return ResponseBody.fromString(
      jsonEncode(match.first.body ?? const <String, dynamic>{}),
      match.first.status,
      headers: _jsonHeaders,
    );
  }

  @override
  void close({bool force = false}) {}
}

const _jsonHeaders = <String, List<String>>{
  Headers.contentTypeHeader: [Headers.jsonContentType],
};