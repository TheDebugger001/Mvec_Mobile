import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/features/marketplace/product_extras.dart';
import 'package:mvec_mobile/models/product.dart';
import 'package:mvec_mobile/state/cart_state.dart';

void main() {
  final shirt = Product.fromJson({
    '_id': 'p1',
    'name': 'Cotton shirt',
    'price': 10000,
    'stockQuantity': 3,
    'deal': {'price': 7000, 'startsAt': '2026-11-18T08:00:00Z', 'endsAt': '2099-01-01T00:00:00Z', 'live': true, 'left': 2, 'percentOff': 30},
    'variants': [
      {'id': 'v1', 'key': 'p1~v1', 'label': 'Red / M', 'options': {'Color': 'Red', 'Size': 'M'}, 'price': 7000, 'ownPrice': null, 'stockQuantity': 2},
      {'id': 'v2', 'key': 'p1~v2', 'label': 'Red / XL', 'options': {'Color': 'Red', 'Size': 'XL'}, 'price': 12000, 'ownPrice': 12000, 'stockQuantity': 0},
    ],
    'variantOptions': [
      {'name': 'Color', 'values': ['Red']},
      {'name': 'Size', 'values': ['M', 'XL']},
    ],
    'sellerBadges': [
      {'code': 'VERIFIED', 'label': 'Verified seller', 'hint': 'Checked'},
    ],
  });

  test('a live deal is the price; variants, options and badges come through', () {
    expect(shirt.price, 7000);
    expect(shirt.oldPrice, 10000);
    expect(shirt.deal!.left, 2);
    expect(shirt.hasVariants, isTrue);
    expect(shirt.variantOptions.map((o) => o.name), ['Color', 'Size']);
    expect(shirt.sellerBadges.single.code, 'VERIFIED');
  });

  test('a variant becomes its own cart line with its key, price, stock and label', () {
    final xl = shirt.forVariant(shirt.variants[1]);
    expect([xl.id, xl.productId, xl.variantLabel, xl.price, xl.stock], ['p1~v2', 'p1', 'Red / XL', 12000, 0]);
    expect(xl.oldPrice, 0); // its own price isn't a discount
    final line = CartLine.fromServer({
      'product': {'_id': 'p1', 'name': 'Cotton shirt', 'price': 10000, 'stockQuantity': 3},
      'lineId': 'p1~v1',
      'variantLabel': 'Red / M',
      'variantStock': 2,
      'price': 7000,
      'quantity': 1,
    })!;
    expect([line.id, line.productRef, line.variantLabel, line.stock], ['p1~v1', 'p1', 'Red / M', 2]);
  });

  test('countdowns read in hours, minutes and seconds, or days', () {
    final now = DateTime(2026, 11, 18, 10);
    expect(countdownText(now.add(const Duration(hours: 2, minutes: 5, seconds: 9)), now), '2h 05m 09s');
    expect(countdownText(now.add(const Duration(days: 3, hours: 4)), now), '3d 4h 00m');
    expect(countdownText(now.subtract(const Duration(seconds: 1)), now), '');
  });
}
