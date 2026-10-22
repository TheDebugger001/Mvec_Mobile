import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/fake_backend.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

Map<String, dynamic> order(String id, {String payment = 'PENDING', String status = 'PENDING'}) => {
      'id': id,
      '_id': id,
      'orderNumber': 'MVEC-ORDER-$id',
      'orderStatus': status,
      'paymentStatus': payment,
      'totalAmount': 40000,
      'createdAt': DateTime.now().toIso8601String(),
      'items': [
        {'name': 'Wireless Headphones', 'price': 40000, 'quantity': 1, 'product': 'p1'},
      ],
    };

Future<void> signIn(WidgetTester tester, FakeBackend backend) async {
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

Map<String, Handler> routes() => {
      ...baseRoutes(),
      'POST /auth/login': (_) => (200, {'token': 'jwt', 'user': userJson('buyer')}),
      'GET /auth/me': (_) => (200, {'user': userJson('buyer')}),
    };

void main() {
  testWidgets('orders: an unpaid order offers Pay now and can be cancelled', (tester) async {
    final backend = FakeBackend({
      ...routes(),
      'GET /orders/my-orders': (_) => (200, {'orders': [order('o1')]}),
      'POST /orders/o1/cancel': (_) => (200, {'message': 'Order cancelled.', 'order': order('o1', status: 'CANCELLED')}),
    });
    await signIn(tester, backend);
    await tester.tap(find.byTooltip('Orders'));
    await settle(tester);
    expect(find.text('MVEC-ORDER-o1'), findsOneWidget);
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('Pay now'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester, frames: 4);
    await tester.tap(find.text('Cancel order'));
    await settle(tester);
    expect(backend.where('POST', '/orders/o1/cancel'), hasLength(1));
    expect(find.text('Order cancelled.'), findsOneWidget);
  });

  testWidgets('wishlist: the heart saves to the account and the page lists it', (tester) async {
    var saved = false;
    Map<String, dynamic> item() => {
          'product': product('p1', 'Wireless Headphones', price: 50000, discount: 40000),
          'savedPrice': 40000,
        };
    final backend = FakeBackend({
      ...routes(),
      'GET /auth/wishlist': (_) => (200, {'items': saved ? [item()] : []}),
      'POST /auth/wishlist': (_) {
        saved = true;
        return (200, {'items': [item()]});
      },
    });
    await signIn(tester, backend);
    await tester.tap(find.bySemanticsLabel('Save to wishlist').first);
    await settle(tester);
    expect(backend.where('POST', '/auth/wishlist').single.body, {'productIds': ['p1']});
    expect(find.byTooltip('Wishlist, 1 items'), findsOneWidget);

    await tester.tap(find.byTooltip('Wishlist, 1 items'));
    await settle(tester);
    expect(find.text('Move to cart'), findsOneWidget);
    expect(find.text('Wireless Headphones'), findsWidgets);
  });

  testWidgets('profile shows the account and saves edits', (tester) async {
    final backend = FakeBackend({
      ...routes(),
      'GET /auth/addresses': (_) => (200, {'addresses': []}),
      'PATCH /auth/me': (_) => (200, {'user': userJson('buyer', name: 'Aline N.')}),
    });
    await signIn(tester, backend);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/profile');
    await settle(tester);
    expect(find.text('Aline Uwase'), findsWidgets);
    await tester.tap(find.text('Edit details'));
    await settle(tester, frames: 3);
    await tester.enterText(field('Full name'), 'Aline N.');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((backend.where('PATCH', '/auth/me').single.body as Map)['Fullname'], 'Aline N.');
    expect(find.text('Your details were saved.'), findsOneWidget);
  });
}
