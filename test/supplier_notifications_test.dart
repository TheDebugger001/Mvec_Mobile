// Covers supplier notification destinations: tapping a notice must lead to the
// page that can act on it, and must never follow a path out of the supplier
// portal.

import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/features/supplier/data/supplier_workspace.dart';

void main() {
  group('notice destinations', () {
    test('an explicit API path wins, but only inside the supplier portal', () {
      for (final inside in ['/supplier', '/supplier/orders', '/supplier/team']) {
        expect(
          supplierNoticeDestination(apiPath: inside),
          inside,
          reason: inside,
        );
      }
      // Refused: the path arrives from the server, so it is not trusted blindly.
      for (final outside in [
        '/admin',
        '/admin/users',
        '/vendor/orders',
        '/suppliers/me/team',
        'https://evil.example/steal',
      ]) {
        expect(
          supplierNoticeDestination(apiPath: outside, type: 'ORDER'),
          isNull,
          reason: outside,
        );
      }
      // Blank is not a destination, so the type takes over.
      expect(supplierNoticeDestination(apiPath: '  ', type: 'ORDER'), '/supplier/orders');
    });

    test('the notice type decides when there is no path', () {
      const expected = {
        'ORDER': '/supplier/orders',
        'ORDER_REQUEST': '/supplier/orders',
        'LOW_STOCK': '/supplier/inventory',
        'INVENTORY': '/supplier/inventory',
        'PRODUCT': '/supplier/products',
        'PAYOUT': '/supplier/payments',
        'PAYMENT': '/supplier/payments',
        'WITHDRAWAL': '/supplier/payments',
        'ESCROW': '/supplier/payments',
        'DELIVERY': '/supplier/delivery',
        'DISPUTE': '/supplier/delivery',
        'SUPPLY_REQUEST': '/supplier/supply-requests',
        'TEAM': '/supplier/team',
        'REVIEW': '/supplier/reviews',
        'SETTINGS': '/supplier/settings',
      };
      expected.forEach((type, path) {
        expect(
          supplierNoticeDestination(type: type),
          path,
          reason: type,
        );
      });
    });

    test('falls back to the headline when the feed sends no type', () {
      expect(
        supplierNoticeDestination(title: 'Payout processed'),
        '/supplier/payments',
      );
      expect(
        supplierNoticeDestination(title: 'Low stock reminder'),
        '/supplier/inventory',
      );
      expect(
        supplierNoticeDestination(title: 'Consignment out for delivery'),
        '/supplier/delivery',
      );
      // Nothing recognisable means no dead button.
      expect(supplierNoticeDestination(title: 'Weekly newsletter'), isNull);
      expect(supplierNoticeDestination(), isNull);
    });

    test('the button says what will happen', () {
      expect(
        supplierNoticeActionLabel('/supplier/payments', null),
        'View payouts',
      );
      expect(
        supplierNoticeActionLabel('/supplier/delivery', null),
        'Track delivery',
      );
      // A verb from the API wins over the derived one.
      expect(
        supplierNoticeActionLabel('/supplier/orders', 'Review order'),
        'Review order',
      );
    });

    test('the parsed notice carries its destination through JSON', () {
      final notice = SupplierNotice.fromJson({
        '_id': 'n-1',
        'type': 'DELIVERY',
        'message': 'Left the depot',
        'createdAt': '2026-09-28T09:00:00Z',
      });
      expect(notice.destination, '/supplier/delivery');
      // The verb is derived at render time from the destination.
      expect(
        supplierNoticeActionLabel(notice.destination, notice.actionLabel),
        'Track delivery',
      );

      final withPath = SupplierNotice.fromJson({
        'id': 'n-2',
        'title': 'Order needs attention',
        'actionPath': '/supplier/orders',
        'actionLabel': 'Open order',
      });
      expect(withPath.destination, '/supplier/orders');
      expect(withPath.actionLabel, 'Open order');
    });

    test('a payload pointing outside the portal resolves to nothing', () {
      final notice = SupplierNotice.fromJson({
        'id': 'n-3',
        'title': 'Order needs attention',
        'actionPath': '/admin/users',
      });
      expect(notice.destination, isNull);
    });
  });
}
