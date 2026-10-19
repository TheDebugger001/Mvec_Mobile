import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MvecApp(),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('bottom bar has exactly Home, Shop, For You, Deals, Orders', (tester) async {
    await _pumpApp(tester);
    for (final label in ['Home', 'Shop', 'For You', 'Deals', 'Orders']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Cart, Wishlist and Account are in the top bar, not the bottom bar.
    expect(find.text('Cart'), findsNothing);
    expect(find.text('Wishlist'), findsNothing);
  });

  testWidgets('hamburger opens the sidebar', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MARKETPLACE'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });
}
