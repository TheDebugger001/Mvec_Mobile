import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';

void main() {
  testWidgets('bottom bar has exactly Home, Shop, For You, Deals, Orders', (tester) async {
    await pumpApp(tester, FakeBackend(baseRoutes()));
    for (final label in ['Home', 'Shop', 'For You', 'Deals', 'Orders']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Cart'), findsNothing);
    expect(find.text('Wishlist'), findsNothing);
  });

  testWidgets('hamburger opens the sidebar from the left', (tester) async {
    await pumpApp(tester, FakeBackend(baseRoutes()));
    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    expect(find.byTooltip('Close menu'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    // The panel's left edge sits at the left of the screen.
    final drawer = tester.getRect(find.byTooltip('Close menu'));
    expect(drawer.left, lessThan(200));
  });

  testWidgets('sidebar keeps every destination and closes from the menu icon', (tester) async {
    await pumpApp(tester, FakeBackend(baseRoutes()));
    await tester.tap(find.byTooltip('Open menu'));
    await settle(tester);
    for (final label in ['Home', 'Shop', 'For You', 'Deals', 'Stores', 'Categories', 'Orders', 'Wishlist', 'Cart', 'Compare', 'Help & Support', 'Become a vendor']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tester.tap(find.byTooltip('Close menu'));
    await settle(tester);
    expect(find.byTooltip('Close menu'), findsNothing);
  });

  testWidgets('home shows products and the top bar has the required actions', (tester) async {
    await pumpApp(tester, FakeBackend(baseRoutes()));
    expect(find.text('Wireless Headphones'), findsWidgets);
    expect(find.byTooltip('Open menu'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Search products')), findsOneWidget);
    expect(find.bySemanticsLabel('Switch to dark mode'), findsOneWidget);
    expect(find.byTooltip('Wishlist, 0 items'), findsOneWidget);
    expect(find.byTooltip('Cart, 0 items'), findsOneWidget);
    expect(find.byTooltip('Sign in or create an account'), findsOneWidget);
  });

  testWidgets('tapping Deals opens the sale-only shop', (tester) async {
    await pumpApp(tester, FakeBackend(baseRoutes()));
    await tester.tap(find.text('Deals'));
    await settle(tester);
    expect(find.text('Deals'), findsWidgets);
    expect(find.text('Wireless Headphones'), findsWidgets);
    expect(find.text('Phone Case'), findsNothing); // not on sale
  });

  testWidgets('dark mode toggle switches the theme', (tester) async {
    await pumpApp(tester, FakeBackend(baseRoutes()));
    await tester.tap(find.bySemanticsLabel('Switch to dark mode'));
    await settle(tester);
    expect(find.bySemanticsLabel('Switch to light mode'), findsOneWidget);
  });
}
