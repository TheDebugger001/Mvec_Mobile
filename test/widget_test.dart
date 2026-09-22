// Smoke tests for the marketplace app shell: top menu + home feed render.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/features/marketplace/presentation/Screens/home_screen.dart';
import 'package:mvec_mobile/main.dart';

void main() {
  testWidgets('renders the top menu and home feed', (WidgetTester tester) async {
    await tester.pumpWidget(const MvecApp());
    await tester.pumpAndSettle();

    // The horizontally scrollable top menu shows the marketplace tabs.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.textContaining('You are previewing demo data'), findsOneWidget);

    // Scroll the home feed down to reveal the featured products row.
    final homeList = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.byType(ListView),
    );
    await tester.drag(homeList, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Wireless Over-Ear Headphones'), findsWidgets);
  });

  testWidgets('tapping a top menu item switches the body',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MvecApp());
    await tester.pumpAndSettle();

    // Scroll the top menu to reach the trailing Orders tab.
    final menu = find.byType(ListView).first;
    await tester.drag(menu, const Offset(-800, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

    expect(find.text('#MV-20415'), findsOneWidget);
  });
}