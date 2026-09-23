// Smoke tests for the MVEC authentication flow (Login / Registration /
// Forgot password) and the routing + validation helpers behind it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mvec_mobile/main.dart';
import 'package:mvec_mobile/models/user.dart';
import 'package:mvec_mobile/providers/auth_provider.dart';
import 'package:mvec_mobile/screens/auth/auth_validation.dart';

void main() {
  // Keep widget tests offline and deterministic: never fetch fonts at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  group('validation helpers', () {
    test('email / phone validation', () {
      expect(validateEmailOrPhone(''), isNotNull);
      expect(validateEmailOrPhone('not-an-email'), isNotNull);
      expect(validateEmailOrPhone('72xxxxxx'), isNotNull);
      expect(validateEmailOrPhone('user@example.com'), isNull);
      expect(validateEmailOrPhone('+250791234567'), isNull);
      expect(validatePhone('abcd'), isNotNull);
      expect(validatePhone('+250 791 234 567'), isNull);
      expect(validateEmail(''), isNull);
      expect(validateEmail('bad'), isNotNull);
    });

    test('password validation', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('123'), isNotNull);
      expect(validatePassword('123456'), isNull);
      expect(validateConfirmPassword('123', '456'), isNotNull);
      expect(validateConfirmPassword('456', '456'), isNull);
    });

    test('full name and otp validation', () {
      expect(validateFullName('Narada'), isNotNull);
      expect(validateFullName('Narada Test'), isNull);
      expect(validateOtp('123'), isNotNull);
      expect(validateOtp('abcdef'), isNotNull);
      expect(validateOtp('123456'), isNull);
    });
  });

  group('role routing', () {
    test('super admin goes to control center', () {
      final admin = UserRecord(role: 'super_admin');
      expect(roleHome(admin), '/admin');
    });

    test('buyer, vendor, supplier and affiliate land on the home feed', () {
      for (final role in ['buyer', 'vendor', 'supplier', 'affiliate']) {
        expect(roleHome(UserRecord(role: role)), '/home', reason: role);
      }
    });
  });

  group('app boot', () {
    testWidgets('boots to the login screen', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Email or telephone'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('empty login submit shows validation errors',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email or telephone.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('invalid email shows a validation error', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'bad@email');
      await tester.enterText(find.byType(TextFormField).last, 'password1');
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });
  });

  group('registration', () {
    Future<void> openRegister(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Create one'));
      await tester.tap(find.text('Create one'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens from the login screen and shows four user types',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await openRegister(tester);

      expect(find.text('Create your account'), findsOneWidget);
      for (final role in ['Buyer', 'Vendor', 'Supplier', 'Affiliate']) {
        expect(find.text(role), findsOneWidget, reason: role);
      }
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Telephone'), findsOneWidget);
    });

    testWidgets('selecting a vendor shows the company field',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await openRegister(tester);

      expect(find.text('Company name'), findsNothing);

      await tester.tap(find.text('Vendor'));
      await tester.pumpAndSettle();

      expect(find.text('Company name'), findsOneWidget);
    });

    testWidgets('register validation catches missing and mismatched fields',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await openRegister(tester);

      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter your telephone number.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);

      // Field order for a buyer: name, telephone, email, password, confirm.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(3), 'password1');
      await tester.enterText(fields.at(4), 'password2');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });
  });

  group('forgot password', () {
    testWidgets('opens from login and renders the request form',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Forgot your password?'), findsOneWidget);
      expect(find.text('Email or telephone'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('validates the identity before sending', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: MvecApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email or telephone.'), findsOneWidget);
    });
  });
}