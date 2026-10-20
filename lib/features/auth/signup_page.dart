import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/redirect.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

/// Account types (same as the web's Signup).
const _roles = <String, (String, String)>{
  'buyer': ('Buyer account', 'Browse products, place orders and manage your purchases.'),
  'vendor': ('Vendor account', 'Create a store, sell products and reach customers.'),
  'supplier': ('Supplier account', 'List wholesale products and reach customers.'),
  'affiliate': ('Affiliate account', 'Promote products and earn commission on qualifying sales.'),
};

/// `/signup` — phone-first registration (`pages/Signup.jsx`).
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key, this.role, this.next = ''});
  final String? role;
  final String next;

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late String _role = _roles.containsKey(widget.role) ? widget.role! : 'buyer';
  String _gender = '';
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _company, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().length < 2) return 'Please enter your full name.';
    if (!isRwandanPhone(_phone.text)) return 'Enter a Rwandan mobile number, for example 0788 123 456.';
    if (_email.text.trim().isNotEmpty && !isEmail(_email.text)) return 'Enter a valid email address or leave it empty.';
    if ((_role == 'vendor' || _role == 'supplier') && _company.text.trim().isEmpty) return 'Please enter your business name.';
    if (_password.text.length < 8) return 'Your password must be at least 8 characters.';
    if (_password.text != _confirm.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final user = await ref.read(authProvider.notifier).register(
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            gender: _gender,
            role: _role,
            companyName: _company.text.trim(),
            password: _password.text,
          );
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
    final info = _roles[_role]!;
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Join MVEC with your phone number. Email is optional.',
      children: [
        if (_error.isNotEmpty) Notice(text: _error),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 120,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(labelText: 'Full name', hintText: 'Enter your full name', counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(labelText: 'Telephone', hintText: '0788 123 456'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email (optional)', hintText: 'you@example.com'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Account type'),
          items: const [
            DropdownMenuItem(value: 'buyer', child: Text('Buyer')),
            DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
            DropdownMenuItem(value: 'supplier', child: Text('Supplier')),
            DropdownMenuItem(value: 'affiliate', child: Text('Affiliate marketer')),
          ],
          onChanged: (v) => setState(() => _role = v ?? 'buyer'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: const InputDecoration(labelText: 'Gender (optional)'),
          items: const [
            DropdownMenuItem(value: '', child: Text('Prefer not to say')),
            DropdownMenuItem(value: 'male', child: Text('Male')),
            DropdownMenuItem(value: 'female', child: Text('Female')),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
          onChanged: (v) => setState(() => _gender = v ?? ''),
        ),
        if (_role == 'vendor' || _role == 'supplier') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _company,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: _role == 'supplier' ? 'Business name' : 'Store / company name', hintText: 'Enter business name'),
          ),
        ],
        const SizedBox(height: 12),
        PasswordField(controller: _password, label: 'Create password', hint: 'At least 8 characters', autofill: AutofillHints.newPassword, action: TextInputAction.next),
        const SizedBox(height: 12),
        PasswordField(controller: _confirm, label: 'Verify password', hint: 'Confirm your password', autofill: AutofillHints.newPassword, onSubmitted: _submit),
        Container(
          margin: const EdgeInsets.only(top: 14, bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(10)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.radio_button_checked_rounded, size: 18, color: mv.accentDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.$1, style: TextStyle(fontWeight: FontWeight.w600, color: mv.text, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(info.$2, style: TextStyle(color: mv.textMuted, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
        GradientButton(label: 'Create account', expand: true, loading: _busy, onPressed: _submit),
        SwitchLine(
          text: 'Already have an account?',
          action: 'Log in',
          onTap: () => context.go('/login${widget.next.isEmpty ? '' : '?next=${Uri.encodeQueryComponent(widget.next)}'}'),
        ),
      ],
    );
  }
}
