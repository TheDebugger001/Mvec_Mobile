import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/auth_api.dart';
import '../../core/api_client.dart';
import '../../core/redirect.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

/// `/login` — email or phone plus password, or a one-time code to the phone for
/// people who ordered as a guest (`pages/Login.jsx`).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.next = '', this.checkout = false});
  final String next;
  final bool checkout;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String _error = '';
  bool _codeMode = false;
  bool _codeSent = false;
  String _sentTo = '';

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _returnTo => safeRedirect(widget.next);

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() => _run(() async {
        if (_identity.text.trim().isEmpty || _password.text.isEmpty) {
          throw ApiException('Enter your email or phone number and your password.');
        }
        final user = await ref.read(authProvider.notifier).login(_identity.text.trim(), _password.text);
        ref.read(authProvider.notifier).clearNotice();
        if (mounted) context.go(afterSignIn(user, _returnTo));
      });

  Future<void> _sendCode() => _run(() async {
        if (_phone.text.trim().isEmpty) throw ApiException('Enter your phone number.');
        try {
          final res = await AuthApi.guestSendCode(_phone.text.trim());
          if (mounted) setState(() => _sentTo = '${res['message'] ?? ''}');
        } on ApiException catch (e) {
          // A code sent less than a minute ago is still valid.
          if (e.statusCode != 429) rethrow;
        }
        if (mounted) setState(() => _codeSent = true);
      });

  Future<void> _verifyCode() => _run(() async {
        try {
          final session = await AuthApi.guestVerify(phone: _phone.text.trim(), code: _code.text.trim());
          final user = await ref.read(authProvider.notifier).startSession(session);
          if (mounted) context.go(afterSignIn(user, _returnTo.isEmpty ? '/orders' : _returnTo));
        } on ApiException catch (e) {
          if (RegExp('full name', caseSensitive: false).hasMatch(e.message)) {
            throw ApiException('No order or account uses this number yet. Shop and check out to get started.');
          }
          rethrow;
        }
      });

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(authProvider.select((a) => a.notice));
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: widget.checkout
          ? 'Log in to finish your order. Your cart is kept.'
          : 'Log in to continue shopping or managing your store.',
      children: [
        if (notice != null && _error.isEmpty) Notice(text: notice),
        if (_error.isNotEmpty) Notice(text: _error),
        if (!_codeMode) ...[
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _identity,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email or phone number', hintText: 'you@example.com or 0788 123 456'),
                ),
                const SizedBox(height: 12),
                PasswordField(controller: _password, label: 'Password', hint: 'Enter your password', autofill: AutofillHints.password, onSubmitted: _login),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
          ),
          GradientButton(label: 'Log in', expand: true, loading: _busy, onPressed: _login),
          SwitchLine(
            text: 'Ordered as a guest?',
            action: 'Log in with a code',
            onTap: () => setState(() {
              _codeMode = true;
              _error = '';
            }),
          ),
        ] else ...[
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (_) => setState(() => _codeSent = false),
            decoration: const InputDecoration(labelText: 'Phone number', hintText: '0788 123 456'),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
            ),
          ],
          if (_codeSent && _sentTo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_sentTo, style: TextStyle(fontSize: 12, color: context.mv.textMuted))),
          const SizedBox(height: 14),
          GradientButton(label: _codeSent ? 'Log in' : 'Send me a code', expand: true, loading: _busy, onPressed: _codeSent ? _verifyCode : _sendCode),
          TextButton(
            onPressed: () => setState(() {
              _codeMode = false;
              _codeSent = false;
              _error = '';
            }),
            child: const Text('Use my password instead'),
          ),
        ],
        SwitchLine(
          text: "Don't have an account?",
          action: 'Create one',
          onTap: () => context.push('/signup${_returnTo.isEmpty ? '' : '?next=${Uri.encodeQueryComponent(_returnTo)}'}'),
        ),
      ],
    );
  }
}
