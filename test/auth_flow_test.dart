import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

Future<void> openLogin(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Sign in or create an account'));
  await settle(tester, frames: 4);
  await tester.tap(find.text('Sign in').last);
  await settle(tester);
}

void main() {
  testWidgets('guest tapping Orders is sent to sign in, and a buyer can log in', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'POST /auth/login': (c) => (200, {'token': 'jwt-1', 'user': userJson('buyer')}),
      'GET /auth/me': (_) => (200, {'user': userJson('buyer')}),
      'GET /orders/my-orders': (_) => (200, {'orders': []}),
    });
    await pumpApp(tester, backend);

    await tester.tap(find.text('Orders'));
    await settle(tester);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(field('Email or phone number'), 'aline@mvec.rw');
    await tester.enterText(field('Password'), 'Secret@123');
    await tester.tap(find.text('Log in').last);
    await settle(tester, frames: 20);

    final login = backend.where('POST', '/auth/login').single;
    expect(login.body, {'email': 'aline@mvec.rw', 'password': 'Secret@123'});
    // Back on the page the guest was trying to reach, now signed in.
    expect(find.text('My orders'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);
    expect(find.byTooltip('Sign in or create an account'), findsNothing);
  });

  testWidgets('a phone number is sent as `phone`, and a wrong password shows the server message', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'POST /auth/login': (_) => (401, {'message': 'Invalid credentials'}),
    });
    await pumpApp(tester, backend);
    await openLogin(tester);
    await tester.enterText(field('Email or phone number'), '0788123456');
    await tester.enterText(field('Password'), 'nope');
    await tester.tap(find.text('Log in').last);
    await settle(tester);
    expect(backend.where('POST', '/auth/login').single.body, {'phone': '0788123456', 'password': 'nope'});
    expect(find.text('Invalid credentials'), findsOneWidget);
  });

  testWidgets('a vendor who logs in lands on the vendor dashboard route', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'POST /auth/login': (_) => (200, {'token': 'jwt-v', 'user': userJson('vendor', name: 'Kigali Gadgets')}),
      'GET /auth/me': (_) => (200, {'user': userJson('vendor')}),
    });
    await pumpApp(tester, backend);
    await openLogin(tester);
    await tester.enterText(field('Email or phone number'), 'v@mvec.rw');
    await tester.enterText(field('Password'), 'Vendor@123');
    await tester.tap(find.text('Log in').last);
    await settle(tester, frames: 20);
    expect(find.text('Dashboard coming next'), findsOneWidget);
  });

  testWidgets('sign-up validates, then registers with the backend payload', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'POST /auth/register': (_) => (201, {'token': 'jwt-n', 'user': userJson('buyer', name: 'New Buyer')}),
      'GET /auth/me': (_) => (200, {'user': userJson('buyer')}),
    });
    await pumpApp(tester, backend);
    await openLogin(tester);
    await tester.tap(find.text('Create one'));
    await settle(tester);
    expect(find.text('Create your account'), findsOneWidget);

    // Empty form.
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await settle(tester, frames: 3);
    expect(find.text('Please enter your full name.'), findsOneWidget);

    await tester.enterText(field('Full name'), 'New Buyer');
    await tester.enterText(field('Telephone'), '12345');
    await tester.tap(find.text('Create account'));
    await settle(tester, frames: 3);
    expect(find.text('Enter a Rwandan mobile number, for example 0788 123 456.'), findsOneWidget);

    await tester.enterText(field('Telephone'), '0788 123 456');
    await tester.enterText(field('Create password'), 'Secret@123');
    await tester.enterText(field('Verify password'), 'Different1');
    await tester.tap(find.text('Create account'));
    await settle(tester, frames: 3);
    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(field('Verify password'), 'Secret@123');
    await tester.tap(find.text('Create account'));
    await settle(tester, frames: 20);
    final body = backend.where('POST', '/auth/register').single.body as Map;
    expect(body['Fullname'], 'New Buyer');
    expect(body['phone'], '0788 123 456');
    expect(body['role'], 'buyer');
    expect(body['password'], 'Secret@123');
    expect(find.byTooltip('Account'), findsOneWidget);
  });

  testWidgets('forgot password walks through code, verification and reset', (tester) async {
    final backend = FakeBackend({
      ...baseRoutes(),
      'POST /auth/forgot-password': (_) => (200, {'message': 'Code sent.'}),
      'POST /auth/verify-reset-otp': (_) => (200, {'resetToken': 'tok-1'}),
      'POST /auth/reset-password': (_) => (200, {'message': 'ok'}),
    });
    await pumpApp(tester, backend);
    await openLogin(tester);
    await tester.tap(find.text('Forgot password?'));
    await settle(tester);

    await tester.enterText(field('Email or phone number'), 'aline@mvec.rw');
    await tester.tap(find.text('Send code'));
    await settle(tester);
    expect(backend.where('POST', '/auth/forgot-password').single.body, {'email': 'aline@mvec.rw'});
    expect(find.text('Step 2 of 3'), findsOneWidget);

    await tester.enterText(field('6-digit code'), '123456');
    await tester.tap(find.text('Verify code'));
    await settle(tester);
    expect(backend.where('POST', '/auth/verify-reset-otp').single.body, {'email': 'aline@mvec.rw', 'code': '123456'});

    await tester.enterText(field('New password'), 'Brand@New1');
    await tester.enterText(field('Confirm new password'), 'Brand@New1');
    await tester.tap(find.text('Reset password'));
    await settle(tester, frames: 25);
    expect(backend.where('POST', '/auth/reset-password').single.body, {'resetToken': 'tok-1', 'newPassword': 'Brand@New1'});
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
