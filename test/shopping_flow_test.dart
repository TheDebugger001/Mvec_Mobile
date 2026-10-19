import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/fake_backend.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

Map<String, dynamic> orderJson({String status = 'PENDING', String payment = 'PENDING', bool paid = false}) => {
      'id': 'o1',
      '_id': 'o1',
      'orderNumber': 'MVEC-WIRELESS-HEADPHONES-2026-000001-4821',
      'orderStatus': status,
      'paymentStatus': payment,
      'paymentMethod': 'MOMO',
      'totalAmount': 40000,
      'subtotal': 40000,
      'shippingFee': 0,
      'shippingMethod': 'PICKUP',
      'createdAt': DateTime.now().toIso8601String(),
      'paidAt': paid ? DateTime.now().toIso8601String() : null,
      'deliveryOtp': paid ? '482913' : null,
      'recipient': {'name': 'Aline Uwase', 'phone': '0788123456'},
      'items': [
        {'name': 'Wireless Headphones', 'price': 40000, 'quantity': 1, 'product': 'p1', 'image': ''},
      ],
    };

Map<String, Handler> signedInRoutes() => {
      ...baseRoutes(),
      'GET /auth/me': (_) => (200, {'user': userJson('buyer')}),
    };

/// Starts the app already signed in (a stored token that `/auth/me` accepts).
Future<void> pumpSignedIn(WidgetTester tester, FakeBackend backend) async {
  await pumpApp(tester, backend);
  await tester.tap(find.byTooltip('Sign in or create an account'));
  await settle(tester, frames: 4);
  await tester.tap(find.text('Sign in').last);
  await settle(tester);
  await tester.enterText(field('Email or phone number'), 'aline@mvec.rw');
  await tester.enterText(field('Password'), 'Secret@123');
  await tester.tap(find.text('Log in').last);
  await settle(tester, frames: 20);
}

