// Regression tests for FallbackAffiliateService:
//  - the service is backend-first and never silently swaps in local demo data;
//  - if the backend is unavailable, the error is surfaced rather than masked.
//
// Run with: flutter test test/features/affiliate/fallback_affiliate_service_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/core/api_client.dart';
import 'package:mvec_mobile/features/affiliate/data/services/fallback_affiliate_service.dart';

void main() {
  group('FallbackAffiliateService', () {
    test('it stays backend-first and never enters demo mode', () async {
      final svc = FallbackAffiliateService(
        ApiClient.instance,
        forceDemo: false,
      );

      expect(svc.isDemo, isFalse);
      expect(svc.fallbackReason, isNull);
      await expectLater(
        svc.fetchOverview(),
        throwsA(isA<ApiException>()),
      );
    });

    test('a backend outage is surfaced as an API error instead of demo data', () async {
      final svc = FallbackAffiliateService(
        ApiClient.instance,
        forceDemo: false,
      );

      await expectLater(
        svc.fetchLinks(),
        throwsA(isA<ApiException>()),
      );
      expect(svc.isDemo, isFalse);
      expect(svc.fallbackReason, isNull);
    });
  });
}