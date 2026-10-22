import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mvec_mobile/widgets/splash_gate.dart';
import 'package:mvec_mobile/core/api_client.dart';
import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A request the app sent.
class Call {
  Call(this.method, this.path, this.body, this.query);
  final String method;
  final String path;
  final dynamic body;
  final Map<String, dynamic> query;
  @override
  String toString() => '$method $path';
}

typedef Handler = (int, Object?) Function(Call call);

/// Stands in for the Ikiguzi backend: answers `/api/*` calls from [routes]
/// (keys look like `GET /products`) and records every call.
class FakeBackend implements HttpClientAdapter {
  FakeBackend(this.routes);
  final Map<String, Handler> routes;
  final List<Call> calls = [];

  Iterable<Call> where(String method, String path) => calls.where((c) => c.method == method && c.path == path);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.path.replaceFirst(RegExp(r'^https?://[^/]+/api'), '');
    dynamic body = options.data;
    if (body is FormData) body = {for (final f in body.fields) f.key: f.value};
    final call = Call(options.method, path, body, options.queryParameters);
    calls.add(call);
    final handler = routes['${options.method} $path'];
    final (status, json) = handler == null ? (404, {'message': 'No fake route for ${options.method} $path'}) : handler(call);
    return ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> product(String id, String name, {num price = 10000, num discount = 0, int stock = 5}) => {
      '_id': id,
      'name': name,
      'price': price,
      'discountPrice': discount,
      'stockQuantity': stock,
      'status': 'ACTIVE',
      'sku': 'SKU-$id',
      'averageRating': 4.5,
      'reviewCount': 3,
      'vendor': {'_id': 'v1', 'companyName': 'Kigali Gadgets'},
      'category': {'name': 'Electronics'},
      'media': {'mainImage': '', 'gallery': []},
    };

Map<String, dynamic> userJson(String role, {String name = 'Aline Uwase'}) => {
      '_id': 'u1',
      'Fullname': name,
      'email': 'aline@mvec.rw',
      'phone': '0788123456',
      'role': role,
      'isOnboarded': true,
    };

/// Default storefront data every test starts from.
Map<String, Handler> baseRoutes() => {
      'GET /products': (_) => (200, {'products': [product('p1', 'Wireless Headphones', price: 50000, discount: 40000), product('p2', 'Phone Case')]}),
      'GET /products/p1': (_) => (200, {'product': product('p1', 'Wireless Headphones', price: 50000, discount: 40000)}),
      'GET /categories': (_) => (200, {'categories': [{'id': 'c1', 'name': 'Electronics', 'slug': 'electronics'}]}),
      'GET /vendors': (_) => (200, {'data': [{'id': 's1', 'userId': 'v1', 'businessName': 'Kigali Gadgets', 'category': 'Electronics', 'verificationStatus': 'VERIFIED'}], 'meta': {'total': 1}}),
      'GET /advertisements': (_) => (200, {'data': []}),
      'GET /reviews/product/p1': (_) => (200, {'reviews': []}),
      'GET /notifications/mine': (_) => (200, {'data': [], 'meta': {'unreadCount': 0}}),
      'GET /cart': (_) => (200, {'cart': {'items': []}}),
      'GET /auth/wishlist': (_) => (200, {'items': []}),
    };

/// Boots the real app on a phone-sized screen with [backend] answering the API.
Future<void> pumpApp(WidgetTester tester, FakeBackend backend, {Size size = const Size(390, 844)}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  // Secure storage has no platform side in tests: keep it in memory.
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final key = (call.arguments as Map?)?['key'] as String?;
      switch (call.method) {
        case 'write':
          store[key!] = (call.arguments as Map)['value'] as String;
          return null;
        case 'read':
          return store[key];
        case 'delete':
          store.remove(key);
          return null;
        default:
          return null;
      }
    },
  );
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), null));
  await TokenStore.instance.clear(); // the token cache outlives a single test
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  Api.instance.dio.httpClientAdapter = backend;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs), splashDurationProvider.overrideWithValue(Duration.zero)],
    child: const MvecApp(),
  ));
  await settle(tester);
}

/// Lets futures, timers and short animations finish (spinners never "settle").
Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
