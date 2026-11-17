import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/auth_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/user.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'rider_api.dart';

/// `/rider`: riders sign in, or sign up, with their phone and a text-message
/// code (as KitchenLink's delivery workers do). A new rider waits for Ikiguzi's
/// approval before taking deliveries.
class RiderAuthPage extends ConsumerStatefulWidget {
  const RiderAuthPage({super.key, this.signUp = false, this.name = '', this.phone = ''});

  /// Opened from the sign-up page's "Delivery worker" choice: sign-up mode, details carried over.
  final bool signUp;
  final String name;
  final String phone;

  @override
  ConsumerState<RiderAuthPage> createState() => _RiderAuthPageState();
}

class _RiderAuthPageState extends ConsumerState<RiderAuthPage> {
  late bool _signUp = widget.signUp;
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String _vehicle = 'MOTORBIKE';
  late final _phone = TextEditingController(text: widget.phone);
  final _code = TextEditingController();
  late final _name = TextEditingController(text: widget.name);
  final _plate = TextEditingController();

  static const _vehicles = {'MOTORBIKE': 'Motorbike', 'BICYCLE': 'Bicycle', 'CAR': 'Car', 'ON_FOOT': 'On foot'};

  @override
  void dispose() {
    for (final c in [_phone, _code, _name, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _go(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _go(() async {
        if (_signUp && _name.text.trim().length < 3) throw ApiException('Enter your full name.');
        await RiderApi.sendCode(_phone.text.trim(), signUp: _signUp);
        setState(() => _codeSent = true);
      });

  Future<void> _verify() => _go(() async {
        final reply = _signUp
            ? await RiderApi.signUp(phone: _phone.text.trim(), code: _code.text.trim(), fullName: _name.text.trim(), vehicleType: _vehicle, plateNumber: _plate.text.trim())
            : await RiderApi.signIn(_phone.text.trim(), _code.text.trim());
        final user = AppUser.fromJson(asMap(reply['user']));
        if (user.role != 'delivery') throw ApiException('This phone number belongs to a ${user.role} account. Use the normal sign-in instead.');
        await ref.read(authProvider.notifier).startSession(AuthSession(strOf(reply['token']), user));
        if (mounted) context.go('/delivery');
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Deliver with Ikiguzi')),
        body: PortalPage(
          title: _signUp ? 'Become a rider' : 'Rider sign in',
          subtitle: _signUp ? 'Deliver parcels near you and keep the whole delivery fee.' : 'We text a 6-digit code to your phone.',
          children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Sign in')), ButtonSegment(value: true, label: Text('Sign up'))],
              selected: {_signUp},
              onSelectionChanged: _busy ? null : (v) => setState(() {
                _signUp = v.first;
                _codeSent = false;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_error != null) Notice(text: _error!),
            if (_signUp) ...[
              TextField(controller: _name, enabled: !_codeSent, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _vehicle,
                decoration: const InputDecoration(labelText: 'How you deliver'),
                items: [for (final e in _vehicles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: _codeSent ? null : (v) => setState(() => _vehicle = v ?? 'MOTORBIKE'),
              ),
              if (_vehicle == 'MOTORBIKE' || _vehicle == 'CAR') ...[
                const SizedBox(height: 10),
                TextField(controller: _plate, enabled: !_codeSent, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Plate number')),
              ],
              const SizedBox(height: 10),
            ],
            TextField(controller: _phone, enabled: !_codeSent, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', hintText: '07xx xxx xxx')),
            if (_codeSent) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                onSubmitted: (_) => _verify(),
              ),
            ],
            const SizedBox(height: 14),
            GradientButton(
              label: !_codeSent ? 'Send code' : (_signUp ? 'Create rider account' : 'Sign in'),
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
            ),
            if (_codeSent)
              TextButton(onPressed: _busy ? null : () => setState(() => _codeSent = false), child: const Text('Change the phone number')),
          ],
        ),
      );
}
