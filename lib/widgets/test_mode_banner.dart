import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/payment_mode.dart';

/// A gold strip on the storefront while payments are simulated, so nobody
/// mistakes a test order for a real purchase (the website's `TestModeBanner`).
class TestModeBanner extends ConsumerWidget {
  const TestModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(paymentTestModeProvider).valueOrNull != true) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Test mode',
      child: Container(
        width: double.infinity,
        color: const Color(0xFFC98A0C),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'TEST MODE  ', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .5)),
            TextSpan(text: 'Payments are simulated: no money is taken and orders are not delivered.'),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF1D1300), fontSize: 12, height: 1.35),
        ),
      ),
    );
  }
}
