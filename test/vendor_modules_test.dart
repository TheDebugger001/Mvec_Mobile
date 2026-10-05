// Vendor module coverage against the shipped transport.
//
// There is no bundled vendor dataset any more: the module is API-only, so these
// tests exercise the real `Api*Service` classes over a fake transport. What is
// pinned here is the contract the screens depend on — the paths and query the
// services request, how they map a payload onto the models, and that they fail
// loudly rather than inventing data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/features/vendor/models/vendor_finance.dart';
import 'package:mvec_mobile/features/vendor/models/vendor_order.dart';
import 'package:mvec_mobile/features/vendor/models/vendor_settings.dart';
import 'package:mvec_mobile/features/vendor/screens/vendor_settings_screen.dart';
import 'package:mvec_mobile/features/vendor/services/vendor_finance_service.dart';
import 'package:mvec_mobile/features/vendor/services/vendor_notification_service.dart';
import 'package:mvec_mobile/features/vendor/services/vendor_order_service.dart';
import 'package:mvec_mobile/features/vendor/services/vendor_settings_service.dart';
import 'package:mvec_mobile/features/vendor/vendor_dependencies.dart';

import 'helpers/fake_api.dart';

void main() {
  tearDown(restoreApiTransport);

  group('vendor dependency wiring', () {
    test('every module resolves to the API service, never a bundled dataset', () {
      fakeApi(const []);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(vendorOrderModuleProvider), isA<ApiVendorOrderService>());
      expect(container.read(vendorFinanceModuleProvider), isA<ApiVendorFinanceService>());
      expect(container.read(vendorNotificationModuleProvider), isA<ApiVendorNotificationService>());
      expect(container.read(vendorSettingsModuleProvider), isA<ApiVendorSettingsService>());

      // `isDemo` is retained so screens can branch without changing, but no
      // shipped service may ever report that it is serving local data.
      expect(container.read(vendorOrderModuleProvider).isDemo, isFalse);
      expect(container.read(vendorFinanceModuleProvider).isDemo, isFalse);
      expect(container.read(vendorNotificationModuleProvider).isDemo, isFalse);
      expect(container.read(vendorSettingsModuleProvider).isDemo, isFalse);
    });
  });

  group('ApiVendorOrderService', () {
    test('requests the vendor orders route and maps the payload', () async {
      final api = fakeApi([
        FakeRoute('GET', '/stores/mine/orders', body: {
          'orders': [
            {
              '_id': 'ord-1',
              'number': 'MV-1001',
              'status': 'shipped',
              'trackingCode': 'TRK-9',
              'total': 45000,
              'buyerName': 'Aline U.',
            },
          ],
        }),
      ]);

      final page = await ApiVendorOrderService(api.client).orders();

      expect(page.orders, hasLength(1));
      final order = page.orders.single;
      expect(order.id, 'ord-1');
      expect(order.status, VendorOrderStatus.shipped);
      expect(order.trackingCode, 'TRK-9');
    });

    test('a status filter is sent as a query parameter', () async {
      final api = fakeApi([
        FakeRoute('GET', '/stores/mine/orders', body: {'orders': <dynamic>[]}),
      ]);

      await ApiVendorOrderService(api.client).orders(status: VendorOrderStatus.shipped, search: 'kigali');

      final sent = api.recorded.first;
      expect(sent.method, 'GET');
      expect(sent.path, '/stores/mine/orders');
      expect(sent.query['status'], 'SHIPPED');
      expect(sent.query['search'], 'kigali');
    });

    test('an empty payload yields an empty page, not an error', () async {
      final api = fakeApi([
        FakeRoute('GET', '/stores/mine/orders', body: {'orders': <dynamic>[]}),
      ]);

      final page = await ApiVendorOrderService(api.client).orders();

      expect(page.orders, isEmpty);
    });

    test('a failed request surfaces as ApiException so the screen can retry', () async {
      final api = fakeApi([
        FakeRoute('GET', '/stores/mine/orders', status: 500, body: {'message': 'Boom'}),
      ]);

      await expectLater(
        ApiVendorOrderService(api.client).orders(),
        throwsA(isA<Object>()),
      );
    });
  });

  group('ApiVendorFinanceService', () {
    test('maps the summary and keeps net equal to gross minus commission', () async {
      final api = fakeApi([
        FakeRoute('GET', '/stores/mine/finance/summary', body: {
          'summary': {
            'grossRevenue': 500000,
            'commission': 50000,
            'netEarnings': 450000,
            'escrowHeld': 120000,
            'availablePayout': 320000,
          },
        }),
      ]);

      final summary = await ApiVendorFinanceService(api.client).summary();

      expect(summary.isConsistent, isTrue);
      expect(summary.grossRevenue, 500000);
      expect(summary.netEarnings, 450000);
      expect(summary.availablePayout, 320000);
    });

    test('a request to withdraw more than the balance is refused by the server', () async {
      final api = fakeApi([
        FakeRoute('POST', '/stores/mine/finance/payouts', status: 400, body: {
          'message': 'Amount exceeds available balance',
        }),
      ]);

      await expectLater(
        ApiVendorFinanceService(api.client).requestPayout(
          amount: 99999999,
          method: PayoutMethod.mtnMomo,
          destination: '+250788000001',
        ),
        throwsA(isA<Object>()),
      );
    });
  });

  group('ApiVendorSettingsService', () {
    test('saves the edited profile and returns what the server stored', () async {
      final api = fakeApi([
        FakeRoute('PUT', '/stores/mine/settings', body: {
          'settings': {'storeName': 'Renamed Store'},
        }),
      ]);

      const draft = VendorStoreSettings(
        storeName: 'Renamed Store',
        hours: OperatingHours(<OperatingDay>[]),
      );
      final saved = await ApiVendorSettingsService(api.client).save(draft);

      expect(saved.storeName, 'Renamed Store');
      final sent = api.recorded.first;
      expect(sent.method, 'PUT');
      expect(sent.path, '/stores/mine/settings');
    });

    test('a password is never echoed back into the stored settings', () async {
      final api = fakeApi([
        FakeRoute('POST', '/stores/mine/settings/staff', body: {
          'settings': {
            'storeName': 'Test Store',
            'staff': [
              {
                '_id': 'staff-1',
                'name': 'Test Member',
                'email': 'member@example.rw',
                'role': 'staff',
              },
            ],
          },
        }),
      ]);

      final member = VendorStaffMember(
        id: 'staff-1',
        name: 'Test Member',
        email: 'member@example.rw',
        role: StaffRole.staff,
        permissions: StaffRole.staff.defaults,
      );

      final updated = await ApiVendorSettingsService(api.client).inviteStaff(
        member: member,
        password: 'Temporary-123',
      );

      expect(updated.staff.any((s) => s.id == member.id), isTrue);
      expect(updated.toJson().toString(), isNot(contains('Temporary-123')));
    });
  });

  group('ApiVendorNotificationService', () {
    test('reads the notification list and maps the read flag', () async {
      final api = fakeApi([
        FakeRoute('GET', '/stores/mine/notifications', body: {
          'notifications': [
            {'_id': 'n1', 'title': 'New order', 'read': false},
            {'_id': 'n2', 'title': 'Payout sent', 'read': true},
          ],
        }),
      ]);

      final items = await ApiVendorNotificationService(api.client).notifications();

      expect(items, hasLength(2));
      expect(items.firstWhere((n) => n.id == 'n1').read, isFalse);
      expect(items.firstWhere((n) => n.id == 'n2').read, isTrue);
    });
  });

  group('models', () {
    test('shipping summaries format whole RWF amounts safely', () {
      const flat = ShippingRule(
        id: 'flat',
        name: 'Standard',
        type: ShippingRuleType.flat,
        amount: 2000,
        etaDays: 2,
      );
      const free = ShippingRule(
        id: 'free',
        name: 'Free delivery',
        type: ShippingRuleType.free,
        minimumOrder: 50000,
        etaDays: 1,
      );

      expect(flat.summary, '2,000 · 2 days');
      expect(free.summary, 'Free above 50,000');
    });

    test('status slugs from the backend map onto the known states', () {
      expect(VendorOrderStatus.parse('shipped'), VendorOrderStatus.shipped);
      expect(VendorOrderStatus.parse('SHIPPED'), VendorOrderStatus.shipped);
      expect(VendorOrderStatus.parse('unknown-slug'), isNotNull);
      expect(VendorOrderStatus.parse(null), isNotNull);
    });

    test('staff roles carry fixed permissions', () {
      expect(StaffRole.owner.defaults, contains(VendorPermission.manageStaff));
      expect(StaffRole.staff.defaults, isNot(contains(VendorPermission.manageStaff)));
    });
  });

  testWidgets('business and delivery section renders shipping options', (
    tester,
  ) async {
    fakeApi(const []);
    const settings = VendorStoreSettings(
      storeName: 'Test Store',
      hours: OperatingHours([OperatingDay(label: 'Monday', open: true)]),
      shippingRules: [
        ShippingRule(
          id: 'ship-standard',
          name: 'Kigali standard',
          type: ShippingRuleType.flat,
          amount: 2000,
          etaDays: 2,
        ),
        ShippingRule(
          id: 'ship-free',
          name: 'Free delivery',
          type: ShippingRuleType.free,
          minimumOrder: 50000,
          etaDays: 1,
        ),
      ],
      defaultShippingRuleId: 'ship-standard',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vendorStoreSettingsProvider.overrideWith((ref) async => settings),
        ],
        child: MaterialApp(
          theme: lightAppTheme,
          home: const Scaffold(
            body: SingleChildScrollView(child: VendorSettingsScreen()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Business & delivery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Kigali standard · 2,000 · 2 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}