import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/widgets/splash_gate.dart';

void main() {
  Widget app(Duration shown) => ProviderScope(
        overrides: [splashDurationProvider.overrideWithValue(shown)],
        child: MaterialApp(
          theme: lightAppTheme,
          home: const SplashGate(child: Scaffold(body: Text('the app'))),
        ),
      );

  testWidgets('the splash shows the wordmark for its duration, then reveals the app', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(app(const Duration(seconds: 2)));
    expect(find.text('Ikiguzi'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Ikiguzi'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1)); // fade starts
    await tester.pump(const Duration(seconds: 1)); // fade done, splash removed
    expect(find.text('Ikiguzi'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a zero duration skips the splash', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(app(Duration.zero));
    expect(find.text('Ikiguzi'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });
}
