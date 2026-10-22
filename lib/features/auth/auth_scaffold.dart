import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/theme_switch.dart';

/// Frame shared by the sign-in, sign-up and password-reset screens.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const MvLogo(size: 24),
        actions: const [ThemeSwitch(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              // The form slides in from the side, one row after another.
              child: SlideInColumn(
                children: [
                  Text(title, style: context.mvH1),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: mv.textMuted, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 18),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password input with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, required this.label, this.hint, this.autofill, this.onSubmitted, this.action});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? autofill;
  final VoidCallback? onSubmitted;
  final TextInputAction? action;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hide = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hide,
      autofillHints: widget.autofill == null ? null : [widget.autofill!],
      textInputAction: widget.action,
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixIcon: IconButton(
          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
          tooltip: _hide ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _hide = !_hide),
        ),
      ),
    );
  }
}

/// "Already have an account? Log in" style footer line.
class SwitchLine extends StatelessWidget {
  const SwitchLine({super.key, required this.text, required this.action, required this.onTap});
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(text, style: TextStyle(color: context.mv.textMuted, fontSize: 13)),
            TextButton(onPressed: onTap, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 32)), child: Text(action)),
          ],
        ),
      );
}
