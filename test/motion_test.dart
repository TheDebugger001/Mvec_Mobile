import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/core/theme.dart';
import 'package:mvec_mobile/widgets/common.dart';
import 'package:mvec_mobile/widgets/motion.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: lightAppTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _scaleOf(WidgetTester tester, Finder within) =>
    tester.widget<AnimatedScale>(find.descendant(of: within, matching: find.byType(AnimatedScale)).first).scale;

void main() {
  testWidgets('a pressed button shrinks, springs back, and its action runs at once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(GradientButton(label: 'Add to cart', onPressed: () => taps++)));
    final button = find.byType(GradientButton);

    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump();
    expect(_scaleOf(tester, button), lessThan(1));

    await gesture.up();
    await tester.pump();
    expect(taps, 1, reason: 'the tap is not delayed by the animation');
    expect(_scaleOf(tester, button), 1);
    await tester.pumpAndSettle();
  });

  testWidgets('dragging across a card is a scroll, not a press', (tester) async {
    await tester.pumpWidget(_app(const Pressable(child: SizedBox(width: 120, height: 120, child: ColoredBox(color: Colors.blue)))));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ColoredBox)));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(_scaleOf(tester, find.byType(Pressable)), 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('with reduce motion on, nothing scales', (tester) async {
    await tester.pumpWidget(_app(GradientButton(label: 'Pay', onPressed: () {}), reduceMotion: true));
    expect(find.descendant(of: find.byType(GradientButton), matching: find.byType(AnimatedScale)), findsNothing);
  });

  testWidgets('the heart only pops when its saved state actually changes', (tester) async {
    Widget heart(bool on) => _app(HeartPop(active: on, child: const Icon(Icons.favorite, size: 20)));
    await tester.pumpWidget(heart(true));
    // Already saved when the screen opens: shown at full size, no pop.
    expect(tester.widget<ScaleTransition>(find.descendant(of: find.byType(HeartPop), matching: find.byType(ScaleTransition))).scale.value, 1);

    await tester.pumpWidget(heart(false));
    await tester.pumpWidget(heart(true));
    await tester.pump(const Duration(milliseconds: 120));
    final mid = tester.widget<ScaleTransition>(find.descendant(of: find.byType(HeartPop), matching: find.byType(ScaleTransition))).scale.value;
    expect(mid, greaterThan(1), reason: 'pops past full size');
    await tester.pumpAndSettle();
    expect(tester.widget<ScaleTransition>(find.descendant(of: find.byType(HeartPop), matching: find.byType(ScaleTransition))).scale.value, closeTo(1, .001));
  });

  testWidgets('badges bounce when the count goes up, not when it goes down', (tester) async {
    Widget badge(int n) => _app(BumpOnIncrease(value: n, child: Text('$n')));
    double scale() => tester.widget<ScaleTransition>(find.descendant(of: find.byType(BumpOnIncrease), matching: find.byType(ScaleTransition))).scale.value;

    await tester.pumpWidget(badge(1));
    await tester.pumpWidget(badge(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(), greaterThan(1));
    await tester.pumpAndSettle();

    await tester.pumpWidget(badge(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(), 1);
  });

  testWidgets('a confirmed add shows a check on the button', (tester) async {
    await tester.pumpWidget(_app(GradientButton(label: 'Added', success: true, onPressed: () {})));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
  });

  testWidgets('changing totals animate to the new value', (tester) async {
    await tester.pumpWidget(_app(const AnimatedValueText('30,000 RWF')));
    await tester.pumpWidget(_app(const AnimatedValueText('60,000 RWF')));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('30,000 RWF'), findsOneWidget, reason: 'old value is still leaving');
    await tester.pumpAndSettle();
    expect(find.text('30,000 RWF'), findsNothing);
    expect(find.text('60,000 RWF'), findsOneWidget);
  });

  testWidgets('sign-in forms slide in once, row by row, and settle fully visible', (tester) async {
    Widget form(int rows, {bool reduce = false}) => _app(SlideInColumn(children: [for (var i = 0; i < rows; i++) Text('row $i')]), reduceMotion: reduce);
    double opacity(String t) => tester.widget<FadeTransition>(find.ancestor(of: find.text(t), matching: find.byType(FadeTransition)).first).opacity.value;

    await tester.pumpWidget(form(3));
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity('row 0'), greaterThan(opacity('row 2')), reason: 'later rows start after earlier ones');
    await tester.pumpAndSettle();
    expect(opacity('row 2'), 1);

    // A rebuild that adds a row (e.g. switching to code login) does not replay it.
    await tester.pumpWidget(form(4));
    await tester.pump();
    expect(opacity('row 0'), 1);
    expect(find.text('row 3'), findsOneWidget);
  });

  testWidgets('with reduce motion on, forms appear at once', (tester) async {
    await tester.pumpWidget(_app(const SlideInColumn(children: [Text('Email')]), reduceMotion: true));
    await tester.pump();
    expect(tester.widget<FadeTransition>(find.ancestor(of: find.text('Email'), matching: find.byType(FadeTransition)).first).opacity.value, 1);
  });
}
