import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/locations.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import '../common/page_frame.dart';
import 'seller_common.dart';

String _customerOf(Map<String, dynamic> o) => strOf(asMap(o['customer'])['name'], personName(o['user']));
num _orderTotal(Map<String, dynamic> o) => numOf(o['vendorSubtotal']) + numOf(o['vendorShippingFee']);

const _ranges = [('all', 'All time'), ('7', 'Last 7 days'), ('30', 'Last 30 days'), ('90', 'Last 90 days')];

/// `/vendor/orders` — online orders and manual sales with the next step for each.
class SellerOrdersPage extends StatefulWidget {
  const SellerOrdersPage({super.key});

  @override
  State<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends State<SellerOrdersPage> {
  late final _data = Loader(() => jlist('/orders/vendor/orders', 'orders'));
  String _tab = 'all';
  String _q = '';
  String _source = '';
  String _range = 'all';
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _update(Map<String, dynamic> o, Map<String, dynamic> body, String message) async {
    setState(() => _busy = idOf(o));
    final ok = await runAction(context, () => jpatch('/orders/vendor/status', {'orderId': idOf(o), ...body}), success: message);
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  Future<void> _cancel(Map<String, dynamic> o) async {
    final reason = await askCancelReason(context, o);
    if (reason != null) await _update(o, {'status': 'CANCELLED', 'reason': reason}, '${o['orderNumber']} cancelled.');
  }

  Future<void> _newOrder() async {
    final created = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ManualOrderPage()));
    if (created != null && mounted) context.push('/vendor/orders/${idOf(created['order'])}');
    _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Orders',
      subtitle: 'Online orders for your products and the sales you record yourself.',
      onRefresh: _data.reload,
      action: GradientButton(label: 'New order', icon: Icons.add_rounded, compact: true, onPressed: _newOrder),
      children: [
        LoadView(
          loader: _data,
          builder: (orders) {
            final now = DateTime.now();
            final inRange = _range == 'all' ? orders : orders.where((o) => (parseDate(o['createdAt']) ?? now).isAfter(now.subtract(Duration(days: int.parse(_range))))).toList();
            final base =
                inRange
                    .where(
                      (o) =>
                          (_source.isEmpty || strOf(o['source'], 'ONLINE') == _source) &&
                          matches(_q, [
                            o['orderNumber'],
                            _customerOf(o),
                            asMap(o['user'])['email'],
                            asMap(o['customer'])['phone'],
                            asMap(o['shippingAddress'])['district'],
                            asMap(o['shippingAddress'])['city'],
                            ...asMaps(o['items']).map((i) => i['name']),
                          ]),
                    )
                    .toList();
            final counts = {for (final t in orderTabs) t.$1: t.$3 == null ? base.length : base.where((o) => t.$3!.contains(o['orderStatus'])).length};
            final statuses = orderTabs.firstWhere((t) => t.$1 == _tab).$3;
            final shown = statuses == null ? base : base.where((o) => statuses.contains(o['orderStatus'])).toList();
            final monthStart = DateTime(now.year, now.month);
            final month = orders.where((o) => !(parseDate(o['createdAt']) ?? now).isBefore(monthStart) && isRevenueOrder(o) && o['paymentStatus'] == 'PAID').toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'To accept', value: '${orders.where((o) => o['orderStatus'] == 'PENDING').length}', icon: 'bell', sub: 'New orders waiting for you'),
                    MetricCard(
                      label: 'To prepare',
                      value: '${orders.where((o) => ['CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT'].contains(o['orderStatus'])).length}',
                      icon: 'box',
                      sub: 'Accepted, not shipped yet',
                    ),
                    MetricCard(
                      label: 'On the way',
                      value: '${orders.where((o) => ['SHIPPED', 'OUT_FOR_DELIVERY'].contains(o['orderStatus'])).length}',
                      icon: 'cart',
                      sub: "Delivered with the buyer's code",
                    ),
                    MetricCard(label: 'Paid this month', value: money(month.fold<num>(0, (s, o) => s + _orderTotal(o))), icon: 'wallet', sub: '${month.length} orders'),
                  ],
                ),
                const SizedBox(height: 14),
                TabChips(tabs: [for (final t in orderTabs) (t.$1, t.$2)], value: _tab, counts: counts, onChanged: (v) => setState(() => _tab = v)),
                SearchBox(hint: 'Search order, customer, phone, district or product', onChanged: (v) => setState(() => _q = v)),
                FilterRow(
                  children: [
                    FilterSelect(value: _source, label: 'Source', options: const [('', 'All sources'), ('ONLINE', 'Online'), ('MANUAL', 'Manual')], onChanged: (v) => setState(() => _source = v)),
                    FilterSelect(value: _range, label: 'Period', options: _ranges, onChanged: (v) => setState(() => _range = v)),
                  ],
                ),
                if (orders.isEmpty)
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders yet',
                    message: 'Orders for your products appear here. You can also record a sale yourself.',
                    action: GradientButton(label: 'New order', compact: true, onPressed: _newOrder),
                  )
                else if (shown.isEmpty)
                  const Tiny('No orders match these filters.')
                else
                  Paged<Map<String, dynamic>>(
                    items: shown,
                    itemBuilder: (o) {
                      final next = sellerNextStatuses(o).where((s) => s != 'CANCELLED').toList();
                      final cancellable = sellerNextStatuses(o).contains('CANCELLED');
                      final items = asMaps(o['items']);
                      final busy = _busy == idOf(o);
                      return RecordCard(
                        title: strOf(o['orderNumber']),
                        badges: [if (o['source'] == 'MANUAL') const StatusChip('Manual')],
                        subtitle: '${_customerOf(o)} · ${formatDate(o['createdAt'])}',
                        lines: [
                          if (items.isNotEmpty) '${items.first['name']}${items.length > 1 ? ' +${items.length - 1} more' : ''}',
                          if (numOf(o['vendorShippingFee']) > 0) 'incl. ${money(o['vendorShippingFee'])} delivery',
                          'Payment: ${titleCase(o['paymentStatus'])}',
                        ],
                        amount: money(_orderTotal(o)),
                        status: Pill(o['orderStatus']),
                        onTap: () => context.push('/vendor/orders/${idOf(o)}'),
                        actions: [
                          for (final s in next)
                            ActionChipBtn(stepLabelFor(o, s), primary: true, busy: busy, onPressed: () => _update(o, {'status': s}, '${o['orderNumber']}: ${titleCase(s).toLowerCase()}.')),
                          if (canRecordCash(o)) ActionChipBtn('Cash received', busy: busy, onPressed: () => _update(o, {'paymentStatus': 'PAID'}, 'Cash recorded for ${o['orderNumber']}.')),
                          if (next.isEmpty && !canRecordCash(o) && ['SHIPPED', 'OUT_FOR_DELIVERY'].contains(o['orderStatus'])) const Tiny('Awaiting delivery code'),
                          if (cancellable) ActionChipBtn('Cancel', danger: true, busy: busy, onPressed: () => _cancel(o)),
                        ],
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// `/vendor/orders/:id` and `/admin/orders/:id` — items, what the seller
/// receives, customer, next step and progress (`SellerOrderDetail`).
class SellerOrderDetailPage extends ConsumerStatefulWidget {
  const SellerOrderDetailPage({super.key, required this.id, this.admin = false});
  final String id;
  final bool admin;

  @override
  ConsumerState<SellerOrderDetailPage> createState() => _SellerOrderDetailPageState();
}

class _SellerOrderDetailPageState extends ConsumerState<SellerOrderDetailPage> {
  late final _data = Loader(() async {
    final order = asMap((await jget('/orders/${widget.id}'))['order']);
    final commission = widget.admin ? kDefaultCommission : parsePercent((await jget('/payouts/balance').catchError((_) => <String, dynamic>{}))['commissionRate']);
    return (order: {...order, '_id': idOf(order)}, commission: commission);
  });
  bool _updating = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _update(Map<String, dynamic> body) async {
    setState(() => _updating = true);
    final ok = await runAction(context, () => jpatch('/orders/vendor/status', {'orderId': widget.id, ...body}));
    if (mounted) setState(() => _updating = false);
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider.select((a) => a.user));
    return PageFrame(
      title: 'Order',
      fallback: widget.admin ? '/admin/orders' : '/vendor/orders',
      body: LoadView(
        loader: _data,
        page: true,
        loadingLabel: 'Loading order…',
        builder: (d) {
          final o = d.order;
          bool mine(Map<String, dynamic> x) => idOf(x['vendor']) == me?.id;
          final items = widget.admin ? asMaps(o['items']) : asMaps(o['items']).where(mine).toList();
          final gross = items.fold<num>(0, (s, it) => s + numOf(it['price']) * numOf(it['quantity']));
          final coupon = items.fold<num>(0, (s, it) => s + numOf(it['discount']));
          final subtotal = gross - coupon;
          final fee = subtotal * d.commission / 100;
          final parcels = widget.admin ? asMaps(o['shippingBreakdown']) : asMaps(o['shippingBreakdown']).where(mine).toList();
          final delivery = parcels.fold<num>(0, (s, p) => s + numOf(p['fee']));
          final waived = parcels.fold<num>(0, (s, p) => s + numOf(p['originalFee']));
          final address = asMap(o['shippingAddress']);
          final customer = asMap(o['customer']);
          final flow = orderFlowFor(o);
          final idx = flowIndexOf(o);
          final allNext = widget.admin ? <String>[] : sellerNextStatuses(o);
          final next = allNext.where((s) => s != 'CANCELLED').toList();
          final manual = o['source'] == 'MANUAL';
          final payLink = '$webOrigin/payment/${o['_id']}';
          return PageList(
            onRefresh: _data.reload,
            children: [
              PageTitle(
                eyebrow: manual ? 'Manual order' : 'Order',
                title: strOf(o['orderNumber']),
                subtitle:
                    '${manual ? 'Recorded' : 'Placed'} ${formatDate(o['createdAt'])} · ${o['paidOffline'] == true ? 'Paid offline (${titleCase(o['offlinePaymentMethod'])})' : titleCase(o['paymentMethod'])}',
              ),
              Section(
                title: widget.admin ? 'Order items' : 'Your items',
                subtitle: '${items.length} item${items.length == 1 ? '' : 's'}',
                trailing: Pill(o['orderStatus']),
                children: [
                  for (final it in items)
                    RecordCard(
                      leading: strOf(it['image']).isEmpty ? null : ProductImage(src: strOf(it['image']), size: 46, radius: 8),
                      title: strOf(it['name']),
                      subtitle: '${it['quantity']} × ${money(it['price'])}',
                      amount: money(numOf(it['price']) * numOf(it['quantity'])),
                    ),
                  KV('Subtotal', money(gross)),
                  if (coupon > 0) KV('Coupon ${asMap(o['coupon'])['code'] ?? ''}', '-${money(coupon)}'),
                  KV('MVEC platform fee (${d.commission.toStringAsFixed(d.commission % 1 == 0 ? 0 : 1)}%)', '-${money(fee)}'),
                  KV(
                    'Delivery${parcels.isNotEmpty && strOf(parcels.first['method']).isNotEmpty ? ' · ${titleCase(parcels.first['method'])}' : ''}',
                    delivery > 0
                        ? '+${money(delivery)}'
                        : waived > 0
                        ? 'Free (coupon, ${money(waived)} waived)'
                        : 'Free',
                  ),
                  const Divider(),
                  KV(widget.admin ? 'Vendor settlement' : 'You receive', money((subtotal - fee).clamp(0, double.infinity) + delivery), bold: true),
                  if (!widget.admin && asMaps(o['items']).length > items.length) const Tiny('This order also contains items from other sellers, which are not shown.'),
                ],
              ),
              Section(
                title: 'Customer',
                children: [
                  Text(strOf(customer['name'], personName(o['user'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (strOf(customer['phone']).isNotEmpty) Tiny(strOf(customer['phone'])),
                  if (strOf(customer['email'] ?? asMap(o['user'])['email']).isNotEmpty) Tiny(strOf(customer['email'] ?? asMap(o['user'])['email'])),
                  if (manual) Tiny(o['user'] != null ? 'Linked to the customer’s MVEC account' : 'Guest customer (no MVEC account)'),
                  Tiny(
                    isPickup(o)
                        ? 'The buyer collects this order from your store. Ask for their delivery code when you hand it over.'
                        : [
                          address['street'],
                          address['sector'],
                          address['district'] ?? address['city'],
                          address['province'] ?? address['state'],
                          address['country'],
                        ].where((x) => strOf(x).isNotEmpty).join(', ').ifEmpty('No address provided'),
                  ),
                  if (parcels.isNotEmpty && strOf(parcels.first['eta']).isNotEmpty) Tiny('Delivery promised: ${parcels.first['eta']}'),
                  const SizedBox(height: 8),
                  Row(children: [const Text('Payment  ', style: TextStyle(fontWeight: FontWeight.w700)), Pill(o['paymentStatus'])]),
                  if (manual && o['paymentStatus'] != 'PAID' && o['paymentMethod'] != 'CASH_ON_DELIVERY' && o['user'] != null) ...[
                    const SizedBox(height: 8),
                    ActionChipBtn('Copy payment link', icon: Icons.copy_rounded, onPressed: () => copyText(context, payLink, 'Payment link copied.')),
                  ],
                  if (strOf(o['sellerNote']).isNotEmpty) ...[const SizedBox(height: 8), const Text('Note', style: TextStyle(fontWeight: FontWeight.w700)), Tiny(strOf(o['sellerNote']))],
                ],
              ),
              if (!widget.admin)
                Section(
                  title: 'Next step',
                  children: [
                    if (next.isNotEmpty || canRecordCash(o) || allNext.contains('CANCELLED')) ...[
                      for (final s in next)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GradientButton(
                            label: stepLabelFor(o, s),
                            icon: s == 'SHIPPED' || s == 'READY_FOR_SHIPMENT' ? Icons.inventory_2_outlined : Icons.check_rounded,
                            loading: _updating,
                            onPressed: () => _update({'status': s}),
                          ),
                        ),
                      if (canRecordCash(o))
                        Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlineBtn(label: 'Cash received', onPressed: _updating ? null : () => _update({'paymentStatus': 'PAID'}))),
                      if (allNext.contains('CANCELLED'))
                        OutlineBtn(
                          label: 'Cancel order',
                          danger: true,
                          onPressed:
                              _updating
                                  ? null
                                  : () async {
                                    final reason = await askCancelReason(context, o);
                                    if (reason != null) await _update({'status': 'CANCELLED', 'reason': reason});
                                  },
                        ),
                    ] else
                      Tiny(
                        ['SHIPPED', 'OUT_FOR_DELIVERY'].contains(o['orderStatus'])
                            ? 'Delivery is confirmed when the courier verifies the buyer’s delivery code. Your funds are released then.'
                            : 'No further action needed.',
                      ),
                    if (strOf(o['cancellationReason']).isNotEmpty && o['orderStatus'] == 'CANCELLED') Tiny('Cancelled: ${o['cancellationReason']}'),
                  ],
                ),
              Section(
                title: 'Order progress',
                subtitle: 'From placement to delivery',
                children: [
                  if (idx == -1) Tiny('This order is ${titleCase(o['orderStatus']).toLowerCase()}.'),
                  for (var i = 0; i < flow.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        idx != -1 && i <= idx ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: idx != -1 && i <= idx ? MvColors.successText : context.mv.textMuted,
                        size: 20,
                      ),
                      title: Text(flowStepLabel(o, flow[i]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      subtitle: Text(
                        idx != -1 && i == idx
                            ? 'Current status'
                            : idx != -1 && i < idx
                            ? 'Completed'
                            : 'Upcoming',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

extension _IfEmpty on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ─── Manual order ────────────────────────────────────────────────────────────

const _payments = [
  ('COD', 'Cash on delivery', 'Customer pays when the order arrives.'),
  ('PAID_OFFLINE', 'Already paid', 'You received cash, MoMo or a bank transfer.'),
  ('LINK', 'MVEC payment link', 'Customer pays online; needs an MVEC account with this phone or email.'),
];

/// Record a sale made in person, by phone or on WhatsApp (`ManualOrderModal`).
class ManualOrderPage extends StatefulWidget {
  const ManualOrderPage({super.key});

  @override
  State<ManualOrderPage> createState() => _ManualOrderPageState();
}

class _Line {
  _Line(this.product, this.qty, this.price);
  final Map<String, dynamic> product;
  int qty;
  num price;
}

class _ManualOrderPageState extends State<ManualOrderPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _sector = TextEditingController();
  final _street = TextEditingController();
  final _fee = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  final _lines = <_Line>[];
  String _search = '';
  String _method = 'STANDARD';
  String _province = 'Kigali City';
  String _district = 'Gasabo';
  bool _manualFee = false;
  Map<String, dynamic>? _quote;
  bool _quoting = false;
  String _payment = 'COD';
  String _offline = 'CASH';
  bool _busy = false;
  String _error = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    vendorProducts().then((v) => mounted ? setState(() => _products = v.where((p) => p['status'] != 'INACTIVE').toList()) : null).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _sector, _street, _fee, _note]) {
      c.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  bool get _pickup => _method == 'PICKUP';
  num get _subtotal => _lines.fold<num>(0, (s, l) => s + l.price * l.qty);
  num? get _autoFee => _quote?['deliverable'] == true ? numOf(_quote!['shippingFee']) : null;
  num get _deliveryFee => _pickup || _manualFee ? numOf(_fee.text) : (_autoFee ?? 0);

  void _requote() {
    _debounce?.cancel();
    if (_pickup || _lines.isEmpty) {
      setState(() => _quote = null);
      return;
    }
    setState(() => _quoting = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final q = await jpost('/shipping/quote', {
          'address': {'province': _province, 'district': _district},
          'method': _method,
          'items': [
            for (final l in _lines) {'productId': l.product['id'], 'qty': l.qty},
          ],
        });
        if (mounted) setState(() => _quote = q);
      } catch (_) {
        if (mounted) setState(() => _quote = null);
      } finally {
        if (mounted) setState(() => _quoting = false);
      }
    });
  }

  void _add(Map<String, dynamic> p) {
    final existing = _lines.where((l) => l.product['id'] == p['id']).firstOrNull;
    setState(() {
      if (existing != null) {
        existing.qty += 1;
      } else {
        _lines.add(_Line(p, 1, numOf(p['discountPrice']) > 0 ? numOf(p['discountPrice']) : numOf(p['price'])));
      }
      _search = '';
    });
    _requote();
  }

  Future<void> _submit() async {
    setState(() => _error = '');
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) return setState(() => _error = "Enter the customer's name and phone.");
    if (_lines.isEmpty) return setState(() => _error = 'Add at least one product.');
    final short = _lines.where((l) => l.qty > numOf(l.product['stockQuantity'])).firstOrNull;
    if (short != null) return setState(() => _error = 'Only ${short.product['stockQuantity']} units of ${short.product['name']} are in stock.');
    if (!_pickup && _street.text.trim().isEmpty) return setState(() => _error = 'Enter the street or a landmark.');
    if (!_pickup && !_manualFee && _quote != null && _quote!['deliverable'] != true) {
      return setState(() => _error = 'Your shipping zones don’t cover this district. Set the delivery fee manually or choose pickup.');
    }
    setState(() => _busy = true);
    try {
      final res = await jpost('/orders/vendor/manual', {
        'customer': {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim()},
        'items': [
          for (final l in _lines) {'productId': l.product['id'], 'qty': l.qty, 'price': l.price},
        ],
        'shippingAddress': {'province': _province, 'district': _district, 'sector': _sector.text.trim(), 'street': _street.text.trim()},
        'shippingMethod': _method,
        if (_pickup || _manualFee) 'deliveryFee': numOf(_fee.text),
        'payment': _payment,
        if (_payment == 'PAID_OFFLINE') 'offlineMethod': _offline,
        'note': _note.text.trim(),
      });
      if (!mounted) return;
      final link = strOf(res['paymentLink']);
      if (link.isNotEmpty) {
        final full = '$webOrigin$link';
        await showDialog<void>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Order created'),
                content: Text('${strOf(res['message'])} Send this link to the customer; they pay after signing in to MVEC.\n\n$full'),
                actions: [
                  TextButton(onPressed: () => copyText(ctx, full, 'Payment link copied.'), child: const Text('Copy link')),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('View order')),
                ],
              ),
        );
      }
      if (mounted) Navigator.of(context).pop(res);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorText(e));
        toast(context, errorText(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _input(TextEditingController c, String label, {String? hint, TextInputType? type, ValueChanged<String>? onChanged, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: c, keyboardType: type, minLines: 1, maxLines: lines, decoration: InputDecoration(labelText: label, hintText: hint), onChanged: onChanged),
  );

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final results = _search.trim().isEmpty ? <Map<String, dynamic>>[] : _products.where((p) => matches(_search, [p['name'], p['sku'], p['brand']])).take(6).toList();
    final total = _subtotal + _deliveryFee;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Cancel', onPressed: () => Navigator.of(context).pop()), title: const Text('New manual order')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const Tiny('Record a sale made in person, by phone or on WhatsApp. Stock is reserved straight away.'),
            if (_error.isNotEmpty) Notice(text: _error),
            Section(
              title: 'Customer',
              children: [
                _input(_name, 'Name *'),
                _input(_phone, 'Phone *', hint: '07xx xxx xxx', type: TextInputType.phone),
                _input(_email, 'Email', hint: 'Optional', type: TextInputType.emailAddress),
                const Tiny('If the phone or email matches an MVEC buyer, the order appears in their account.'),
              ],
            ),
            Section(
              title: 'Products',
              children: [
                SearchBox(hint: 'Search your products by name or SKU', onChanged: (v) => setState(() => _search = v)),
                for (final p in results)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: numOf(p['stockQuantity']) > 0,
                    title: Text(strOf(p['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${p['sku'] ?? ''} · ${p['stockQuantity']} in stock'),
                    trailing: Text(money(numOf(p['discountPrice']) > 0 ? p['discountPrice'] : p['price']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => _add(p),
                  ),
                if (_search.trim().isNotEmpty && results.isEmpty) const Tiny('No products match.'),
                if (_lines.isEmpty) const Tiny('Search above to add products.'),
                for (final l in _lines)
                  RecordCard(
                    title: strOf(l.product['name']),
                    subtitle: '${l.product['stockQuantity']} in stock',
                    amount: money(l.price * l.qty),
                    actions: [
                      QtyStepper(
                        value: l.qty,
                        max: numOf(l.product['stockQuantity'], 1).toInt().clamp(1, 9999),
                        onChanged: (v) {
                          setState(() => l.qty = v);
                          _requote();
                        },
                      ),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          initialValue: '${l.price}',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Unit price', isDense: true),
                          onChanged: (v) => setState(() => l.price = numOf(v)),
                        ),
                      ),
                      ActionChipBtn(
                        'Remove',
                        danger: true,
                        onPressed: () {
                          setState(() => _lines.remove(l));
                          _requote();
                        },
                      ),
                    ],
                  ),
              ],
            ),
            Section(
              title: 'Delivery',
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'STANDARD', label: Text('Standard')),
                    ButtonSegment(value: 'EXPRESS', label: Text('Express')),
                    ButtonSegment(value: 'PICKUP', label: Text('Pickup')),
                  ],
                  selected: {_method},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _method = s.first);
                    _requote();
                  },
                ),
                const SizedBox(height: 12),
                if (!_pickup) ...[
                  FilterSelect(
                    label: 'Province',
                    value: _province,
                    options: [for (final p in rwandaLocations.keys) (p, p)],
                    onChanged: (v) {
                      setState(() {
                        _province = v;
                        _district = rwandaLocations[v]!.first;
                      });
                      _requote();
                    },
                  ),
                  const SizedBox(height: 10),
                  FilterSelect(
                    label: 'District',
                    value: _district,
                    options: [for (final d in rwandaLocations[_province]!) (d, d)],
                    onChanged: (v) {
                      setState(() => _district = v);
                      _requote();
                    },
                  ),
                  const SizedBox(height: 10),
                  _input(_sector, 'Sector', hint: 'Optional'),
                  _input(_street, 'Street / landmark *'),
                  if (!_manualFee)
                    Tiny(
                      _lines.isEmpty
                          ? 'Add products to calculate delivery.'
                          : _quoting || _quote == null
                          ? 'Calculating…'
                          : _quote!['deliverable'] == true
                          ? 'From your zones: ${_autoFee == 0 ? 'Free' : money(_autoFee)}${strOf(asMaps(_quote!['groups']).firstOrNull?['eta']).isNotEmpty ? ' · ${asMaps(_quote!['groups']).first['eta']}' : ''}'
                          : 'Your zones don’t cover this district.',
                      color: _quote != null && _quote!['deliverable'] != true ? MvColors.errorText : null,
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Set fee manually', style: TextStyle(fontSize: 14)),
                    value: _manualFee,
                    onChanged:
                        (on) => setState(() {
                          _manualFee = on;
                          if (on && _autoFee != null) _fee.text = '$_autoFee';
                        }),
                  ),
                  if (_manualFee) _input(_fee, 'Delivery fee (RWF)', type: TextInputType.number, onChanged: (_) => setState(() {})),
                ] else ...[
                  const Tiny('The customer collects the order from your store.'),
                  _input(_fee, 'Pickup fee (RWF)', hint: '0', type: TextInputType.number, onChanged: (_) => setState(() {})),
                ],
              ],
            ),
            Section(
              title: 'Payment',
              children: [
                RadioGroup<String>(
                  groupValue: _payment,
                  onChanged: (v) => setState(() => _payment = v ?? 'COD'),
                  child: Column(
                    children: [
                      for (final (v, l, d) in _payments)
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: v,
                          title: Text(l, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(d, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                if (_payment == 'PAID_OFFLINE')
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'CASH', label: Text('Cash')), ButtonSegment(value: 'MOMO', label: Text('MoMo')), ButtonSegment(value: 'BANK', label: Text('Bank'))],
                    selected: {_offline},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _offline = s.first),
                  ),
                if (_payment != 'LINK') const Tiny("You collect this payment yourself, so it isn't added to your MVEC balance."),
                const SizedBox(height: 8),
                _input(_note, 'Note', hint: 'Optional, e.g. gift wrap, call before delivery', lines: 3),
              ],
            ),
            DataCard(
              child: Column(
                children: [KV('Products', money(_subtotal)), KV('Delivery', _deliveryFee == 0 ? 'Free' : money(_deliveryFee)), Divider(color: mv.border), KV('Total', money(total), bold: true)],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: GradientButton(label: 'Create order · ${money(total)}', loading: _busy, onPressed: _lines.isEmpty ? null : _submit)),
      ),
    );
  }
}
