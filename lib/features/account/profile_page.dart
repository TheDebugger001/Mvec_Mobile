import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/auth_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/locations.dart';
import '../../core/nav_items.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

const _roleLabel = {'buyer': 'Buyer', 'vendor': 'Vendor', 'supplier': 'Supplier', 'affiliate': 'Affiliate', 'super_admin': 'Super Admin', 'delivery': 'Delivery'};
const _addressTypes = [('HOME', 'Home'), ('OFFICE', 'Office'), ('PARENTS', 'Family'), ('OTHER', 'Other')];

/// `/profile` — account details and photo, saved addresses, password and
/// sign-out (`pages/Profile.jsx`).
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _editing = false;
  bool _busy = false;
  bool _uploading = false;
  ({bool ok, String text})? _notice;
  final _name = TextEditingController();
  final _email = TextEditingController();
  String _gender = '';

  List<Map<String, dynamic>> _addresses = const [];
  bool _addrLoading = true;

  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _pwBusy = false;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    try {
      final a = await AuthApi.addresses();
      if (mounted) setState(() => _addresses = a);
    } catch (_) {
      // Addresses are optional here; the list just stays empty.
    } finally {
      if (mounted) setState(() => _addrLoading = false);
    }
  }

  void _startEdit() {
    final u = ref.read(authProvider).user!;
    _name.text = u.fullName;
    _email.text = u.email;
    _gender = u.gender;
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _notice = (ok: false, text: 'Please enter your full name.'));
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final u = await AuthApi.updateProfile(fullName: _name.text.trim(), email: _email.text.trim(), gender: _gender);
      ref.read(authProvider.notifier).setUser(u);
      setState(() {
        _editing = false;
        _notice = (ok: true, text: 'Your details were saved.');
      });
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (file == null) return;
    if (await file.length() > 2 * 1024 * 1024) {
      setState(() => _notice = (ok: false, text: 'Your photo must be 2 MB or smaller.'));
      return;
    }
    setState(() {
      _uploading = true;
      _notice = null;
    });
    try {
      final url = await AuthApi.uploadAvatar(file);
      final u = ref.read(authProvider).user!;
      ref.read(authProvider.notifier).setUser(u.copyWith(avatarUrl: url));
      setState(() => _notice = (ok: true, text: 'Profile photo updated.'));
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_new.text.length < 8) {
      setState(() => _notice = (ok: false, text: 'Your new password must be at least 8 characters.'));
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _notice = (ok: false, text: 'The new passwords do not match.'));
      return;
    }
    setState(() {
      _pwBusy = true;
      _notice = null;
    });
    try {
      final token = await AuthApi.changePassword(_current.text, _new.text);
      if (token != null) await ref.read(authProvider.notifier).replaceToken(token);
      _current.clear();
      _new.clear();
      _confirm.clear();
      setState(() => _notice = (ok: true, text: 'Password changed. Other devices were signed out.'));
    } catch (e) {
      setState(() => _notice = (ok: false, text: errorText(e)));
    } finally {
      if (mounted) setState(() => _pwBusy = false);
    }
  }

  Future<void> _editAddress([Map<String, dynamic>? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressSheet(existing: existing),
    );
    if (saved == true) _loadAddresses();
  }

  Future<void> _deleteAddress(Map<String, dynamic> a) async {
    if (!await confirmDialog(context, 'Delete this address?', confirm: 'Delete', danger: true)) return;
    try {
      await AuthApi.removeAddress(strOf(a['_id']));
      _loadAddresses();
    } catch (e) {
      if (mounted) setState(() => _notice = (ok: false, text: errorText(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final user = ref.watch(authProvider.select((a) => a.user));
    if (user == null) return const SizedBox.shrink();
    final dashboard = roleHome[user.role];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const PageTitle(eyebrow: 'Account', title: 'My account'),
        if (_notice != null) Notice(text: _notice!.text, ok: _notice!.ok, onClose: () => setState(() => _notice = null)),
        DataCard(
          child: Column(
            children: [
              Avatar(name: user.fullName, url: user.avatarUrl, radius: 36),
              TextButton(onPressed: _uploading ? null : _pickPhoto, child: Text(_uploading ? 'Uploading…' : 'Change photo')),
              if (_editing) ...[
                TextField(controller: _name, textCapitalization: TextCapitalization.words, maxLength: 120, decoration: const InputDecoration(labelText: 'Full name', counterText: '')),
                const SizedBox(height: 10),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional)')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Gender (optional)'),
                  items: const [DropdownMenuItem(value: '', child: Text('Prefer not to say')), DropdownMenuItem(value: 'male', child: Text('Male')), DropdownMenuItem(value: 'female', child: Text('Female')), DropdownMenuItem(value: 'other', child: Text('Other'))],
                  onChanged: (v) => setState(() => _gender = v ?? ''),
                ),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: GradientButton(label: 'Save', compact: true, loading: _busy, onPressed: _save)), const SizedBox(width: 8), Expanded(child: OutlineBtn(label: 'Cancel', compact: true, onPressed: () => setState(() => _editing = false)))]),
              ] else ...[
                Text(user.fullName, style: context.mvH1.copyWith(fontSize: 17)),
                if (user.email.isNotEmpty) Text(user.email, style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                const SizedBox(height: 6),
                StatusChip(_roleLabel[user.role] ?? statusLabel(user.role)),
                const SizedBox(height: 8),
                Text('${user.gender.isEmpty ? 'Gender not specified' : statusLabel(user.gender)}  ·  ${user.telephone.isEmpty ? 'No phone number' : user.telephone}', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                const SizedBox(height: 10),
                OutlineBtn(label: 'Edit details', compact: true, onPressed: _startEdit),
                const SizedBox(height: 6),
                Text('Your phone number is your sign-in. Contact support to change it.', style: TextStyle(color: mv.textMuted, fontSize: 11)),
              ],
            ],
          ),
        ),
        if (dashboard != null) DataCard(child: Row(children: [Expanded(child: Text('Your workspace', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text))), GradientButton(label: 'Open dashboard', compact: true, onPressed: () => context.go(dashboard))])),
        DataCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Expanded(child: Text('Saved addresses', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text))), TextButton(onPressed: () => _editAddress(), child: const Text('+ Add'))]),
              if (_addrLoading) const LoadingState(),
              if (!_addrLoading && _addresses.isEmpty) Text('No saved addresses yet. Add one to speed up checkout.', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
              for (final a in _addresses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.location_on_outlined, color: mv.accentDeep, size: 22),
                  title: Text('${strOf(a['type'], 'Address')}${a['isDefaultShipping'] == true ? ' · Default' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text([a['street'], a['sector'], a['cityDistrict'], a['provinceState']].where((e) => strOf(e).isNotEmpty).join(', '), style: const TextStyle(fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit_outlined, size: 19), tooltip: 'Edit', onPressed: () => _editAddress(a)), IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 19), tooltip: 'Delete', onPressed: () => _deleteAddress(a))]),
                ),
            ],
          ),
        ),
        if (user.hasPassword)
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Change password', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                const SizedBox(height: 10),
                TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
                const SizedBox(height: 10),
                TextField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'New password', hintText: 'At least 8 characters')),
                const SizedBox(height: 10),
                TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
                const SizedBox(height: 12),
                GradientButton(label: 'Update password', compact: true, loading: _pwBusy, onPressed: _changePassword),
              ],
            ),
          ),
        OutlineBtn(
          label: 'Sign out of all devices',
          expand: true,
          onPressed: () async {
            if (!await confirmDialog(context, 'Sign out everywhere, including this phone?', confirm: 'Sign out')) return;
            try {
              await AuthApi.logoutAll();
            } catch (_) {
              // Signing out locally still works if the server call fails.
            }
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/');
          },
        ),
        const SizedBox(height: 10),
        SolidButton(
          label: 'Sign out',
          expand: true,
          color: MvColors.dangerBtn,
          onPressed: () async {
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/');
          },
        ),
      ],
    );
  }
}

