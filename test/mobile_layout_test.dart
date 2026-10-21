import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/fake_backend.dart';

/// Flutter fails a test on any RenderFlex overflow or layout exception, so
/// walking the storefront at small and large phone sizes (light and dark) is
/// a real check that nothing is clipped or overflowing.
void main() {
  const sizes = [Size(320, 640), Size(360, 740), Size(412, 915)];

  void go(WidgetTester tester, String location) => GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);

  for (final size in sizes) {
    for (final dark in [false, true]) {
      testWidgets('storefront fits at ${size.width.toInt()}x${size.height.toInt()}${dark ? ' (dark)' : ''}', (tester) async {
        await pumpApp(tester, FakeBackend(baseRoutes()), size: size);
        if (dark) {
          await tester.tap(find.bySemanticsLabel('Switch to dark mode'));
          await settle(tester);
        }

        // Home, scrolled to the bottom.
        expect(find.text('Deals of the Day'), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
          await settle(tester, frames: 4);
        }
        expect(find.text('Compare products'), findsOneWidget);

        // Sidebar opens over the page and closes again.
        await tester.tap(find.byTooltip('Open menu'));
        await settle(tester);
        expect(find.byTooltip('Close menu'), findsOneWidget);
        await tester.tap(find.byTooltip('Close menu'));
        await settle(tester);
        expect(find.byTooltip('Close menu'), findsNothing);

        // Shop, wishlist and compare screens.
        for (final route in ['/shop', '/shop?deal=true', '/wishlist', '/buyer/compare']) {
          go(tester, route);
          await settle(tester);
        }

        // Product -> add to cart -> cart -> buy now -> checkout.
        go(tester, '/product/p1');
        await settle(tester);
        expect(find.text('Add to cart'), findsOneWidget);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await settle(tester, frames: 4);
        await tester.tap(find.text('Add to cart'));
        await settle(tester);

        go(tester, '/cart');
        await settle(tester);
        expect(find.text('Proceed to checkout'), findsOneWidget);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await settle(tester, frames: 4);

        go(tester, '/checkout');
        await settle(tester);
        expect(find.text('Your details'), findsOneWidget);
        final list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.text("I'll pick it up"), 200, scrollable: list);
        await tester.ensureVisible(find.text("I'll pick it up"));
        await settle(tester, frames: 3);
        await tester.tap(find.text("I'll pick it up"));
        await settle(tester);
        await tester.scrollUntilVisible(find.text('Deliver it to me'), 200, scrollable: list);
        await tester.ensureVisible(find.text('Deliver it to me'));
        await settle(tester, frames: 3);
        await tester.tap(find.text('Deliver it to me'));
        await settle(tester);
        await tester.scrollUntilVisible(find.text('Order summary'), 300, scrollable: list);
        await tester.ensureVisible(find.text('Order summary'));
        await settle(tester, frames: 4);
      });
    }
  }
}
