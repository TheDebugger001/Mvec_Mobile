import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/core/order_rules.dart';
import 'package:mvec_mobile/core/redirect.dart';
import 'package:mvec_mobile/models/product.dart';
import 'package:mvec_mobile/models/user.dart';

import 'helpers/fake_backend.dart';

void main() {
  group('after sign-in', () {
    test('only in-app paths are followed', () {
      expect(safeRedirect('/orders/1'), '/orders/1');
      for (final bad in ['https://evil.com', '//evil.com', r'/\evil.com', 'orders', '/login', null]) {
        expect(safeRedirect(bad), '', reason: '$bad');
      }
    });

    test('sellers land on their dashboard, buyers go back', () {
      expect(afterSignIn(AppUser.fromJson(userJson('buyer')), '/cart'), '/cart');
      final vendor = AppUser.fromJson(userJson('vendor'));
      expect(afterSignIn(vendor, '/cart'), homeForRole('vendor'));
      expect(afterSignIn(vendor, '${homeForRole('vendor')}/orders'), '${homeForRole('vendor')}/orders');
    });
  });

  group('cancelling an order (mirrors order.controller.js)', () {
    final paidAt = DateTime.utc(2026, 11, 1, 10);
    final paid = {'paymentStatus': 'PAID', 'orderStatus': 'CONFIRMED', 'paidAt': paidAt.toIso8601String()};

    test('an unpaid order can be cancelled', () {
      expect(canCancel({'paymentStatus': 'PENDING', 'orderStatus': 'PENDING'}), isTrue);
    });

    test('a paid order only inside the 30-minute window, before it ships', () {
      expect(paidCancelRemaining(paid, paidAt.add(const Duration(minutes: 10))), const Duration(minutes: 20));
      expect(canCancel(paid, paidAt.add(const Duration(minutes: 31))), isFalse);
      expect(canCancel({...paid, 'orderStatus': 'SHIPPED'}, paidAt), isFalse);
    });

    test('buyers see plain words', () {
      expect(buyerStatus({'orderStatus': 'CANCELLED', 'paymentStatus': 'REFUNDED'}), 'Cancelled · refunded');
      expect(buyerStatus({'orderStatus': 'OUT_FOR_DELIVERY', 'paymentStatus': 'PAID'}), 'Out for delivery');
    });
  });

  group('products from the API', () {
    test('a real discount becomes the price, with the old price kept', () {
      final p = Product.fromJson(product('p1', 'Headphones', price: 85000, discount: 68000));
      expect(p.price, 68000);
      expect(p.oldPrice, 85000);
      expect(p.vendor, 'Kigali Gadgets');
    });

    test('a discount at or above the price is ignored', () {
      final p = Product.fromJson(product('p1', 'Headphones', price: 50000, discount: 60000));
      expect(p.price, 50000);
      expect(p.oldPrice, 0);
    });

    test('missing fields fall back instead of crashing', () {
      final p = Product.fromJson({'_id': 'p2', 'name': 'Mat'});
      expect(p.category, 'Uncategorized');
      expect(p.stock, 0);
      expect(p.image, isEmpty);
    });
  });
}
