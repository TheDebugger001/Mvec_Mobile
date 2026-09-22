// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/main.dart';

void main() {
  testWidgets('product detail screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Classic Leather Backpack'), findsOneWidget);
    expect(find.text('Add to Cart'), findsOneWidget);
  });

  testWidgets('wishlist stays connected to product detail',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Open wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('My Wishlist'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pump();

    expect(find.text('Your wishlist is empty'), findsOneWidget);
  });

  testWidgets('wishlist product can be moved to cart',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Open wishlist'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move to Cart'));
    await tester.pump();
    expect(find.text('Your wishlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Open cart'));
    await tester.pumpAndSettle();

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);
  });

  testWidgets('cart shows added products and supports removal',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Add to Cart'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Open cart'));
    await tester.pumpAndSettle();

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from cart'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Are you sure you want to delete Classic Leather Backpack from your cart?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('Classic Leather Backpack'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('cart opens checkout with the current order',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Add to Cart'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byTooltip('Open cart'));
    await tester.pumpAndSettle();

    final checkoutButton = find.text('Proceed to Checkout');
    await tester.ensureVisible(checkoutButton);
    final checkoutAction = tester.widget<ElevatedButton>(
      find.ancestor(
        of: checkoutButton,
        matching: find.byType(ElevatedButton),
      ),
    );
    checkoutAction.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Order Review'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);
    expect(find.text('Confirm & Place Order'), findsOneWidget);
  });
}