class _AddressSheet extends StatefulWidget {
  const _AddressSheet({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late String _type = strOf(widget.existing?['type'], 'HOME');
  late String _province = provinces.contains(strOf(widget.existing?['provinceState'])) ? strOf(widget.existing?['provinceState']) : 'Kigali City';
  late String _district = strOf(widget.existing?['cityDistrict']);
  late final _sector = TextEditingController(text: strOf(widget.existing?['sector']));
  late final _street = TextEditingController(text: strOf(widget.existing?['street']));
  late final _building = TextEditingController(text: strOf(widget.existing?['building']));
  late final _phone = TextEditingController(text: strOf(widget.existing?['phone']));
  late final _notes = TextEditingController(text: strOf(widget.existing?['deliveryInstructions']));
  late bool _default = widget.existing?['isDefaultShipping'] == true;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_sector, _street, _building, _phone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(rwandaLocations[_province]?.contains(_district) ?? false)) {
      setState(() => _error = 'Choose your district.');
      return;
    }
    if (_street.text.trim().length < 3) {
      setState(() => _error = 'Enter your street, house number or a nearby landmark.');
      return;
    }
    if (_phone.text.trim().isNotEmpty && !isRwandanPhone(_phone.text)) {
      setState(() => _error = 'Enter a Rwandan mobile number or leave it empty.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final body = {
      'type': _type,
      'country': 'Rwanda',
      'provinceState': _province,
      'cityDistrict': _district,
      'sector': _sector.text.trim(),
      'street': _street.text.trim(),
      'building': _building.text.trim(),
      'phone': _phone.text.trim(),
      'deliveryInstructions': _notes.text.trim(),
      'isDefaultShipping': _default,
    };
    try {
      if (widget.existing == null) {
        await AuthApi.addAddress(body);
      } else {
        await AuthApi.updateAddress(strOf(widget.existing!['_id']), body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add address' : 'Edit address', style: context.mvH1.copyWith(fontSize: 17)),
            const SizedBox(height: 12),
            if (_error.isNotEmpty) Notice(text: _error),
            DropdownButtonFormField<String>(initialValue: _type, decoration: const InputDecoration(labelText: 'Type'), items: [for (final t in _addressTypes) DropdownMenuItem(value: t.$1, child: Text(t.$2))], onChanged: (v) => setState(() => _type = v ?? 'HOME')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(initialValue: _province, isExpanded: true, decoration: const InputDecoration(labelText: 'Province / City'), items: [for (final p in provinces) DropdownMenuItem(value: p, child: Text(p))], onChanged: (v) => setState(() {
                  _province = v ?? _province;
                  _district = '';
                })),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey('d$_province$_district'),
              initialValue: _district.isEmpty ? null : _district,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'District'),
              items: [for (final d in rwandaLocations[_province] ?? const <String>[]) DropdownMenuItem(value: d, child: Text(d))],
              onChanged: (v) => setState(() => _district = v ?? ''),
            ),
            const SizedBox(height: 10),
            TextField(controller: _sector, decoration: const InputDecoration(labelText: 'Sector (optional)')),
            const SizedBox(height: 10),
            TextField(controller: _street, decoration: const InputDecoration(labelText: 'Street / landmark')),
            const SizedBox(height: 10),
            TextField(controller: _building, decoration: const InputDecoration(labelText: 'Building / apartment (optional)')),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
            const SizedBox(height: 10),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Delivery instructions (optional)')),
            CheckboxListTile(value: _default, onChanged: (v) => setState(() => _default = v ?? false), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('Use as my default delivery address', style: TextStyle(fontSize: 13))),
            GradientButton(label: 'Save address', expand: true, loading: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
