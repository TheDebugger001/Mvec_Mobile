import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

/// `/admin/become-seller` — open a storefront while staying admin.
class AdminBecomeSellerPage extends ConsumerStatefulWidget {
  const AdminBecomeSellerPage({super.key});

  @override
  ConsumerState<AdminBecomeSellerPage> createState() => _AdminBecomeSellerPageState();
}

class _AdminBecomeSellerPageState extends ConsumerState<AdminBecomeSellerPage> {
  late final _user = ref.read(authProvider).user;
  late final _c = {
    'businessName': TextEditingController(),
    'phone': TextEditingController(text: _user?.telephone ?? ''),
    'email': TextEditingController(text: _user?.email ?? ''),
    'description': TextEditingController(),
  };
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await jpost('/vendors/become-seller', {for (final e in _c.entries) e.key: e.value.text.trim()});
      await ref.read(authProvider.notifier).refresh();
      if (mounted) context.go('/vendor');
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        toast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final already = ref.watch(authProvider.select((a) => a.user?.isSellerEnabled ?? false));
    return PortalPage(
      eyebrow: 'Seller mode',
      title: 'Become a Seller',
      subtitle: 'Open your own vendor storefront on Ikiguzi while keeping full Super Administrator access. Your admin role and permissions never change.',
      children: [
        if (already)
          InfoBox(
            title: "You're already selling on Ikiguzi",
            text: 'Your vendor storefront is active. Jump into your seller dashboard to manage products, orders and payouts.',
            child: GradientButton(label: 'Go to my Seller Dashboard', icon: Icons.grid_view_rounded, compact: true, onPressed: () => context.go('/vendor')),
          )
        else
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error.isNotEmpty) Notice(text: _error),
                TextField(controller: _c['businessName'], decoration: const InputDecoration(labelText: 'Business / store name', hintText: 'e.g. Ikiguzi Official Store')),
                const SizedBox(height: 10),
                TextField(controller: _c['phone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Business phone', hintText: '0788123456')),
                const SizedBox(height: 10),
                TextField(controller: _c['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Business email', hintText: 'store@example.com')),
                const SizedBox(height: 10),
                TextField(
                  controller: _c['description'],
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Short description (optional)', hintText: 'What will you sell on Ikiguzi?'),
                ),
                const SizedBox(height: 12),
                GradientButton(label: 'Activate Seller Mode', loading: _busy, onPressed: _submit),
              ],
            ),
          ),
      ],
    );
  }
}
