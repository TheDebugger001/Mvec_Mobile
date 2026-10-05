// Covers the supplier "Finance & Insights" module: that the shipped
// services derive their figures rather than shipping a bundled dataset, that a
// payout is validated against the balance the summary shows, and that the
// screens render from whatever the service returns.
//
// The fixture service lives in test/helpers so it cannot ship; the API and empty
// adapters are exercised over a fake transport.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/core/utils.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_finance.dart';
import 'package:mvec_mobile/features/supplier/models/supplier_insights.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_analytics_screen.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_payments_screen.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_reviews_screen.dart';
import 'package:mvec_mobile/features/supplier/screens/supplier_transactions_screen.dart';
import 'package:mvec_mobile/features/supplier/services/empty_supplier_finance_service.dart';
import 'package:mvec_mobile/features/supplier/services/supplier_finance_service.dart';
import 'package:mvec_mobile/features/supplier/supplier_dependencies.dart';

import 'helpers/fake_api.dart';
import 'helpers/fake_supplier_finance.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  tearDown(restoreApiTransport);

  group('the empty adapter', () {
    test('reports zeroed balances and empty collections, never an error', () async {
      final service = EmptySupplierFinanceService();

      final summary = await service.summary();
      expect(summary.grossSales, 0);
      expect(summary.netEarnings, 0);
      expect(summary.isConsistent, isTrue);
      expect(await service.ledger(), isEmpty);
      expect(await service.payouts(), isEmpty);
      expect(await service.reviews(), isEmpty);
      expect((await service.analytics(SupplierReportRange.last30Days)).orderCount, 0);
    });

    test('isDemo stays false and writes are refused', () async {
      final service = EmptySupplierFinanceService();

      expect(service.isDemo, isFalse);
      expect(
        () => service.requestPayout(
          amount: 100000,
          method: SupplierPayoutMethod.mtnMomo,
          destination: '+250788000001',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ApiSupplierFinanceService', () {
    test('requests the token-scoped routes and maps the summary', () async {
      final api = fakeApi([
        FakeRoute('GET', '/suppliers/me/finance/summary', body: {
          'summary': {
            'grossSales': 1000000,
            'commission': 50000,
            'netEarnings': 950000,
            'availablePayout': 400000,
          },
        }),
      ]);

      final summary = await ApiSupplierFinanceService(api.client).summary();

      expect(api.recorded.single.path, '/suppliers/me/finance/summary');
      expect(summary.isConsistent, isTrue);
      expect(summary.availablePayout, 400000);
    });

    test('no supplier id is ever sent — the token identifies the caller', () async {
      final api = fakeApi([
        FakeRoute('GET', '/suppliers/me/finance/ledger', body: {'entries': <dynamic>[]}),
      ]);

      await ApiSupplierFinanceService(api.client).ledger();

      final sent = api.recorded.single;
      expect(sent.path, '/suppliers/me/finance/ledger');
      // The caller is identified by the bearer token, so the route carries no
      // supplier id in the path.
      expect(sent.path, matches(RegExp(r'^/suppliers/me/')));
      expect(sent.query.keys, isNot(contains('supplierId')));
    });

    test('a ledger kind filter is sent as a query parameter', () async {
      final api = fakeApi([
        FakeRoute('GET', '/suppliers/me/finance/ledger', body: {'entries': <dynamic>[]}),
      ]);

      await ApiSupplierFinanceService(api.client).ledger(
        kind: SupplierLedgerKind.payout,
      );

      expect(api.recorded.single.query['kind'], 'PAYOUT');
    });

    test('the analytics range is sent as a query parameter', () async {
      final api = fakeApi([
        FakeRoute('GET', '/suppliers/me/finance/analytics', body: {
          'analytics': {'orderCount': 12, 'grossSales': 500000},
        }),
      ]);

      final snapshot = await ApiSupplierFinanceService(api.client).analytics(
        SupplierReportRange.last3Months,
      );

      expect(api.recorded.single.query['range'], '3m');
      expect(snapshot.orderCount, 12);
    });
  });

  group('the finance figures reconcile with the ledger they come from', () {
    test('net equals gross minus commission on every card', () async {
      final service = seededFinance();
      final summary = await service.summary();

      expect(summary.isConsistent, isTrue);
    });

    test('the supplier can withdraw something on first open', () async {
      final service = seededFinance();
      final summary = await service.summary();

      expect(summary.availablePayout, greaterThan(kMinSupplierPayoutAmount));
      expect(summary.series, isNotEmpty);
    });

    test('every withdrawal appears on the ledger and the payout list', () async {
      final service = seededFinance();
      final request = await service.requestPayout(
        amount: 100000,
        method: SupplierPayoutMethod.mtnMomo,
        destination: '+250788000001',
      );

      final ledger = await service.ledger();
      expect(
        ledger.any((e) => e.kind == SupplierLedgerKind.payout && e.amount == request.amount),
        isTrue,
      );
      expect((await service.payouts()).first.id, request.id);
    });

    test(
      'a payout request is validated against the available balance',
      () async {
        final service = seededFinance();
        final before = await service.summary();

        // Below the platform minimum.
        await expectLater(
          service.requestPayout(
            amount: 1000,
            method: SupplierPayoutMethod.mtnMomo,
            destination: '+250788000001',
          ),
          throwsA(isA<Exception>()),
        );

        // No destination on file.
        await expectLater(
          service.requestPayout(
            amount: 500000,
            method: SupplierPayoutMethod.mtnMomo,
            destination: '   ',
          ),
          throwsA(isA<Exception>()),
        );

        // More than the supplier has cleared.
        await expectLater(
          service.requestPayout(
            amount: before.availablePayout + 1,
            method: SupplierPayoutMethod.bankTransfer,
            destination: 'Equity bank account',
          ),
          throwsA(isA<Exception>()),
        );

        final request = await service.requestPayout(
          amount: 50000,
          method: SupplierPayoutMethod.mtnMomo,
          destination: '+250 788 000 001',
          note: 'Weekly settlement',
        );
        expect(request.isPending, isTrue);

        final after = await service.summary();
        expect(after.availablePayout, before.availablePayout - 50000);
        expect(after.pendingPayouts, before.pendingPayouts + 50000);

        // The withdrawal shows up on both the ledger and the payout list, newest
        // first, so the pages stay in step with each other.
        final ledger = await service.ledger(limit: 5);
        expect(ledger.first.kind, SupplierLedgerKind.payout);
        expect((await service.payouts()).first.id, request.id);
      },
    );

    test('analytics reports a distinct total for every range', () async {
      final service = seededFinance();

      final month = await service.analytics(SupplierReportRange.last30Days);
      final quarter = await service.analytics(SupplierReportRange.last3Months);
      final year = await service.analytics(SupplierReportRange.lastYear);

      expect(month.orderCount, greaterThan(0));
      expect(quarter.orderCount, greaterThan(month.orderCount));
      expect(year.orderCount, greaterThan(quarter.orderCount));

      // A wider window can never bill less money.
      expect(quarter.grossSales, greaterThan(month.grossSales));
      expect(year.grossSales, greaterThan(quarter.grossSales));

      expect(month.unitsSold, greaterThan(0));
      expect(month.averageOrderValue, greaterThan(0));
      expect(month.series, isNotEmpty);
      expect(month.categories, isNotEmpty);
      expect(month.topProducts, isNotEmpty);
      // The category shares must add up to the whole, not overflow it.
      final share = month.categories.fold<num>(0, (sum, c) => sum + c.share);
      expect(share, closeTo(1, 0.02));
    });

    test('the review summary is derived from the reviews themselves', () async {
      final service = seededFinance();
      final reviews = await service.reviews();
      final summary = SupplierReviewSummary.fromReviews(reviews);

      expect(reviews, isNotEmpty);
      expect(summary.total, reviews.length);
      expect(summary.distribution.fold<int>(0, (a, b) => a + b), reviews.length);
      expect(summary.average, greaterThan(4));
      expect(summary.average, lessThanOrEqualTo(5));
      expect(summary.percentFor(5), closeTo(summary.distribution[0] / reviews.length * 100, .01));
    });
  });

  group('supplier finance screens', () {
    Widget wrap(Widget child, FakeSupplierFinanceService service) =>
        ProviderScope(
          overrides: [
            supplierFinanceModuleProvider.overrideWith((ref) => service),
          ],
          child: MaterialApp(
            theme: lightAppTheme,
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );

    /// The scope the screen under test is running in.
    ///
    /// Widget tests read the data back through the providers rather than
    /// awaiting the service directly: inside `testWidgets` a `Future.delayed`
    /// only completes when the fake clock is pumped, so awaiting one outside a
    /// `pump` would hang until the test times out.
    ProviderContainer containerOf(
      WidgetTester tester,
      FakeSupplierFinanceService service,
    ) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

    testWidgets('payments page shows the withdrawable balance', (tester) async {
      final service = seededFinance();
      await tester.pumpWidget(wrap(const SupplierPaymentsScreen(), service));
      await tester.pumpAndSettle();

      expect(find.text('Earnings & payouts'), findsOneWidget);
      expect(find.text('Available to withdraw'), findsOneWidget);
      expect(find.text('Request payout'), findsOneWidget);
      expect(find.text('Payout requests'), findsOneWidget);
    });

    testWidgets('the payout form rejects an amount above the balance', (
      tester,
    ) async {
      final service = seededFinance();
      await tester.pumpWidget(wrap(const SupplierPaymentsScreen(), service));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Request payout'));
      await tester.pumpAndSettle();

      expect(find.text('Request a payout'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (RWF)'),
        '99999999999',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit request'));
      await tester.pumpAndSettle();

      expect(find.text('Amount exceeds your available balance'), findsOneWidget);
    });

    testWidgets('a valid request posts and lands in the payout list', (
      tester,
    ) async {
      final service = seededFinance();
      await tester.pumpWidget(wrap(const SupplierPaymentsScreen(), service));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Request payout'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (RWF)'),
        '250000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile Money phone number'),
        '+250 788 000 001',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit request'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Payout request submitted'), findsOneWidget);

      // Read through the widget's own provider rather than awaiting the service
      // here: inside testWidgets a Future.delayed only fires when the clock is
      // pumped, so awaiting it directly would never return.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SupplierPaymentsScreen)),
      );
      final requests = await container.read(supplierPayoutsProvider.future);
      expect(requests.first.amount, 250000);
      expect(requests.first.destination, '+250 788 000 001');
    });

    testWidgets('transactions page filters the ledger by kind', (tester) async {
      final service = seededFinance();
      await tester.pumpWidget(wrap(const SupplierTransactionsScreen(), service));
      await tester.pumpAndSettle();

      expect(find.text('Money ledger'), findsOneWidget);
      expect(find.text('Ledger totals'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Withdrawal'));
      await tester.pumpAndSettle();

      final ledger = await containerOf(tester, service).read(supplierLedgerProvider.future);
      final withdrawals = ledger.where((e) => e.kind == SupplierLedgerKind.payout);
      expect(find.textContaining('${withdrawals.length} of'), findsOneWidget);
    });

    testWidgets('analytics page switches period', (tester) async {
      final service = seededFinance();
      await tester.pumpWidget(wrap(const SupplierAnalyticsScreen(), service));
      await tester.pumpAndSettle();

      expect(find.text('Wholesale performance'), findsOneWidget);
      expect(find.text('Revenue by category'), findsOneWidget);
      expect(find.text('Top moving products'), findsOneWidget);
      expect(find.textContaining('last 30 days'), findsWidgets);

      // Read the 30-day totals while the page is still showing them: once it
      // switches away, that autoDispose provider is dropped and reading it
      // would start a fresh fetch nothing is left to pump.
      final month = await containerOf(
        tester,
        service,
      ).read(supplierAnalyticsProvider(SupplierReportRange.last30Days).future);

      await tester.tap(find.widgetWithText(ChoiceChip, '12 months'));
      await tester.pumpAndSettle();

      expect(find.textContaining('last 12 months'), findsWidgets);
      expect(find.text('Revenue by category'), findsOneWidget);

      expect(
        find.text(money(month.netEarnings)),
        findsNothing,
        reason: 'the 12-month totals must replace the 30-day ones',
      );
    });

    testWidgets('reviews page renders the rating and every review', (
      tester,
    ) async {
      final service = seededFinance();
      await tester.pumpWidget(wrap(const SupplierReviewsScreen(), service));
      await tester.pumpAndSettle();

      final reviews = await containerOf(tester, service).read(supplierReviewsProvider.future);
      expect(find.text('Buyer feedback'), findsOneWidget);
      expect(find.text(reviews.first.author), findsOneWidget);
      expect(find.textContaining('Replied'), findsWidgets);
    });
  });
}
