import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/auth_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

/// `/orders` and `/orders/:id` while signed out: follow an order with the
/// phone it was placed with (guests and regular buyers). A text code proves
/// the phone, then [child] shows (web: `FollowOrders` in `pages/Orders.jsx`).
class OrdersGate extends ConsumerWidget {
  const OrdersGate({super.key, required this.child, this.framed = false});
  final Widget child;

  /// Outside the shop's bottom-bar shell (an order page): adds its own app bar.
  final bool framed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.user != null) return child;
    final body = auth.restoring ? const LoadingState() : const FollowOrders();
    return framed ? Scaffold(appBar: AppBar(title: const Text('Your order')), body: body) : body;
  }
}

class FollowOrders extends ConsumerStatefulWidget {
  const FollowOrders({super.key});

  @override
  ConsumerState<FollowOrders> createState() => _FollowOrdersState();
}

class _FollowOrdersState extends ConsumerState<FollowOrders> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _note;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        if (!RegExp(r'^(\+?250|0)?7[2389]\d{7}$').hasMatch(_phone.text.replaceAll(RegExp(r'[\s-]'), ''))) {
          throw ApiException('Enter the phone number you ordered with (07…).');
        }
        final r = await AuthApi.guestSendCode(_phone.text.trim());
        setState(() {
          _sent = true;
          _note = strOf(r['message'], 'We sent you a 6-digit code.');
        });
      });

  Future<void> _verify() => _run(() async {
        if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) throw ApiException('Enter the 6-digit code.');
        final session = await AuthApi.guestVerify(phone: _phone.text.trim(), code: _code.text.trim(), track: true);
        await ref.read(authProvider.notifier).startSession(session);
      });

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Text('MY ORDERS', style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: mv.textMuted)),
        const SizedBox(height: 6),
        Text('Follow your order', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text("Enter the phone number you ordered with. We'll text you a code, then show your orders and where each parcel is.", style: TextStyle(color: mv.textMuted, height: 1.4)),
        const SizedBox(height: 18),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Notice(text: _error!)),
        if (!_sent) ...[
          TextField(controller: _phone, keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber], decoration: const InputDecoration(labelText: 'Phone number', hintText: '07xx xxx xxx')),
          const SizedBox(height: 14),
          GradientButton(label: 'Text me a code', expand: true, loading: _busy, onPressed: _busy ? null : _send),
        ] else ...[
          if (_note != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Notice(info: true, text: _note!)),
          TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, autofillHints: const [AutofillHints.oneTimeCode], decoration: const InputDecoration(labelText: '6-digit code', counterText: '')),
          const SizedBox(height: 14),
          GradientButton(label: 'Show my orders', expand: true, loading: _busy, onPressed: _busy ? null : _verify),
          TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _code.clear(); _note = null; }), child: const Text('Use another number')),
        ],
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: () => context.push('/login?next=/orders'), child: const Text('Have a password? Sign in instead'))),
      ],
    );
  }
}
