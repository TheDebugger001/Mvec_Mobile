@Tags(['contract'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/features/marketplace/presentation/providers/home_provider.dart';

/// Verifies the live API shape the app was written against.
///
/// Everything else in `test/` runs against fakes and stays green whether or not
/// a backend exists, which is exactly why a route or casing mismatch would
/// otherwise reach the UI unnoticed. This suite is the one that can catch it.
///
/// Run it with a backend up:
///
///     flutter test --tags contract
///
/// Without one it skips, so it is safe to leave in the default run. Set
/// `API_BASE_URL` to point somewhere other than the local default.
void main() {
  // The default `flutter test` must stay green whether or not a backend exists,
  // and a backend that is up but missing routes would otherwise fail a run that
  // was never meant to check routes. Opt in explicitly:
  //
  //     CONTRACT=1 flutter test --tags contract
  if (Platform.environment['CONTRACT'] != '1') {
    test('live API contract', () {}, skip: 'Set CONTRACT=1 to check the live API');
    return;
  }

  final baseUrl = Platform.environment['API_BASE_URL'] ?? 'http://localhost:4000/api';

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  /// Sends [method] to [path] and returns the decoded body alongside the status.
  ///
  /// A null status means the server was not reachable at all, which is the one
  /// case worth skipping over: a 404 or 501 is a real answer and means the
  /// route is genuinely missing.
  Future<({int? status, Map<String, dynamic>? body})> call(
    String path, {
    String method = 'GET',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = await client.openUrl(method, uri).timeout(
        const Duration(seconds: 5),
      );
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 5));
      final text = await response.transform(utf8.decoder).join();
      dynamic decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      return (
        status: response.statusCode,
        body: decoded is Map<String, dynamic> ? decoded : null,
      );
    } on Object {
      return (status: null, body: null);
    }
  }

  /// Skips the calling test when nothing is listening on [baseUrl].
  Future<void> requireBackend() async {
    if ((await call('/search/home')).status == null) {
      markTestSkipped('No backend reachable at $baseUrl');
    }
  }

  /// Asserts a route was actually implemented.
  ///
  /// 2xx means it is live. 401 and 403 also mean it exists: the route is there
  /// and the app simply was not authenticated, which is correct behaviour for
  /// an admin surface. 404 and 501 mean the route was never built, and that is
  /// the case worth failing on.
  void expectRouteExists(String path, int? status) {
    expect(
      status,
      isNotNull,
      reason: '$path produced no response',
    );
    expect(
      const {404, 501},
      isNot(contains(status)),
      reason: '$path is not implemented on the backend (HTTP $status)',
    );
  }

  tearDownAll(() => client.close(force: true));

  group('live $baseUrl', () {
    test('GET /search/home answers with a parseable, non-empty feed', () async {
      await requireBackend();

      final response = await call('/search/home');
      expect(
        response.status,
        200,
        reason: 'GET /search/home must exist and be readable',
      );

      // The route answers `{feed: {categories, featuredProducts, topVendors}}`.
      // Assert the shape rather than the contents: an unseeded database is a
      // legitimate empty state, but a renamed section key is exactly the fault
      // this suite exists to catch, and it looks identical from the UI.
      final body = response.body ?? const <String, dynamic>{};
      final feed = body['feed'];
      expect(feed, isA<Map<String, dynamic>>(), reason: 'expected a feed envelope');
      final sections = Map<String, dynamic>.from(feed as Map);
      for (final key in const ['categories', 'featuredProducts', 'topVendors']) {
        expect(
          sections.containsKey(key),
          isTrue,
          reason: 'feed.$key is missing; the section keys no longer match',
        );
        expect(sections[key], isA<List<dynamic>>(), reason: 'feed.$key is not a list');
      }

      // Everything the parsers depend on, checked against whatever data exists.
      final parsed = HomeFeed.fromJson(sections);
      for (final product in [
        ...parsed.products,
        ...parsed.featuredProducts,
        ...parsed.recommendedProducts,
      ]) {
        expect(product.id, greaterThan(0));
        expect(product.name, isNotEmpty, reason: 'product ${product.id} has no name');
        expect(product.price, greaterThanOrEqualTo(0));
      }
      for (final vendor in parsed.featuredVendors) {
        expect(vendor.id, greaterThan(0));
        expect(vendor.name, isNotEmpty, reason: 'vendor ${vendor.id} has no name');
      }
    });

    test('GET /audit-logs answers', () async {
      await requireBackend();
      final response = await call('/audit-logs');
      expectRouteExists('GET /audit-logs', response.status);
    });

    test('GET /supplier-matches answers', () async {
      await requireBackend();
      final response = await call('/supplier-matches');
      expectRouteExists('GET /supplier-matches', response.status);
    });

    test('GET /trust-scores answers', () async {
      await requireBackend();
      final response = await call('/trust-scores');
      expectRouteExists('GET /trust-scores', response.status);
    });

    test('GET /system/settings answers', () async {
      await requireBackend();
      final response = await call('/system/settings');
      expectRouteExists('GET /system/settings', response.status);
    });

    test('GET /recommendation-signals answers', () async {
      await requireBackend();
      final response = await call('/recommendation-signals');
      expectRouteExists('GET /recommendation-signals', response.status);
    });

    test('GET /orders/my-orders is reachable by a shopper', () async {
      await requireBackend();
      final response = await call('/orders/my-orders');

      // The shopper orders tab calls this route. If the backend treats it as
      // admin-only it answers 403, and the tab shows an error instead of the
      // shopper's orders. Surfacing it here keeps the fix a backend route
      // rather than a UI change.
      expect(
        response.status,
        isNot(403),
        reason: 'shopper orders answered 403; check the bearer token is sent',
      );
    });
  });
}