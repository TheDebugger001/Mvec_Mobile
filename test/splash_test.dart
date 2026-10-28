import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/widgets/splash_gate.dart';

void main() {
  Widget app(Duration shown, {List<SplashTask> tasks = const []}) => ProviderScope(
        overrides: [splashDurationProvider.overrideWithValue(shown), splashTasksProvider.overrideWithValue(tasks)],
        child: MaterialApp(
          theme: lightAppTheme,
          home: const SplashGate(child: Scaffold(body: Text('the app'))),
        ),
      );

  testWidgets('the splash shows the wordmark for its duration, then reveals the app', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(app(const Duration(seconds: 2)));
    expect(find.text('Ikiguzi'), findsOneWidget);
    expect(find.text('YOUR MARKETPLACE,\nEVERYTHING'), findsOneWidget);
    expect(find.text('LOADING...'), findsNothing); // no loader bar

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

  testWidgets('the splash stays past its minimum until the products are ready', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final slow = Completer<void>();
    await tester.pumpWidget(app(const Duration(seconds: 2), tasks: [(_, __) async {}, (_, __) => slow.future]));

    // The minimum time is over, but the products are still loading.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Ikiguzi'), findsOneWidget);

    slow.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ikiguzi'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('the splash has its own Material so no debug underline is drawn', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // No Scaffold above it, like the SplashGate in MaterialApp.builder.
    await tester.pumpWidget(ProviderScope(
      overrides: [splashDurationProvider.overrideWithValue(const Duration(seconds: 2)), splashTasksProvider.overrideWithValue(const [])],
      child: MaterialApp(theme: lightAppTheme, home: const SplashGate(child: SizedBox())),
    ));
    final tagline = tester.widget<Text>(find.text('YOUR MARKETPLACE,\nEVERYTHING'));
    expect(tagline.style?.decoration, TextDecoration.none);
    expect(find.ancestor(of: find.text('Ikiguzi'), matching: find.byType(Material)), findsWidgets);
  });

  testWidgets('a failing preparation task does not block the app', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.pumpWidget(app(const Duration(seconds: 2), tasks: [(_, __) async => throw StateError('offline')]));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('the app'), findsOneWidget);
  });
}
