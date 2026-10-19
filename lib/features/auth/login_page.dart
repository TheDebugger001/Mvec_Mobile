import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/redirect.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

/// `/login` — email or phone plus password (`pages/Login.jsx`).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.next = ''});
  final String next;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String _error = '';

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_identity.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email or phone number and your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final user = await ref.read(authProvider.notifier).login(_identity.text.trim(), _password.text);
      if (mounted) context.go(afterSignIn(user, safeRedirect(widget.next)));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final notice = ref.watch(authProvider.select((a) => a.notice));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: const MvLogo(size: 26),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Welcome back', style: context.mvH1),
                    const SizedBox(height: 6),
                    Text('Log in to continue shopping or managing your store.', style: TextStyle(color: mv.textMuted)),
                    const SizedBox(height: 18),
                    if (notice != null && _error.isEmpty) Notice(text: notice),
                    if (_error.isNotEmpty) Notice(text: _error),
                    TextField(
                      controller: _identity,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email or phone number', hintText: 'you@example.com or 0788 123 456'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                          tooltip: _hide ? 'Show password' : 'Hide password',
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
                    ),
                    GradientButton(label: 'Log in', expand: true, loading: _busy, onPressed: _submit),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account?", style: TextStyle(color: mv.textMuted)),
                        TextButton(onPressed: () => context.push('/signup'), child: const Text('Create one')),
                      ],
                    ),
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
