import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'wholesale_shared.dart';

/// Seller pays a wholesale order by mobile money or card (`PayWholesale`).
class PayWholesaleSheet extends StatefulWidget {
  const PayWholesaleSheet({super.key, required this.order});
  final Map<String, dynamic> order;

  @override
  State<PayWholesaleSheet> createState() => _PayWholesaleSheetState();
}

class _PayWholesaleSheetState extends State<PayWholesaleSheet> {
  String _method = 'momo';
  final _phone = TextEditingController();
  bool _busy = false;
  String _error = '';
  String _waiting = '';
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  String get _done => '${widget.order['orderNumber']} is paid. The supplier has been told to ship.';

  void _wait(String paymentId) {
    setState(() => _waiting = paymentId);
    var tries = 0;
    _timer = Timer.periodic(const Duration(seconds: 4), (t) async {
      tries++;
      try {
        final r = await jget('/payments/status/$paymentId');
        final st = r['status'] ?? asMap(r['payment'])['status'];
        if (st == 'SUCCESS') {
          t.cancel();
          if (mounted) Navigator.of(context).pop(_done);
          return;
        }
        if (st == 'FAILED') {
          t.cancel();
          if (mounted) {
            setState(() {
              _waiting = '';
              _busy = false;
              _error = 'The payment was declined or cancelled. No money was taken.';
            });
          }
          return;
        }
      } catch (_) {
        // Keep waiting.
      }
      if (tries > 45) {
        t.cancel();
        if (mounted) {
          setState(() {
            _waiting = '';
            _busy = false;
            _error = 'No confirmation yet. If you approved it, the order updates by itself in a few minutes.';
          });
        }
      }
    });
  }

  Future<void> _pay() async {
    if (_method == 'momo' && !isRwandanPhone(_phone.text)) {
      setState(() => _error = 'Enter an MTN (078/079) or Airtel (072/073) number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await jpost('/wholesale/orders/${idOf(widget.order)}/pay', {'method': _method, 'phoneNumber': _phone.text.trim()});
      if (strOf(r['checkoutUrl']).isNotEmpty) {
        await launchUrl(Uri.parse(strOf(r['checkoutUrl'])), mode: LaunchMode.externalApplication);
        if (mounted) setState(() => _busy = false);
        if (strOf(r['paymentId']).isNotEmpty) _wait(strOf(r['paymentId']));
        return;
      }
      if (r['status'] == 'SUCCESS') {
        if (mounted) Navigator.of(context).pop(_done);
        return;
      }
      _wait(strOf(r['paymentId']));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('PAY WHOLESALE ORDER', style: context.mvEyebrow.copyWith(fontSize: 11, letterSpacing: 1.4)),
            Text(money(o['totalAmount']), style: context.mvH1.copyWith(fontSize: 22)),
            Tiny('${o['orderNumber']} · ${partyName(o['supplier'])}. Ikiguzi holds the money and pays the supplier only after you confirm the goods arrived.'),
            const SizedBox(height: 10),
            if (_error.isNotEmpty) Notice(text: _error),
            if (_waiting.isNotEmpty)
              const Notice(info: true, text: 'Approve the prompt on your phone. This updates when the payment is confirmed…')
            else ...[
              RadioGroup<String>(
                groupValue: _method,
                onChanged: (v) => setState(() => _method = v ?? 'momo'),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'momo',
                      title: Text('Mobile money', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('MTN MoMo or Airtel Money'),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'card',
                      title: Text('Card', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Visa or Mastercard on a secure page'),
                    ),
                  ],
                ),
              ),
              if (_method == 'momo') TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile money number', hintText: '07…')),
              const SizedBox(height: 12),
              GradientButton(label: 'Pay ${money(o['totalAmount'])}', loading: _busy, onPressed: _pay),
            ],
            const SizedBox(height: 8),
            OutlineBtn(label: 'Close', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

// ─── Seller: quote requests ──────────────────────────────────────────────────
