// Verifies the DEMO_MODE auth gate: with `--dart-define=DEMO_MODE=true` the real
// `AuthController` must sign in locally, without any network round-trip, so the
// app can be presented with no backend running.
//
// This file is only meaningful under that define — `kDemoMode` is resolved at
// compile time. Run it with:
//   flutter test --dart-define=DEMO_MODE=true test/demo_mode_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/core/api_config.dart';
import 'package:mvec_mobile/features/marketplace/presentation/Screens/main_navigation.dart';
import 'package:mvec_mobile/main.dart';
import 'package:mvec_mobile/providers/auth_provider.dart';
import 'package:mvec_mobile/screens/layout/admin_shell.dart';
import 'package:mvec_mobile/screens/vendor/vendor_shell.dart';

void main() {
  // Without the define these cases would exercise the *real* login path and
  // hang on a network call, so skip the whole file.
  group('demo auth gate (--dart-define=DEMO_MODE=true)', () {
    test('demo login opens the app without a backend', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The real controller — no stub, no secure storage, no network.
      final controller = container.read(authControllerProvider.notifier);
      final ok = await controller.login('admin@gmail.com', 'anything');

      expect(ok, isTrue);
      final session = container.read(authControllerProvider).session;
      expect(session, isNotNull);
      expect(session!.token, 'demo-token');
    }, skip: !kDemoMode);

    testWidgets('an admin identity routes to the control center', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login('admin@gmail.com', 'anything');

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MvecApp()),
      );
      // The control center loads live providers, so its spinners never settle
      // in a test: pump a bounded number of frames instead of pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(AdminShell), findsOneWidget);
    }, skip: !kDemoMode);

    testWidgets('a buyer identity routes to the marketplace home feed', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login('buyer@example.com', 'anything');

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MvecApp()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsOneWidget);
    }, skip: !kDemoMode);

    testWidgets('a vendor identity opens the local vendor dashboard', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .login('vendor@umucyo.rw', 'anything');

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MvecApp()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(VendorShell), findsOneWidget);
      expect(find.text('VENDOR PORTAL'), findsOneWidget);
    }, skip: !kDemoMode);

    test('empty demo credentials are rejected', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ok = await container
          .read(authControllerProvider.notifier)
          .login('   ', '');

      expect(ok, isFalse);
      expect(container.read(authControllerProvider).session, isNull);
    }, skip: !kDemoMode);
  });
}
