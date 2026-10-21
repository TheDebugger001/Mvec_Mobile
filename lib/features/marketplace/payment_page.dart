import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/commerce_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../common/page_frame.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/checkout_steps.dart';
import '../../widgets/common.dart';

const _pollEvery = Duration(seconds: 3);
const _pollLimit = Duration(minutes: 3);

/// `/payment/:id` — pay an order with mobile money, card or K-Pay, then wait
/// for the payment to be confirmed (`pages/Payment.jsx`). The status endpoint
/// also asks the gateway, so polling works even without a gateway callback.
class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> with WidgetsBindingObserver {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String _method = 'momo'; // momo | card | kpay
  String _kpayMethod = 'momo';
  final _phone = TextEditingController();
  String _stage = 'choose'; // choose | waiting | confirmed | timeout
  String _error = '';
  String _notice = '';
  Timer? _timer;
  String? _paymentId;
  DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOrder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  /// Back from the card page: check the result right away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == 'waiting') _checkOnce();
  }

  Future<void> _loadOrder() async {
    try {
      final o = await OrdersApi.byId(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        final raw = strOf(asMap(o['recipient'])['phone'], ref.read(authProvider).user?.telephone ?? '');
        _phone.text = raw.startsWith('+250') ? '0${raw.substring(4)}' : raw;
        if (o['paymentStatus'] == 'PAID') _stage = 'confirmed';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirmed() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _stage = 'confirmed');
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) context.pushReplacement('/orders/${widget.orderId}');
    });
  }

  Future<void> _checkOnce() async {
    try {
      if (_paymentId != null) {
        final res = await PaymentsApi.status(_paymentId!);
        final payment = asMap(res['payment']);
        if (asMap(res['order'])['paymentStatus'] == 'PAID' || payment['status'] == 'SUCCESS') return _confirmed();
        if (payment['status'] == 'FAILED' || payment['status'] == 'CANCELLED') {
          _timer?.cancel();
          if (mounted) {
            setState(() {
              _stage = 'choose';
              _error = payment['method'] == 'CARD'
                  ? 'The card payment was declined or cancelled. No money was taken; you can try again or use mobile money.'
                  : 'The payment was declined or cancelled on your phone. You can try again.';
            });
          }
          return;
        }
      } else {
        final o = await OrdersApi.byId(widget.orderId);
        if (o['paymentStatus'] == 'PAID') return _confirmed();
      }
    } catch (_) {
      // Temporary network problem: keep trying.
    }
    if (DateTime.now().difference(_startedAt) > _pollLimit) {
      _timer?.cancel();
      if (mounted) setState(() => _stage = 'timeout');
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(_pollEvery, (_) => _checkOnce());
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) throw ApiException('The payment page could not be opened. Please try again.');
  }

  Future<void> _pay() async {
    setState(() {
      _error = '';
      _notice = '';
    });
    final id = widget.orderId;
    try {
      if (_method == 'card') {
        setState(() => _stage = 'waiting');
        final res = await PaymentsApi.payCard(id);
        _paymentId = strOf(res['paymentId']).isEmpty ? null : strOf(res['paymentId']);
        if (res['status'] == 'SUCCESS') return _confirmed();
        final url = strOf(res['checkoutUrl']);
        if (url.isEmpty) throw ApiException('The card page could not be opened. Please try again.');
        setState(() => _notice = 'Complete the payment on the secure card page, then come back here.');
        await _openUrl(url);
        _startPolling();
        return;
      }
      if (_method == 'kpay') {
        if (_kpayMethod == 'momo' && !isRwandanPhone(_phone.text)) {
          setState(() => _error = 'Enter an MTN (078/079) or Airtel (072/073) number.');
          return;
        }
        setState(() => _stage = 'waiting');
        final res = await PaymentsApi.payKpay(id, _kpayMethod, _phone.text.trim());
        _paymentId = strOf(res['paymentId']).isEmpty ? null : strOf(res['paymentId']);
        if (res['status'] == 'SUCCESS') return _confirmed();
        final url = strOf(res['checkoutUrl']);
        if (url.isNotEmpty) {
          setState(() => _notice = "Finish on K-Pay's secure page, then come back here.");
          await _openUrl(url);
        } else {
          setState(() => _notice = strOf(res['message'], 'Approve the prompt on your phone.'));
        }
        _startPolling();
        return;
      }
      if (!isRwandanPhone(_phone.text)) {
        setState(() => _error = 'Enter an MTN (078/079) or Airtel (072/073) number.');
        return;
      }
      setState(() => _stage = 'waiting');
      final res = await PaymentsApi.payMobileMoney(id, _phone.text.trim());
      _paymentId = strOf(res['paymentId']).isEmpty ? null : strOf(res['paymentId']);
      setState(() => _notice = strOf(res['message']));
      if (res['status'] == 'SUCCESS') return _confirmed();
      _startPolling();
    } on ApiException catch (e) {
      // A prompt is already waiting on the phone: keep watching that one.
      final data = e.data;
      if (e.statusCode == 409 && data is Map && data['paymentId'] != null) {
        _paymentId = '${data['paymentId']}';
        setState(() => _notice = e.message);
        _startPolling();
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _stage = 'choose';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _stage = 'choose';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    if (_loading) return const PageFrame(title: 'Payment', storefront: true, body: LoadingState());
    final order = _order;
    if (order == null) {
      return PageFrame(
        title: 'Payment',
        fallback: '/orders',
        storefront: true,
        body: PageList(children: [Notice(text: _error.isEmpty ? 'Order not found.' : _error), OutlineBtn(label: 'My orders', onPressed: () => context.go('/orders'))]),
      );
    }
    final closed = order['orderStatus'] == 'CANCELLED' || order['paymentStatus'] == 'REFUNDED';
    final waiting = _stage == 'waiting';
    final provider = mobileProvider(_phone.text);
    final total = order['totalAmount'];

    Widget option(String value, String title, String sub, IconData icon) {
      final on = _method == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(MvRadius.card),
          onTap: waiting ? null : () => setState(() => _method = value),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: on ? mv.soft : null,
              borderRadius: BorderRadius.circular(MvRadius.card),
              border: Border.all(color: on ? mv.accent : mv.border, width: on ? 1.5 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: on ? mv.accent : mv.surfaceMuted, shape: BoxShape.circle),
                  child: Icon(icon, size: 21, color: on ? Colors.white : mv.accentDeep),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 13.5)), const SizedBox(height: 1), Text(sub, style: TextStyle(color: mv.textMuted, fontSize: 11.5, height: 1.3))])),
                const SizedBox(width: 8),
                Icon(on ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, size: 22, color: on ? mv.accent : mv.textMuted),
              ],
            ),
          ),
        ),
      );
    }

    return PageFrame(
      title: 'Payment',
      fallback: '/orders',
      storefront: true,
      body: PageList(
        children: [
          CheckoutSteps(current: _stage == 'confirmed' ? 3 : 2),
          PageTitle(eyebrow: 'Payment', title: 'Pay for your order', subtitle: 'Order #${order['orderNumber']}'),
          if (_error.isNotEmpty) Notice(text: _error),
          if (_notice.isNotEmpty && _stage != 'confirmed') Notice(text: _notice, ok: true),
          if (closed)
            DataCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('This order is closed', style: context.mvH1.copyWith(fontSize: 16)),
                const SizedBox(height: 6),
                Text('${order['cancellationReason'] == 'PAYMENT_TIMEOUT_EXPIRED_30_MIN' ? 'It was not paid within 30 minutes, so it was cancelled and the items were released.' : 'This order was cancelled.'} You have not been charged for it.', style: TextStyle(color: mv.textMuted, fontSize: 13)),
                const SizedBox(height: 12),
                GradientButton(label: 'Continue shopping', compact: true, onPressed: () => context.go('/shop')),
              ]),
            )
          else if (_stage == 'confirmed')
            DataCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Payment confirmed ✓', style: context.mvH1.copyWith(fontSize: 16)),
                const SizedBox(height: 6),
                Text('Thank you! Your payment is held safely by MVEC. Taking you to your order…', style: TextStyle(color: mv.textMuted, fontSize: 13)),
                const SizedBox(height: 12),
                GradientButton(label: 'View order', compact: true, onPressed: () => context.pushReplacement('/orders/${widget.orderId}')),
              ]),
            )
          else
            DataCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How would you like to pay?', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                  const SizedBox(height: 10),
                  option('momo', 'Mobile money', 'MTN MoMo or Airtel Money: approve a prompt on your phone', Icons.phone_android_rounded),
                  option('card', 'Card', "Visa or Mastercard on Flutterwave's secure page", Icons.credit_card_rounded),
                  option('kpay', 'K-Pay', 'Mobile money, card or SPENN through K-Pay', Icons.account_balance_wallet_outlined),
                  const SizedBox(height: 4),
                  if (_method == 'kpay') ...[
                    DropdownButtonFormField<String>(
                      initialValue: _kpayMethod,
                      decoration: const InputDecoration(labelText: 'Pay with'),
                      items: const [
                        DropdownMenuItem(value: 'momo', child: Text('Mobile money (MTN / Airtel)')),
                        DropdownMenuItem(value: 'card', child: Text('Card (Visa / Mastercard / Amex)')),
                        DropdownMenuItem(value: 'spenn', child: Text('SPENN')),
                      ],
                      onChanged: waiting ? null : (v) => setState(() => _kpayMethod = v ?? 'momo'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_method == 'momo' || (_method == 'kpay' && _kpayMethod == 'momo')) ...[
                    TextField(controller: _phone, enabled: !waiting, keyboardType: TextInputType.phone, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Mobile money number', hintText: '07xx xxx xxx', helperText: provider.isEmpty ? null : provider)),
                  ] else
                    Text(_method == 'card' ? "You will enter your card on Flutterwave's secure page, then come back here. MVEC never sees your card number." : "You finish the payment on K-Pay's secure page and come back here.", style: TextStyle(color: mv.textMuted, fontSize: 12)),
                  const SizedBox(height: 14),
                  GradientButton(
                    label: waiting ? (_method == 'card' ? 'Confirming your card payment…' : 'Waiting for your approval…') : 'Pay ${money(total)}${_method == 'card' ? ' by card' : (_method == 'kpay' ? ' with K-Pay' : '')}',
                    expand: true,
                    loading: waiting,
                    onPressed: waiting ? null : _pay,
                  ),
                  if (waiting && _method == 'momo') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Approve the prompt on your phone. This page updates automatically.', style: TextStyle(color: mv.textMuted, fontSize: 12))),
                  if (waiting)
                    Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () {
                      _timer?.cancel();
                      setState(() => _stage = 'choose');
                    }, child: const Text('Change payment method'))),
                  if (_stage == 'timeout')
                    Notice(text: 'We have not received a confirmation yet. If you approved the payment, it may still arrive.', child: TextButton(onPressed: () {
                      setState(() => _stage = 'waiting');
                      _startPolling();
                    }, child: const Text('Check again'))),
                  Text('Unpaid orders are cancelled automatically after 30 minutes.', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
          BrandPanel(
            children: [
              const PanelTitle('Order total'),
              PanelRow('Products', money(order['subtotal'] ?? numOf(total) - numOf(order['shippingFee']))),
              PanelRow('Delivery', numOf(order['shippingFee']) > 0 ? money(order['shippingFee']) : 'FREE'),
              Divider(height: 22, color: Colors.white.withValues(alpha: .22)),
              PanelRow('Total', money(total), bold: true),
            ],
          ),
          const InfoBox(title: 'How MVEC protects you', text: 'Your payment is held by MVEC until you confirm delivery, then released to the seller. After payment you get a delivery code in your order. Only give it to the courier when your order arrives.'),
        ],
      ),
    );
  }
}
