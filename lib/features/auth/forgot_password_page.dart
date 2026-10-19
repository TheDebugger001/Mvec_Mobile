import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/auth_api.dart';
import '../../core/api_client.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

/// `/forgot-password` — request a code, verify it, choose a new password
/// (`pages/ForgotPassword.jsx`). The account is found by email or phone.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _identity = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  int _step = 1;
  String _resetToken = '';
  String _message = '';
  String _error = '';
  String _devCode = '';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_identity, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = '';
      _message = '';
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        if (_identity.text.trim().isEmpty) {
          throw ApiException('Enter the email or phone number on your MVEC account.');
        }
        final res = await AuthApi.forgotPassword(_identity.text);
        setState(() {
          _devCode = '${res['devCode'] ?? ''}';
          _code.clear();
          _step = 2;
          _message = '${res['message'] ?? 'If an account uses ${_identity.text.trim()}, we sent it a 6-digit code.'}';
        });
      });

  Future<void> _verify() => _run(() async {
        if (_code.text.trim().length != 6) throw ApiException('Enter the complete 6-digit code.');
        final token = await AuthApi.verifyResetOtp(_identity.text, _code.text.trim());
        setState(() {
          _resetToken = token;
          _step = 3;
          _message = 'Code verified. Choose your new password.';
        });
      });

  Future<void> _reset() => _run(() async {
        if (_password.text.length < 8) throw ApiException('Your new password must contain at least 8 characters.');
        if (_password.text != _confirm.text) throw ApiException('The passwords do not match.');
        await AuthApi.resetPassword(_resetToken, _password.text);
        if (!mounted) return;
        setState(() => _message = 'Password reset. You were signed out on other devices. Log in with your new password.');
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        if (mounted) context.go('/login');
      });

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'Step $_step of 3',
      children: [
        if (_message.isNotEmpty) Notice(text: _message, ok: true),
        if (_error.isNotEmpty) Notice(text: _error),
        if (_step == 1) ...[
          TextField(
            controller: _identity,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email or phone number', hintText: 'you@example.com or 0788 123 456'),
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: 14),
          GradientButton(label: 'Send code', expand: true, loading: _busy, onPressed: _sendCode),
        ],
        if (_step == 2) ...[
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
            onSubmitted: (_) => _verify(),
          ),
          if (_devCode.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Development code: $_devCode', style: const TextStyle(fontSize: 12))),
          const SizedBox(height: 14),
          GradientButton(label: 'Verify code', expand: true, loading: _busy, onPressed: _verify),
          TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Send a new code')),
        ],
        if (_step == 3) ...[
          PasswordField(controller: _password, label: 'New password', hint: 'At least 8 characters', action: TextInputAction.next),
          const SizedBox(height: 12),
          PasswordField(controller: _confirm, label: 'Confirm new password', onSubmitted: _reset),
          const SizedBox(height: 14),
          GradientButton(label: 'Reset password', expand: true, loading: _busy, onPressed: _reset),
        ],
        SwitchLine(text: 'Remembered it?', action: 'Log in', onTap: () => context.go('/login')),
      ],
    );
  }
}
