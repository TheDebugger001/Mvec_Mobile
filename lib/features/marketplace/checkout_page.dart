import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/auth_api.dart';
import '../../api/catalog_api.dart';
import '../../api/commerce_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/locations.dart';
import '../../core/theme.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/catalog_state.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/checkout_steps.dart';
import '../../widgets/common.dart';
import '../common/page_frame.dart';

class _Line {
  const _Line({required this.id, required this.name, required this.image, required this.vendor, required this.price, required this.qty, required this.stock, required this.status});
  final String id;
  final String name;
  final String image;
  final String vendor;
  final num price;
  final int qty;
  final int stock;
  final String status;
  bool get problem => (status.isNotEmpty && status != 'ACTIVE') || stock <= 0 || qty > stock;
}

/// `/checkout` (cart) and `/checkout?product=ID&qty=N` (buy now): details,
/// pickup or delivery, delivery fee quote, coupon, then the order is created
/// and the buyer goes on to pay (`pages/Checkout.jsx`). Guests confirm their
/// phone with a one-time code instead of signing up.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key, this.productId, this.qty = 1});
  final String? productId;
  final int qty;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _sector = TextEditingController();
  final _street = TextEditingController();
  final _coupon = TextEditingController();

  String _fulfilment = ''; // '' | pickup | delivery
  String _speed = 'standard';
  String _province = 'Kigali City';
  String _district = '';

  _Line? _buyNow;
  bool _loadingProduct = false;
  String _productError = '';

  List<Map<String, dynamic>> _addresses = const [];
  String _addressId = '';
  bool _saveAddress = false;
  bool _prefilled = false;

  Map<String, Map<String, dynamic>?> _quotes = {'standard': null, 'express': null, 'pickup': null};
  bool _quoting = false;
  String _quoteError = '';
  Timer? _quoteTimer;
  String _lastQuoteKey = '';

  Map<String, dynamic>? _couponResult;
  String _couponError = '';
  bool _couponBusy = false;

  Map<String, String> _errors = {};
  String _error = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) _loadProduct();
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    for (final c in [_name, _phone, _email, _sector, _street, _coupon]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() => _loadingProduct = true);
    try {
      final p = await CatalogApi.product(widget.productId!);
      final qty = widget.qty.clamp(1, p.stock <= 0 ? 1 : p.stock);
      if (mounted) {
        setState(() => _buyNow = _Line(id: p.id, name: p.name, image: p.image, vendor: p.vendor, price: p.price, qty: qty, stock: p.stock, status: p.status));
      }
    } catch (_) {
      if (mounted) setState(() => _productError = 'This product is no longer available.');
    } finally {
      if (mounted) setState(() => _loadingProduct = false);
    }
    _scheduleQuote();
  }

  List<_Line> get _items {
    if (widget.productId != null) return _buyNow == null ? const [] : [_buyNow!];
    return [
      for (final l in ref.read(cartProvider).lines)
        _Line(id: l.id, name: l.name, image: l.image, vendor: l.vendor, price: l.price, qty: l.qty, stock: l.stock < 0 ? 999999 : l.stock, status: l.status),
    ];
  }

  bool get _isPickup => _fulfilment == 'pickup';
  bool get _isDelivery => _fulfilment == 'delivery';
  String get _method => _isPickup ? 'pickup' : (_isDelivery ? _speed : '');
  Map<String, dynamic>? get _quote => _method.isEmpty ? null : _quotes[_method];
  bool get _districtValid => rwandaLocations[_province]?.contains(_district) ?? false;

  num get _subtotal => _items.fold<num>(0, (s, l) => s + l.price * l.qty);
  num get _delivery => _isDelivery ? numOf(_quote?['shippingFee']) : 0;
  bool get _undeliverable => _isDelivery && _quote != null && _quote!['deliverable'] == false;
  String get _undeliverableMessage => asMaps(_quote?['groups']).where((g) => g['deliverable'] == false).map((g) => strOf(g['message'])).join(' ');
  num get _discount => _couponResult == null ? 0 : numOf(_couponResult!['discount']).clamp(0, _subtotal + _delivery);
  num get _total => _subtotal + _delivery - _discount;

  List<({String productId, int qty})> get _quoteItems => [for (final l in _items) (productId: l.id, qty: l.qty)];

  void _scheduleQuote() {
    final key = '$_fulfilment|$_province|$_district|${_quoteItems.map((e) => '${e.productId}x${e.qty}').join(',')}';
    if (key == _lastQuoteKey) return;
    _lastQuoteKey = key;
    _quoteTimer?.cancel();
    if (_quoteItems.isEmpty || _fulfilment.isEmpty || (_isDelivery && !_districtValid)) {
      setState(() => _quotes = {'standard': null, 'express': null, 'pickup': null});
      return;
    }
    setState(() {
      _quoting = true;
      _quoteError = '';
    });
    _quoteTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        Map<String, Map<String, dynamic>?> next;
        if (_isPickup) {
          next = {'standard': null, 'express': null, 'pickup': await CheckoutApi.quote(method: 'PICKUP', items: _quoteItems)};
        } else {
          final res = await Future.wait([
            CheckoutApi.quote(method: 'STANDARD', items: _quoteItems, province: _province, district: _district),
            CheckoutApi.quote(method: 'EXPRESS', items: _quoteItems, province: _province, district: _district),
          ]);
          next = {'standard': res[0], 'express': res[1], 'pickup': null};
        }
        if (mounted && key == _lastQuoteKey) setState(() => _quotes = next);
      } catch (e) {
        if (mounted && key == _lastQuoteKey) {
          setState(() => _quoteError = _isPickup
              ? "We could not load the pickup points right now. You can still place the order; the seller's address is shown on your order."
              : 'We could not work out the delivery fee right now. You can still place the order; the fee is confirmed on the next step.');
        }
      } finally {
        if (mounted && key == _lastQuoteKey) setState(() => _quoting = false);
      }
    });
    if (_couponResult != null) _checkCoupon(_couponResult!['code'] as String, silent: true);
  }

  void _prefill() {
    final user = ref.read(authProvider).user;
    if (_prefilled || user == null) return;
    _prefilled = true;
    if (_name.text.isEmpty) _name.text = user.fullName;
    if (_phone.text.isEmpty) _phone.text = user.telephone;
    if (_email.text.isEmpty) _email.text = user.email;
    AuthApi.addresses().then((list) {
      if (!mounted) return;
      final preferred = list.where((a) => a['isDefaultShipping'] == true).firstOrNull ?? (list.isEmpty ? null : list.first);
      setState(() {
        _addresses = list;
        _saveAddress = list.isEmpty;
      });
      if (preferred != null) _pickAddress(strOf(preferred['_id']));
    }).catchError((_) {});
  }

  void _pickAddress(String id) {
    setState(() => _addressId = id);
    final a = _addresses.where((x) => strOf(x['_id']) == id).firstOrNull;
    if (a == null) return;
    final found = findDistrict(strOf(a['cityDistrict']));
    setState(() {
      _province = found?.province ?? (provinces.contains(strOf(a['provinceState'])) ? strOf(a['provinceState']) : 'Kigali City');
      _district = found?.district ?? '';
      _sector.text = strOf(a['sector']);
      _street.text = [a['street'], a['building'], a['apartment']].where((e) => strOf(e).isNotEmpty).join(', ');
      if (_phone.text.isEmpty) _phone.text = strOf(a['phone']);
    });
    _scheduleQuote();
  }

  Future<void> _checkCoupon(String code, {bool silent = false}) async {
    if (code.trim().isEmpty) return;
    if (ref.read(authProvider).user == null) {
      setState(() => _couponError = "Coupons work once you're signed in or have verified your phone.");
      return;
    }
    setState(() => _couponBusy = true);
    if (!silent) setState(() => _couponError = '');
    try {
      final res = await CheckoutApi.validateCoupon(
        code: code.trim(),
        items: _quoteItems,
        shippingMethod: _method.isEmpty ? 'pickup' : _method,
        province: _isDelivery && _districtValid ? _province : null,
        district: _isDelivery && _districtValid ? _district : null,
      );
      if (mounted) {
        setState(() {
          _couponResult = res;
          _couponError = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _couponResult = null;
          _couponError = errorText(e);
        });
      }
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  Map<String, String> _validate() {
    final errs = <String, String>{};
    final who = _isPickup ? 'collecting' : 'receiving';
    if (_name.text.trim().length < 2) errs['name'] = 'Enter the name of the person $who the order.';
    if (!isRwandanPhone(_phone.text)) errs['phone'] = 'Enter a Rwandan mobile number, for example 0788 123 456.';
    if (_email.text.trim().isNotEmpty && !isEmail(_email.text)) errs['email'] = 'Enter a valid email or leave it empty.';
    if (_fulfilment.isEmpty) errs['fulfilment'] = "Choose whether you'll pick the order up or have it delivered.";
    if (_isDelivery) {
      if (!_districtValid) errs['district'] = 'Choose your district.';
      if (_street.text.trim().length < 3) errs['street'] = 'Enter your street, house number or a nearby landmark.';
    }
    return errs;
  }

  CheckoutRequest _request() => CheckoutRequest(
        fulfilment: _fulfilment,
        method: _method,
        recipientName: _name.text,
        recipientPhone: _phone.text,
        recipientEmail: _email.text,
        province: _province,
        district: _district,
        sector: _sector.text,
        street: _street.text,
        couponCode: _couponResult?['code'] as String?,
      );

  Future<String> _submitOrder({List<_Line>? guestItems}) async {
    final lines = guestItems ?? (widget.productId != null ? _items : null);
    final req = _request();
    final res = lines != null
        ? await OrdersApi.directCheckout(req, [for (final l in lines) (productId: l.id, quantity: l.qty)])
        : await OrdersApi.checkout(req);
    if (_isDelivery && ref.read(authProvider).user != null && _saveAddress && _addressId.isEmpty) {
      AuthApi.addAddress({
        'type': 'HOME',
        'country': 'Rwanda',
        'provinceState': _province,
        'cityDistrict': _district,
        'sector': _sector.text.trim(),
        'street': _street.text.trim(),
        'phone': _phone.text.trim(),
      }).catchError((_) {});
    }
    ref.invalidate(catalogProvider); // stock changed
    final id = strOf(asMap(res['order'])['id']);
    if (id.isEmpty) throw ApiException('Your order was placed. Open My orders to pay for it.');
    return id;
  }

  Future<void> _place() async {
    setState(() => _error = '');
    final errs = _validate();
    setState(() => _errors = errs);
    if (errs.isNotEmpty) {
      setState(() => _error = errs.length == 1 && errs.containsKey('fulfilment') ? errs['fulfilment']! : 'Please check the highlighted fields.');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Your cart is empty.');
      return;
    }
    if (_items.any((l) => l.problem)) {
      setState(() => _error = 'Some items are no longer available in the quantity selected. Update your cart first.');
      return;
    }
    if (_undeliverable) {
      setState(() => _error = '$_undeliverableMessage Choose another district, choose pickup, or remove those items.');
      return;
    }
    if (ref.read(authProvider).user == null) {
      await _guestFlow();
      return;
    }
    setState(() => _submitting = true);
    try {
      final id = await _submitOrder();
      if (widget.productId == null) await ref.read(cartProvider.notifier).refresh();
      if (mounted) context.pushReplacement('/payment/$id');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
      if (widget.productId == null) ref.read(cartProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// No account needed: confirm the phone with a code, then order.
  Future<void> _guestFlow() async {
    setState(() => _submitting = true);
    String sentTo = '';
    try {
      final res = await AuthApi.guestSendCode(_phone.text.trim(), email: _email.text);
      sentTo = '${res['message'] ?? ''}';
    } on ApiException catch (e) {
      if (e.statusCode != 429) {
        setState(() {
          _error = e.message;
          _submitting = false;
        });
        return;
      }
    }
    if (!mounted) return;
    final basket = _items;
    final session = await showDialog<AuthSession>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CodeDialog(phone: _phone.text.trim(), name: _name.text.trim(), email: _email.text.trim(), sentTo: sentTo),
    );
    if (session == null || !mounted) {
      setState(() => _submitting = false);
      return;
    }
    // The basket goes with the order, so don't also merge it into the account cart.
    if (widget.productId == null) ref.read(cartProvider.notifier).clearLocal();
    await ref.read(authProvider.notifier).startSession(session);
    try {
      final id = await _submitOrder(guestItems: basket);
      if (widget.productId == null) await ref.read(cartProvider.notifier).refresh();
      if (mounted) context.pushReplacement('/payment/$id');
    } catch (e) {
      if (widget.productId == null) {
        for (final x in basket) {
          try {
            await CartApi.add(x.id, x.qty);
          } catch (_) {}
        }
        await ref.read(cartProvider.notifier).refresh();
      }
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _feeLabel(String method) {
    final q = _quotes[method];
    if (q == null) return _quoting ? '…' : (_districtValid ? '—' : 'Choose your district');
    if (q['deliverable'] == false) return 'Unavailable';
    final fee = numOf(q['shippingFee']);
    return fee == 0 ? 'FREE' : money(fee);
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final auth = ref.watch(authProvider);
    ref.watch(cartProvider);
    if (auth.user != null) WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());

    if (_loadingProduct) return const PageFrame(title: 'Checkout', storefront: true, body: LoadingState());
    final items = _items;
    if (_productError.isNotEmpty || (items.isEmpty && !_submitting)) {
      return PageFrame(
        title: 'Checkout',
        storefront: true,
        body: EmptyState(title: _productError.isEmpty ? 'Your cart is empty' : _productError, action: GradientButton(label: 'Continue shopping', compact: true, onPressed: () => context.go('/shop'))),
      );
    }

    InputDecoration dec(String key, String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint, errorText: _errors[key], errorMaxLines: 3);
    final groups = asMaps(_quote?['groups']);

    return PageFrame(
      title: 'Checkout',
      fallback: '/cart',
      storefront: true,
      bottom: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text('Total to pay', style: TextStyle(color: mv.textMuted, fontSize: 11)), FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(_total), style: context.mvH1.copyWith(fontSize: 18, fontWeight: FontWeight.w800)))],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 196,
            child: GradientButton(
              label: _submitting ? 'Placing order…' : (auth.user != null ? 'Continue to payment' : 'Verify phone & continue'),
              loading: _submitting,
              onPressed: auth.restoring || _undeliverable ? null : _place,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const CheckoutSteps(current: 1),
          Text('Pay with mobile money or card. MVEC holds the payment until you confirm you have your items.', style: TextStyle(color: mv.textMuted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 12),
          if (_error.isNotEmpty) Notice(text: _error),
          if (auth.user == null && !auth.restoring)
            Notice(
              info: true,
              text: "No account needed. We'll send a code to your phone (and to your email, if you add one) to confirm it's yours before you pay.",
              child: GestureDetector(
                onTap: () => context.push('/login?checkout=1&next=${Uri.encodeQueryComponent(GoRouterState.of(context).uri.toString())}'),
                child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('Have an account? Log in', style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w600, fontSize: 12.5))),
              ),
            ),
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your details', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                const SizedBox(height: 2),
                Text('The seller uses this phone number to reach you about the order.', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                const SizedBox(height: 12),
                TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: dec('name', 'Full name'), onChanged: (_) => setState(() => _errors.remove('name'))),
                const SizedBox(height: 10),
                TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: dec('phone', 'Phone', hint: '07xx xxx xxx'), onChanged: (_) => setState(() => _errors.remove('phone'))),
                const SizedBox(height: 10),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: dec('email', 'Email (optional)', hint: 'We also send your code and receipt here')),
              ],
            ),
          ),
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How do you want to get your order?', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                const SizedBox(height: 10),
                _Choice(selected: _isPickup, title: "I'll pick it up", subtitle: "Collect from the seller's store. No delivery fee.", icon: Icons.storefront_outlined, onTap: () => _chooseFulfilment('pickup')),
                const SizedBox(height: 8),
                _Choice(selected: _isDelivery, title: 'Deliver it to me', subtitle: 'The seller or an MVEC courier brings it. A delivery fee applies.', icon: Icons.local_shipping_outlined, onTap: () => _chooseFulfilment('delivery')),
                if (_errors['fulfilment'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['fulfilment']!, style: const TextStyle(color: MvColors.errorText, fontSize: 12))),
                if (_isPickup) ...[
                  const SizedBox(height: 10),
                  if (_quoting && _quote == null) Text('Loading pickup points…', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                  for (final g in groups) _ParcelRow(title: strOf(g['storeName'], 'Store'), subtitle: '${strOf(asMap(g['pickup'])['address'], "The seller confirms the pickup address")}${strOf(asMap(g['pickup'])['phone']).isEmpty ? '' : ' · ${asMap(g['pickup'])['phone']}'}', fee: 'FREE'),
                  if (_quoteError.isNotEmpty) Notice(text: _quoteError),
                  Text("You'll be told when your order is ready. Bring your delivery code; the seller hands over your items when you give it.", style: TextStyle(color: mv.textMuted, fontSize: 11.5, height: 1.4)),
                ],
                if (_isDelivery) ...[
                  const SizedBox(height: 12),
                  if (_addresses.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('addr$_addressId${_addresses.length}'),
                      initialValue: _addressId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Saved addresses'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Enter a new address')),
                        for (final a in _addresses) DropdownMenuItem(value: strOf(a['_id']), child: Text('${strOf(a['type'], 'Address')}: ${strOf(a['street'])}, ${strOf(a['cityDistrict'])}', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        if (v == null || v.isEmpty) {
                          setState(() => _addressId = '');
                        } else {
                          _pickAddress(v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _province,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Province / City'),
                    items: [for (final p in provinces) DropdownMenuItem(value: p, child: Text(p))],
                    onChanged: (v) {
                      setState(() {
                        _province = v ?? _province;
                        _district = '';
                        _addressId = '';
                      });
                      _scheduleQuote();
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('district$_province$_district'),
                    initialValue: _district.isEmpty ? null : _district,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'District', errorText: _errors['district']),
                    hint: const Text('Choose a district'),
                    items: [for (final d in rwandaLocations[_province] ?? const <String>[]) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: (v) {
                      setState(() {
                        _district = v ?? '';
                        _addressId = '';
                        _errors.remove('district');
                      });
                      _scheduleQuote();
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _sector, decoration: const InputDecoration(labelText: 'Sector (optional)', hintText: 'e.g. Remera'), onChanged: (_) => _addressId = ''),
                  const SizedBox(height: 10),
                  TextField(controller: _street, decoration: dec('street', 'Street / landmark', hint: 'e.g. KG 11 Ave, house 18'), onChanged: (_) {
                    _addressId = '';
                    setState(() => _errors.remove('street'));
                  }),
                  if (auth.user != null && _addressId.isEmpty)
                    CheckboxListTile(
                      value: _saveAddress,
                      onChanged: (v) => setState(() => _saveAddress = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text('Save this address to my account', style: TextStyle(fontSize: 12.5)),
                    ),
                  const SizedBox(height: 6),
                  Text('Delivery speed', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                  RadioGroup<String>(
                    groupValue: _speed,
                    onChanged: (v) {
                      setState(() => _speed = v ?? 'standard');
                      _scheduleQuote();
                    },
                    child: Column(
                      children: [
                        for (final speed in const [('standard', 'Standard delivery'), ('express', 'Express delivery')])
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: _speed == speed.$1 ? mv.soft : null,
                              borderRadius: BorderRadius.circular(MvRadius.field + 2),
                              border: Border.all(color: _speed == speed.$1 ? mv.accent : mv.border, width: _speed == speed.$1 ? 1.5 : 1),
                            ),
                            child: Material(color: Colors.transparent, child: RadioListTile<String>(value: speed.$1, dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8), title: Text('${speed.$2}  ·  ${_feeLabel(speed.$1)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),
                          ),
                      ],
                    ),
                  ),
                  if (_quoteError.isNotEmpty) Notice(text: _quoteError),
                  if (_undeliverable) Notice(text: '$_undeliverableMessage Choose another district, choose pickup, or remove those items.'),
                  if (_quote?['deliverable'] == true)
                    for (final g in groups)
                      _ParcelRow(
                        title: strOf(g['storeName'], 'Store'),
                        subtitle: '${strOf(g['zoneName'])}${strOf(g['eta']).isEmpty ? '' : ' · ${g['eta']}'}',
                        fee: numOf(g['fee']) == 0 ? 'FREE' : money(g['fee']),
                      ),
                  Text('Delivery fees are set by each seller for your district; items from different stores ship separately. You give the courier your delivery code when it arrives.', style: TextStyle(color: mv.textMuted, fontSize: 11.5, height: 1.4)),
                ],
              ],
            ),
          ),
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order items', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text)),
                const SizedBox(height: 8),
                for (final x in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(width: 54, height: 54, decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias, child: ProductImage(src: x.image)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              Text('${x.vendor} · Qty ${x.qty}', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                              if (x.problem) Text(x.stock <= 0 || x.status != 'ACTIVE' ? 'No longer available' : 'Only ${x.stock} left', style: const TextStyle(color: MvColors.errorText, fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Text(money(x.price * x.qty), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coupon', style: TextStyle(fontWeight: FontWeight.w700, color: mv.text)),
                const SizedBox(height: 10),
                if (_couponResult != null)
                  Row(children: [Expanded(child: Text('${_couponResult!['code']} · ${strOf(_couponResult!['message'])}', style: TextStyle(color: mv.textMuted, fontSize: 11.5))), TextButton(onPressed: () => setState(() {
                        _couponResult = null;
                        _coupon.clear();
                      }), child: const Text('Remove'))])
                else
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _coupon, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'Coupon code', isDense: true), onSubmitted: (v) => _checkCoupon(v))),
                      const SizedBox(width: 8),
                      OutlineBtn(label: _couponBusy ? '…' : 'Apply', compact: true, onPressed: _couponBusy ? null : () => _checkCoupon(_coupon.text)),
                    ],
                  ),
                if (_couponError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_couponError, style: const TextStyle(color: MvColors.errorText, fontSize: 11.5))),
              ],
            ),
          ),
          BrandPanel(
            children: [
              const PanelTitle('Order summary'),
              PanelRow('Products', money(_subtotal)),
              PanelRow(_isPickup ? 'Pickup' : 'Delivery', _fulfilment.isEmpty ? 'Choose pickup or delivery' : (_isPickup ? 'FREE (pickup)' : (_quoting && _quote == null ? '…' : (_undeliverable || _quote == null ? '—' : (_delivery == 0 ? 'FREE' : money(_delivery)))))),
              if (_discount > 0) PanelRow('Coupon ${_couponResult!['code']}', '−${money(_discount)}'),
              Divider(height: 22, color: Colors.white.withValues(alpha: .22)),
              PanelRow('Total to pay', money(_total), bold: true),
            ],
          ),
          const InfoBox(title: 'Protected payment', text: 'You pay by MTN MoMo, Airtel Money or card on the next step. MVEC holds the money and only releases it to the seller after you confirm you have your items with your code.'),
        ],
      ),
    );
  }

  void _chooseFulfilment(String v) {
    setState(() {
      _fulfilment = v;
      _errors.remove('fulfilment');
    });
    _scheduleQuote();
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.title, required this.subtitle, required this.onTap, required this.icon});
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return InkWell(
      borderRadius: BorderRadius.circular(MvRadius.card),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? mv.soft : null,
          borderRadius: BorderRadius.circular(MvRadius.card),
          border: Border.all(color: selected ? mv.accent : mv.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: selected ? mv.accent : mv.surfaceMuted, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: selected ? Colors.white : mv.accentDeep),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 13.5)), const SizedBox(height: 1), Text(subtitle, style: TextStyle(color: mv.textMuted, fontSize: 11.5, height: 1.3))])),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, size: 22, color: selected ? mv.accent : mv.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ParcelRow extends StatelessWidget {
  const _ParcelRow({required this.title, required this.subtitle, required this.fee});
  final String title;
  final String subtitle;
  final String fee;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)), Text(subtitle, style: TextStyle(color: mv.textMuted, fontSize: 11))])),
          Text(fee, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Asks for the 6-digit code sent to a guest's phone (and email, if given).
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.phone, required this.name, required this.email, required this.sentTo});
  final String phone;
  final String name;
  final String email;
  /// Where the server says the code went, e.g. "We emailed a 6-digit code to …".
  final String sentTo;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final s = await AuthApi.guestVerify(phone: widget.phone, code: code, fullName: widget.name, email: widget.email);
      if (mounted) Navigator.pop(context, s);
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
    return AlertDialog(
      title: const Text('Confirm your phone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.sentTo.isEmpty ? 'We sent a 6-digit code to ${widget.phone}.' : widget.sentTo} Enter it to place your order. Only this phone can see the order.', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: _code, autofocus: true, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Code', counterText: ''), onSubmitted: (_) => _confirm()),
          if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: MvColors.errorText, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _busy ? null : _confirm, child: Text(_busy ? 'Checking…' : 'Confirm & continue')),
      ],
    );
  }
}
