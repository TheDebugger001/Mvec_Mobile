// Regression tests for FallbackAffiliateService:
//  - with the API skipped, the empty adapter answers immediately, so the module
//    renders without a backend and without waiting on connection timeouts;
//  - once degraded the empty adapter stays in use for the rest of the session.
//
// Run with: flutter test test/features/affiliate/fallback_affiliate_service_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/core/api_client.dart';
import 'package:mvec_mobile/features/affiliate/data/models/affiliate_marketing.dart';
import 'package:mvec_mobile/features/affiliate/data/services/empty_affiliate_service.dart';
import 'package:mvec_mobile/features/affiliate/data/services/fallback_affiliate_service.dart';

class _CountingEmptyService extends EmptyAffiliateService {
  int overviewCalls = 0;

  @override
  Future<AffiliateOverview> fetchOverview() {
    overviewCalls++;
    return super.fetchOverview();
  }
}

void main() {
  group('FallbackAffiliateService', () {
    test('the empty adapter answers immediately, never touching the API', () async {
      final empty = _CountingEmptyService();
      final svc = FallbackAffiliateService(
        ApiClient.instance,
        fallback: empty,
        forceEmpty: true,
      );

      final overview = await svc.fetchOverview();

      expect(overview, isA<AffiliateOverview>());
      // No bundled figures ship any more: the overview is zeroed out.
      expect(overview.clicks, 0);
      expect(overview.registrations, 0);
      expect(overview.conversions, 0);
      expect(overview.activeLinks, 0);
      expect(empty.overviewCalls, 1);
      expect(svc.isDemo, isFalse);
      expect(svc.fallbackReason, isNotNull);
    });

    test('degradation stays sticky once the empty adapter is active', () async {
      final empty = _CountingEmptyService();
      final svc = FallbackAffiliateService(
        ApiClient.instance,
        fallback: empty,
        forceEmpty: true,
      );

      await svc.fetchOverview();
      await svc.fetchOverview();
      await svc.fetchOverview();

      // Every request is served from the empty adapter; the API is never hit.
      expect(empty.overviewCalls, 3);
    });

    test('isDemo stays false and no reason is recorded while still live', () {
      final svc = FallbackAffiliateService(
        ApiClient.instance,
        fallback: _CountingEmptyService(),
        forceEmpty: false,
      );

      expect(svc.isDemo, isFalse);
      expect(svc.fallbackReason, isNull);
    });
  });

  group('EmptyAffiliateService', () {
    test('reads return empty collections and zeroed metrics, not errors', () async {
      final svc = EmptyAffiliateService();

      expect(await svc.fetchLinks(), isEmpty);
      expect(await svc.fetchCampaigns(), isEmpty);
      expect(await svc.fetchPayouts(), isEmpty);
      expect(await svc.fetchCommissions(), isEmpty);
      expect(await svc.fetchNotifications(), isEmpty);
      expect((await svc.fetchOverview()).clicks, 0);
      expect((await svc.fetchProfile()).fullName, isNull);
    });

    test('writes are refused instead of silently reporting success', () async {
      final svc = EmptyAffiliateService();

      expect(
        () => svc.deleteLink('link-1'),
        throwsA(isA<Exception>()),
      );
      expect(
        () => svc.requestPayout(
          amount: 1000,
          paymentMethod: 'bank',
          accountName: 'Test',
          phoneNumber: '+250788000000',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('isDemo is always false — no bundled dataset is served', () {
      expect(EmptyAffiliateService().isDemo, isFalse);
    });
  });
}