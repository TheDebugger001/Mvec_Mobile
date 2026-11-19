import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../portal/kit.dart';
import 'common.dart';

/// "Get paid automatically" (`/api/auto-payouts`), for sellers, suppliers,
/// riders and affiliates. When a buyer receives an order, Ikiguzi sets its
/// commission (and any affiliate's share) aside and sends the rest to this
/// mobile money number, without a withdrawal request.
class AutoPayoutCard extends StatefulWidget {
  const AutoPayoutCard({super.key, this.defaultName = '', this.defaultPhone = '', this.onSaved});

  final String defaultName;
  final String defaultPhone;
  final VoidCallback? onSaved;

  @override
  State<AutoPayoutCard> createState() => _AutoPayoutCardState();
}

class _AutoPayoutCardState extends State<AutoPayoutCard> {
  late final _phone = TextEditingController(text: widget.defaultPhone);
  late final _name = TextEditingController(text: widget.defaultName);
  bool _auto = false;
  bool _loaded = false;
  bool _busy = false;
  num _minimum = 1000;
  String _lastError = '';
  String? _message;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    Api.instance.get('/auto-payouts').then((r) {
      final s = asMap(r);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _auto = s['auto'] == true;
        _minimum = numOf(s['minimum'], 1000);
        _lastError = strOf(s['lastError']);
        if (strOf(s['phone']).isNotEmpty) _phone.text = strOf(s['phone']);
        if (strOf(s['accountName']).isNotEmpty) _name.text = strOf(s['accountName']);
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _message = errorText(e));
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = asMap(await Api.instance.put('/auto-payouts', body: {'auto': _auto, 'phone': _phone.text.trim(), 'accountName': _name.text.trim()}));
      final s = asMap(r['setting']);
      setState(() {
        _ok = true;
        _message = strOf(r['message'], 'Saved.');
        _lastError = strOf(s['lastError']);
      });
      widget.onSaved?.call();
    } catch (e) {
      setState(() {
        _ok = false;
        _message = errorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Section(
        title: 'Get paid automatically',
        subtitle: 'When a buyer receives an order, Ikiguzi takes its commission (and any affiliate\'s share) and sends the rest to your mobile money, from ${money(_minimum)}.',
        children: [
          if (_message != null) Notice(text: _message!, ok: _ok),
          if (_lastError.isNotEmpty) Notice(text: 'Last attempt failed: $_lastError. We\'ll try again shortly.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _auto,
            onChanged: _loaded ? (v) => setState(() => _auto = v) : null,
            title: const Text('Send my money automatically', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile money number', hintText: '078/079 (MTN) or 072/073 (Airtel)')),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name on the account')),
          const SizedBox(height: 12),
          GradientButton(label: 'Save', expand: true, loading: _busy, onPressed: _busy || !_loaded ? null : _save),
        ],
      );
}
