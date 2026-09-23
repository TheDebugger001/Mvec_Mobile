// Smoke test: the admin console boots to the login screen with the
// frontend-style brand lockup.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/main.dart';

void main() {
  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MvecAdminApp()));

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ADMIN CONTROL'), findsOneWidget);
    expect(find.text('Email or telephone'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}