void main() {
  testWidgets('guest: product -> cart -> checkout -> phone code -> payment', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'POST /shipping/quote': (_) => (200, {'deliverable': true, 'shippingFee': 0, 'groups': [{'storeName': 'Kigali Gadgets', 'pickup': {'address': 'KN 4 Ave'}}]}),
      'POST /auth/guest/send-code': (_) => (200, {'devCode': '123456'}),
      'POST /auth/guest/verify': (_) => (200, {'token': 'guest-jwt', 'user': userJson('buyer'), 'guest': true}),
      'POST /orders/direct-checkout': (_) => (201, {'order': orderJson()}),
      'GET /auth/me': (_) => (200, {'user': userJson('buyer')}),
      'GET /orders/o1': (_) => (200, {'order': orderJson()}),
    });
    await pumpApp(tester, backend);

    // Open the product from the home screen.
    await tester.tap(find.text('Wireless Headphones').first);
    await settle(tester);
    expect(find.text('40,000 RWF'), findsWidgets);
    expect(find.text('Add to cart'), findsOneWidget);
    await tester.tap(find.text('Add to cart'));
    await settle(tester);
    expect(find.text('Added to your cart.'), findsOneWidget);

    // A guest's cart lives on the phone, not on the server.
    expect(backend.where('POST', '/cart'), isEmpty);

    // Buy now goes straight to checkout with the product and quantity.
    await tester.tap(find.text('Buy now'));
    await settle(tester);
    expect(find.text('Complete your order'), findsNothing); // mobile copy is shorter
    expect(find.text('Your details'), findsOneWidget);
    expect(find.text('Verify phone & continue'), findsOneWidget);

    await tester.enterText(field('Full name'), 'Aline Uwase');
    await tester.enterText(field('Phone'), '0788123456');
    await tester.tap(find.text("I'll pick it up"));
    await settle(tester);
    final quote = backend.where('POST', '/shipping/quote').last.body as Map;
    expect(quote['method'], 'PICKUP');
    expect((quote['items'] as List).first, {'productId': 'p1', 'qty': 1});

    await tester.tap(find.text('Verify phone & continue'));
    await settle(tester);
    expect(find.text('Confirm your phone'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Code'), '123456');
    await tester.tap(find.text('Confirm & continue'));
    await settle(tester, frames: 20);

    expect((backend.where('POST', '/auth/guest/verify').single.body as Map)['code'], '123456');
    final order = backend.where('POST', '/orders/direct-checkout').single.body as Map;
    expect(order['items'], [
      {'productId': 'p1', 'quantity': 1},
    ]);
    expect(order['deliveryMethod'], 'pickup');
    expect(order['recipient'], {'name': 'Aline Uwase', 'phone': '0788123456', 'email': ''});
    expect(find.text('Pay for your order'), findsOneWidget);
  });

  testWidgets('signed-in buyer: add to cart uses the account cart and quantities update', (tester) async {
    var qty = 1;
    Map<String, dynamic> cart() => {
          'cart': {
            'items': [
              {'product': product('p1', 'Wireless Headphones', price: 50000, discount: 40000), 'quantity': qty, 'price': 40000},
            ],
          },
        };
    final backend = FakeBackend({
      ...signedInRoutes(),
      'POST /auth/login': (_) => (200, {'token': 'jwt', 'user': userJson('buyer')}),
      'POST /cart': (_) => (200, cart()),
      'PUT /cart/items/p1': (c) {
        qty = (c.body as Map)['quantity'] as int;
        return (200, cart());
      },
      'GET /cart': (_) => (200, cart()),
    });
    await pumpSignedIn(tester, backend);
    await tester.tap(find.text('Wireless Headphones').first);
    await settle(tester);
    await tester.tap(find.text('Add to cart'));
    await settle(tester);
    expect(backend.where('POST', '/cart').single.body, {'productId': 'p1', 'quantity': 1});

    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byTooltip('Cart, 1 items'));
    await settle(tester);
    expect(find.text('Your cart'), findsOneWidget);
    expect(find.text('Proceed to checkout'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(tester);
    expect(backend.where('PUT', '/cart/items/p1').single.body, {'quantity': 2});
    expect(find.byTooltip('Cart, 2 items'), findsOneWidget);
  });

  testWidgets('mobile money payment is confirmed by polling the order', (tester) async {
    var polls = 0;
    final backend = FakeBackend({
      ...signedInRoutes(),
      'POST /auth/login': (_) => (200, {'token': 'jwt', 'user': userJson('buyer')}),
      'GET /orders/o1': (_) => (200, {'order': orderJson(status: polls > 0 ? 'CONFIRMED' : 'PENDING', payment: polls > 0 ? 'PAID' : 'PENDING', paid: polls > 0)}),
      'POST /payments/pay': (_) => (200, {'status': 'PENDING', 'paymentId': 'pay1', 'message': 'Approve the prompt on your phone.'}),
      'GET /payments/status/pay1': (_) {
        polls++;
        return (200, {'payment': {'status': 'SUCCESS'}, 'order': {'paymentStatus': 'PAID'}});
      },
    });
    await pumpSignedIn(tester, backend);
    // Open the payment screen the way "Pay now" on an order does.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/payment/o1');
    await settle(tester);
    expect(find.text('Pay for your order'), findsOneWidget);

    await tester.tap(find.textContaining('Pay 40,000 RWF'));
    await settle(tester);
    expect((backend.where('POST', '/payments/pay').single.body as Map), {'orderId': 'o1', 'phoneNumber': '0788123456'});
    expect(find.text('Approve the prompt on your phone.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Payment confirmed ✓'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester, frames: 10);
    // Lands on the order, which now shows the delivery code.
    await tester.scrollUntilVisible(find.text('Your delivery code'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Your delivery code'), findsOneWidget);
    expect(find.text('482913'), findsOneWidget);
  });
}
