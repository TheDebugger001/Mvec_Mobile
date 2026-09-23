import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_config.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email/phone and password.');
      return;
    }
    setState(() => _error = null);
    final ok = await ref.read(authControllerProvider.notifier).login(_email.text.trim(), _password.text);
    if (!mounted) return;
    if (ok) {
      final user = ref.read(authControllerProvider).session?.user;
      if (user?.role != 'super_admin') {
        await ref.read(authControllerProvider.notifier).logout();
        if (mounted) setState(() => _error = 'This account is not a Super Administrator.');
        return;
      }
      context.go('/admin');
    } else {
      setState(() => _error = ref.read(authControllerProvider).error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider.select((s) => s.loading));
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: MvColors.gradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 40, offset: const Offset(0, 20))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Text('MVEC', style: TextStyle(fontFamily: 'Manrope', fontSize: 34, fontWeight: FontWeight.w800, foreground: Paint()..shader = MvColors.gradient.createShader(const Rect.fromLTWH(0, 0, 120, 40)))),
                    ),
                    const SizedBox(height: 2),
                    Center(
                      child: Text('ADMIN CONTROL', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.8, color: MvColors.muted)),
                    ),
                    const SizedBox(height: 28),
                    Text('Sign in', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Access the MVEC marketplace control center.', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 22),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: MvColors.errorBg, borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: MvColors.errorText),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: MvColors.errorText, fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _field('Email or telephone', _email, icon: Icons.person_outline, hint: 'admin@gmail.com'),
                    const SizedBox(height: 14),
                    _field(
                      'Password',
                      _password,
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      hint: '••••••••',
                      suffix: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20), onPressed: () => setState(() => _obscure = !_obscure)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          height: 32,
                          child: Checkbox(
                            value: _remember,
                            onChanged: (v) => setState(() => _remember = v ?? true),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('Remember me', style: TextStyle(fontSize: 12.5)),
                        const Spacer(),
                        TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?', style: TextStyle(fontSize: 12.5))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GradientButton(label: loading ? 'Signing in…' : 'Sign in', onPressed: loading ? null : _submit, expanded: true, icon: 'arrow'),
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/'),
                        child: const Text('← Back to home', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (!kReleaseMode) ...[
                      const Divider(),
                      const SizedBox(height: 6),
                      Text('Dev quick login', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: loading
                            ? null
                            : () async {
                                _email.text = kAdminEmail;
                                _password.text = kAdminPassword;
                                await _submit();
                              },
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                        icon: const Icon(Icons.flash_on, size: 16),
                        label: const Text('Fill admin credentials'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {required IconData icon, String? hint, bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 0),
        suffixIcon: suffix,
      ),
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your account email.');
      return;
    }
    setState(() => _error = null);
    final ok = await ref.read(authControllerProvider.notifier).forgotPassword(_email.text.trim());
    if (!mounted) return;
    if (ok) {
      showMvSnack(context, 'Reset link sent. Check your email.', success: true);
      Navigator.of(context).pop();
    } else {
      setState(() => _error = ref.read(authControllerProvider).error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  children: [
                    Text('Forgot password', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('We will send a reset link to your email.', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: MvColors.errorBg, borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!, style: const TextStyle(fontSize: 12, color: MvColors.errorText, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline, size: 20)),
                    ),
                    const SizedBox(height: 18),
                    GradientButton(label: 'Send reset link', onPressed: _submit, expanded: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}