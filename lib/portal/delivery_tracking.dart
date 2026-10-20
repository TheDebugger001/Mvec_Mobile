import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../state/auth_state.dart';
import '../widgets/common.dart';
import 'api.dart';
import 'kit.dart';

// Deliveries for the seller, supplier, courier and admin (`DeliveryTracking`).
// The last step is reached only with the buyer's 6-digit delivery code, which
// also releases the held payment.

const _retailSteps = ['CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'];
const _retailAlias = {'PENDING': -1, 'COMPLETED': 5};
const _pickupSteps = ['CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT', 'DELIVERED'];
const _pickupAlias = {'PENDING': -1, 'COMPLETED': 3};
const _pickupLabel = {'READY_FOR_SHIPMENT': 'Ready for pickup', 'DELIVERED': 'Collected'};
const _wholesaleSteps = ['PENDING_PAYMENT', 'ESCROW_HELD', 'SHIPPED', 'DELIVERED', 'CONFIRMED_RELEASED'];
const _stepLabel = {
  'CONFIRMED': 'Paid',
  'PROCESSING': 'Preparing',
  'READY_FOR_SHIPMENT': 'Packed',
  'OUT_FOR_DELIVERY': 'On the way',
  'PENDING_PAYMENT': 'Unpaid',
  'ESCROW_HELD': 'Paid',
  'CONFIRMED_RELEASED': 'Settled',
};
const _nextAction = {
  'CONFIRMED': ('PROCESSING', 'Start preparing'),
  'PROCESSING': ('READY_FOR_SHIPMENT', 'Mark packed'),
  'READY_FOR_SHIPMENT': ('SHIPPED', 'Mark shipped'),
  'SHIPPED': ('OUT_FOR_DELIVERY', 'Out for delivery'),
};
const _closedStates = ['CANCELLED', 'RETURNED', 'REFUNDED', 'FAILED', 'DISPUTED'];
const _doneStates = ['DELIVERED', 'COMPLETED', 'CONFIRMED_RELEASED'];

String _nameOf(dynamic u, String fallback) => u is Map ? strOf(u['companyName'] ?? u['Fullname'] ?? u['fullName'] ?? u['name'], fallback) : fallback;
bool _isCod(Map<String, dynamic> o) => o['paymentMethod'] == 'CASH_ON_DELIVERY' && o['paymentStatus'] != 'PAID';

class _Delivery {
  _Delivery({
    required this.raw,
    required this.id,
    required this.number,
    required this.title,
    required this.party,
    required this.amount,
    required this.status,
    required this.date,
    required this.steps,
    required this.step,
    required this.settlement,
    required this.closed,
    required this.done,
    required this.held,
    required this.relevant,
    this.pickup = false,
    this.attention = '',
    this.sellers = '',
    this.phone = '',
    this.place = '',
    this.eta = '',
    this.method = '',
    this.courier,
    this.link,
    this.next,
    this.canPickUp = false,
    this.canAssign = false,
    this.canConfirm = false,
    this.handedOver = false,
    this.canShip = false,
  });

  final Map<String, dynamic> raw;
  final String id, number, title, party, status, attention, sellers, phone, place, eta, method;
  final num amount;
  final dynamic date;
  final List<String> steps;
  final int step;
  final (String, StatusTone, String) settlement;
  final bool closed, done, held, relevant, pickup, canPickUp, canAssign, canConfirm, handedOver, canShip;
  final dynamic courier;
  final String? link;
  final (String, String)? next;
}

(String, StatusTone, String) _retailSettlement(Map<String, dynamic> o) {
  if (_closedStates.contains(o['orderStatus']) || o['paymentStatus'] == 'DISPUTED') {
    return (titleCase(o['paymentStatus'] == 'DISPUTED' ? 'DISPUTED' : o['orderStatus']), StatusTone.bad, 'Not settled');
  }
  if (_isCod(o)) return ('Cash on delivery', StatusTone.warn, 'Collect from the buyer');
  if (o['paidOffline'] == true) return ('Paid offline', StatusTone.good, 'Settled outside MVEC');
  if (o['paymentStatus'] != 'PAID') return ('Awaiting payment', StatusTone.warn, 'Not yet paid');
  if (_doneStates.contains(o['orderStatus'])) return ('Released', StatusTone.good, "Added to the seller's balance");
  return ('Held by MVEC', StatusTone.warn, 'Released after delivery');
}

double _daysSince(dynamic d) {
  final t = parseDate(d);
  return t == null ? 0 : DateTime.now().difference(t).inMinutes / 1440;
}

_Delivery _retail(Map<String, dynamic> o, String role, String userId) {
  final all = asMaps(o['items']);
  final mine = role == 'vendor' ? all.where((i) => idOf(i['vendor']) == userId).toList() : all;
  final items = mine.isNotEmpty ? mine : all;
  final first = items.firstOrNull;
  final parcel = asMaps(o['shippingBreakdown']).firstOrNull;
  final address = asMap(o['shippingAddress']);
  final status = '${o['orderStatus']}';
  final payable = o['paymentStatus'] == 'PAID' || (o['paymentMethod'] == 'CASH_ON_DELIVERY' && o['paymentStatus'] == 'PENDING' && status != 'PENDING');
  final closed = _closedStates.contains(status) || o['paymentStatus'] == 'DISPUTED';
  final done = _doneStates.contains(status);
  final handedOver = role == 'vendor' && (o['deliveredVendors'] is List ? (o['deliveredVendors'] as List).map((x) => '$x') : const <String>[]).contains(userId);
  final active = payable && !closed && !done;
  final pickup = o['shippingMethod'] == 'PICKUP';
  var attention = '';
  if (active) {
    if (['SHIPPED', 'OUT_FOR_DELIVERY'].contains(status) && _daysSince(o['shippedAt'] ?? o['updatedAt']) > 2) {
      attention = "On the way for ${_daysSince(o['shippedAt'] ?? o['updatedAt']).floor()} days without the buyer's code";
    } else if (!pickup && ['CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT'].contains(status) && _daysSince(o['paidAt'] ?? o['createdAt']) > 3) {
      attention = 'Paid ${_daysSince(o['paidAt'] ?? o['createdAt']).floor()} days ago and not shipped';
    } else if (pickup && status == 'READY_FOR_SHIPMENT' && _daysSince(o['updatedAt']) > 7) {
      attention = 'Ready for pickup for ${_daysSince(o['updatedAt']).floor()} days, not collected';
    }
  }
  final steps = pickup ? _pickupSteps : _retailSteps;
  final next =
      pickup && status == 'READY_FOR_SHIPMENT'
          ? null
          : status == 'PROCESSING' && pickup
          ? ('READY_FOR_SHIPMENT', 'Mark ready for pickup')
          : _nextAction[status];
  final recipient = asMap(o['recipient']);
  final customer = asMap(o['customer']);
  return _Delivery(
    raw: o,
    pickup: pickup,
    attention: attention,
    id: idOf(o),
    number: strOf(o['orderNumber']),
    title: first == null ? 'Order' : '${first['quantity']} × ${first['name']}${items.length > 1 ? ' +${items.length - 1} more' : ''}',
    sellers: {for (final i in all) _nameOf(i['vendor'], '')}.where((x) => x.isNotEmpty).join(', '),
    party: strOf(recipient['name'] ?? customer['name'], _nameOf(o['user'], 'Buyer')),
    phone: strOf(recipient['phone'] ?? customer['phone'] ?? asMap(o['user'])['phone']),
    place: pickup ? 'Buyer collects from the store' : [address['street'], address['sector'], address['district'] ?? address['city'], address['province']].where((x) => strOf(x).isNotEmpty).join(', '),
    eta: strOf(parcel?['eta']),
    method: titleCase(o['shippingMethod'] ?? o['deliveryMethod'] ?? 'STANDARD'),
    courier: o['courier'],
    amount: role == 'vendor' ? numOf(o['vendorSubtotal']) + numOf(o['vendorShippingFee']) : numOf(o['totalAmount']),
    status: status,
    date: o['createdAt'],
    steps: steps,
    step: (pickup ? _pickupAlias : _retailAlias)[status] ?? steps.indexOf(status),
    settlement: _retailSettlement(o),
    closed: closed,
    done: done,
    handedOver: handedOver,
    relevant: payable || closed || done,
    held: o['paymentStatus'] == 'PAID' && o['paidOffline'] != true && active,
    link:
        role == 'vendor'
            ? '/vendor/orders/${idOf(o)}'
            : role == 'admin'
            ? '/admin/orders/${idOf(o)}'
            : null,
    next: active && !handedOver && (role == 'vendor' || role == 'admin') ? next : null,
    canPickUp: active && !pickup && role == 'delivery' && status != 'OUT_FOR_DELIVERY',
    canAssign: active && role == 'admin',
    canConfirm: active && !handedOver && ['vendor', 'admin', 'delivery'].contains(role),
  );
}

_Delivery _wholesale(Map<String, dynamic> o) {
  final status = '${o['status']}';
  final done = status == 'CONFIRMED_RELEASED';
  final held = ['ESCROW_HELD', 'SHIPPED', 'DELIVERED'].contains(status);
  final items = asMaps(o['items']);
  return _Delivery(
    raw: o,
    id: idOf(o),
    number: strOf(o['orderNumber']),
    title: '${items.firstOrNull?['productName'] ?? 'Wholesale order'}${items.length > 1 ? ' +${items.length - 1} more' : ''}',
    party: _nameOf(o['vendor'], 'Vendor'),
    amount: numOf(o['totalAmount']),
    status: status,
    date: o['createdAt'],
    steps: _wholesaleSteps,
    step: _wholesaleSteps.indexOf(status),
    settlement:
        done
            ? ('Released', StatusTone.good, 'Added to your balance')
            : held
            ? ('Held in escrow', StatusTone.warn, 'Released when the vendor confirms')
            : _closedStates.contains(status)
            ? (titleCase(status), StatusTone.bad, 'Not settled')
            : ('Awaiting payment', StatusTone.warn, 'Vendor has not paid yet'),
    closed: _closedStates.contains(status),
    done: done,
    held: held,
    relevant: true,
    canShip: status == 'ESCROW_HELD',
  );
}

const _copy = {
  'vendor': ('Delivery & settlement', "Move each paid order to the buyer, then confirm with the buyer's 6-digit code to release your money."),
  'supplier': ('Delivery & settlement', 'Ship paid wholesale orders. Funds are released when the vendor confirms receipt.'),
  'admin': (
    'Deliveries',
    'Orders that need action first: stuck on the way, paid but not shipped, or waiting for pickup. Sellers deliver their own orders; assign an MVEC courier here once you have courier accounts.',
  ),
  'delivery': ('My deliveries', 'Deliveries assigned to you. Ask the buyer for their 6-digit code when you hand over the items.'),
};

/// Delivery list with steps, settlement state and each role's actions.
class DeliveryTrackingPage extends ConsumerStatefulWidget {
  const DeliveryTrackingPage({super.key, required this.role, this.initialTab = 'active', this.header});
  final String role;
  final String initialTab;

  /// Shown above the list (the courier dashboard's intro card).
  final Widget? header;

  @override
  ConsumerState<DeliveryTrackingPage> createState() => _DeliveryTrackingPageState();
}

class _DeliveryTrackingPageState extends ConsumerState<DeliveryTrackingPage> {
  bool get _wholesaleRole => widget.role == 'supplier';
  late final _data = Loader(() async {
    final userId = ref.read(authProvider).user?.id ?? '';
    final path =
        _wholesaleRole
            ? '/wholesale/orders/mine'
            : widget.role == 'vendor'
            ? '/orders/vendor/orders'
            : widget.role == 'admin'
            ? '/orders'
            : '/orders/deliverable';
    final res = await jget(path);
    final list = asMaps(res['orders'] ?? res['data']);
    final balance = widget.role == 'vendor' ? asMap((await jget('/payouts/balance').catchError((_) => <String, dynamic>{}))['balance']) : <String, dynamic>{};
    final couriers = widget.role == 'admin' ? await jlist('/users', 'data', {'role': 'delivery', 'limit': 100}).catchError((_) => <Map<String, dynamic>>[]) : <Map<String, dynamic>>[];
    return (orders: [for (final o in list) _wholesaleRole ? _wholesale(o) : _retail(o, widget.role, userId)], balance: balance, couriers: couriers);
  });
  late String _tab = widget.role == 'admin' ? 'attention' : widget.initialTab;
  String _q = '';
  String _busy = '';
  final _codes = <String, TextEditingController>{};
  final _feedback = <String, (bool, String)>{};

  @override
  void dispose() {
    _data.dispose();
    for (final c in _codes.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _code(String id) => _codes.putIfAbsent(id, TextEditingController.new);

  Future<void> _act(_Delivery o, Future<Map<String, dynamic>> Function() fn, String fallback) async {
    setState(() {
      _busy = o.id;
      _feedback.remove(o.id);
    });
    try {
      final res = await fn();
      _feedback[o.id] = (true, strOf(res['message'], fallback));
      await _data.reload();
    } catch (e) {
      _feedback[o.id] = (false, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, desc) = _copy[widget.role] ?? _copy['vendor']!;
    return PortalPage(
      eyebrow: 'Delivery & settlement',
      title: title,
      subtitle: desc,
      onRefresh: _data.reload,
      children: [
        if (widget.header != null) widget.header!,
        LoadView(
          loader: _data,
          loadingLabel: 'Loading deliveries…',
          builder: (d) {
            final relevant = d.orders.where((o) => o.relevant).toList();
            final counts = {
              'attention': relevant.where((o) => o.attention.isNotEmpty).length,
              'active': relevant.where((o) => !o.done && !o.closed).length,
              'done': relevant.where((o) => o.done).length,
              'all': relevant.length,
            };
            final shown =
                relevant
                    .where(
                      (o) =>
                          _tab == 'attention'
                              ? o.attention.isNotEmpty
                              : _tab == 'active'
                              ? !o.done && !o.closed
                              : _tab == 'done'
                              ? o.done
                              : true,
                    )
                    .where((o) => matches(_q, [o.number, o.title, o.party, o.phone, o.place]))
                    .toList();
            final heldTotal = relevant.where((o) => o.held).fold<num>(0, (n, o) => n + o.amount);
            final releasedTotal = relevant.where((o) => o.done && o.settlement.$1 == 'Released').fold<num>(0, (n, o) => n + o.amount);
            final steps =
                _wholesaleRole
                    ? const [('Vendor pays', 'Funds are locked in escrow.'), ('You ship', 'Mark the order as shipped.'), ('Vendor confirms', 'Payment is released to you.')]
                    : const [('Buyer pays', 'MVEC holds the money.'), ('Parcel delivered', 'The buyer shares their 6-digit code.'), ('Funds released', "The amount moves to the seller's balance.")];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(icon: 'box', label: 'In progress', value: '${counts['active']}', sub: _wholesaleRole ? 'Wholesale orders' : 'Parcels on the way'),
                    MetricCard(icon: 'shield', label: 'Held until delivery', value: money(heldTotal), sub: 'Protected by MVEC'),
                    if (widget.role == 'vendor' && d.balance.isNotEmpty) ...[
                      MetricCard(icon: 'wallet', label: 'Available balance', value: money(d.balance['availableBalance']), sub: 'Withdraw from Payouts'),
                      MetricCard(icon: 'chart', label: 'Total earned', value: money(d.balance['totalEarned']), sub: '${money(d.balance['pendingBalance'])} pending'),
                    ] else ...[
                      MetricCard(icon: 'check', label: 'Delivered', value: '${counts['done']}', sub: 'Completed orders'),
                      MetricCard(icon: 'wallet', label: 'Released', value: money(releasedTotal), sub: 'Settled after delivery'),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                DataCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    children: [
                      for (final (i, (t, s)) in steps.indexed)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 12,
                            backgroundColor: context.mv.soft,
                            child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: context.mv.accentDeep, fontWeight: FontWeight.w800)),
                          ),
                          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          subtitle: Text(s, style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                if (!_wholesaleRole)
                  const InfoBox(title: '🔒 Protected funds', text: "Only enter the buyer's code once they have the items in hand. Never accept the code over the phone before delivery."),
                TabChips(
                  tabs: [if (widget.role == 'admin') ('attention', 'Needs attention'), ('active', 'In progress'), ('done', 'Delivered'), ('all', 'All')],
                  value: _tab,
                  counts: counts,
                  onChanged: (v) => setState(() => _tab = v),
                ),
                SearchBox(hint: _wholesaleRole ? 'Search order, vendor or product…' : 'Search order, buyer, product or place…', onChanged: (v) => setState(() => _q = v)),
                Paged<_Delivery>(
                  items: shown,
                  perPage: 6,
                  empty: EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title:
                        _q.isNotEmpty
                            ? 'No deliveries match your search'
                            : _tab == 'attention'
                            ? 'Nothing needs your attention'
                            : _tab == 'done'
                            ? 'Nothing delivered yet'
                            : 'No deliveries in progress',
                    message: _wholesaleRole ? 'Paid wholesale orders you need to ship will appear here.' : 'Paid orders appear here as they move towards the buyer.',
                  ),
                  itemBuilder: (o) => _card(o, d.couriers),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card(_Delivery o, List<Map<String, dynamic>> couriers) {
    final mv = context.mv;
    final busy = _busy == o.id;
    final note = _feedback[o.id];
    final code = _code(o.id);
    return DataCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: o.link == null ? null : () => context.push(o.link!),
                      child: Text(o.number, style: TextStyle(fontWeight: FontWeight.w800, color: o.link == null ? mv.text : mv.accentDeep)),
                    ),
                    Text(o.title, style: TextStyle(color: mv.text, fontSize: 13)),
                    Tiny('${o.party}${o.phone.isNotEmpty ? ' · ${o.phone}' : ''} · ${formatDate(o.date)}'),
                    if (o.place.isNotEmpty) Tiny('Deliver to: ${o.place}'),
                    if (o.sellers.isNotEmpty && widget.role != 'vendor') Tiny('Seller: ${o.sellers}'),
                    if (o.courier != null && widget.role == 'admin') Tiny('Courier: ${_nameOf(o.courier, 'Assigned')}'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(o.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  StatusChip(o.settlement.$1, tone: o.settlement.$2),
                  SizedBox(width: 110, child: Text(o.settlement.$3, textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: mv.textMuted))),
                ],
              ),
            ],
          ),
          if (o.attention.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(text: o.attention)),
          const SizedBox(height: 10),
          if (o.closed)
            Tiny(
              'This order is ${titleCase(o.raw['paymentStatus'] == 'DISPUTED' ? 'DISPUTED' : o.status).toLowerCase()} and will not be delivered${o.raw['paymentStatus'] == 'DISPUTED' ? ' until MVEC resolves the dispute' : ''}.',
            )
          else
            Row(
              children: [
                for (final (i, s) in o.steps.indexed)
                  Expanded(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor:
                              i < o.step || (o.done && i == o.step)
                                  ? MvColors.successText
                                  : i == o.step
                                  ? MvColors.primaryDark
                                  : mv.soft,
                          child:
                              i < o.step || (o.done && i == o.step)
                                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                  : Text('${i + 1}', style: TextStyle(fontSize: 10, color: i == o.step ? Colors.white : mv.textMuted, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 3),
                        Text((o.pickup ? _pickupLabel[s] : null) ?? _stepLabel[s] ?? titleCase(s), textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 9.5, color: mv.textMuted)),
                      ],
                    ),
                  ),
              ],
            ),
          if (!o.closed && (o.eta.isNotEmpty || (!_wholesaleRole && o.method.isNotEmpty))) Tiny([if (!_wholesaleRole) o.method, if (o.eta.isNotEmpty) 'Promised: ${o.eta}'].join(' · ')),
          if (o.next != null || o.canPickUp || (o.canAssign && couriers.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (o.next != null)
                  ActionChipBtn(
                    o.next!.$2,
                    busy: busy,
                    onPressed: () => _act(o, () => jpatch('/orders/vendor/status', {'orderId': o.id, 'status': o.next!.$1}), 'Updated. The buyer has been notified.'),
                  ),
                if (o.canPickUp)
                  ActionChipBtn(
                    'Picked up · out for delivery',
                    busy: busy,
                    onPressed: () => _act(o, () => jpatch('/orders/${o.id}/out-for-delivery'), 'Marked as out for delivery. The buyer has been notified.'),
                  ),
                if (o.canAssign && couriers.isNotEmpty)
                  SizedBox(
                    width: 220,
                    child: FilterSelect(
                      label: 'Courier',
                      value: idOf(o.courier),
                      options: [('', 'Assign a courier…'), for (final c in couriers) (idOf(c), strOf(c['Fullname'] ?? c['fullName'] ?? c['phone']))],
                      onChanged: (v) => _act(o, () => jpatch('/orders/${o.id}/courier', {'courierId': v.isEmpty ? null : v}), 'Courier updated.'),
                    ),
                  ),
              ],
            ),
          ],
          if (o.canConfirm) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: '••••••', counterText: '', isDense: true, labelText: "Buyer's code"),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                ActionChipBtn(
                  o.pickup ? 'Confirm pickup' : 'Confirm delivery',
                  icon: Icons.check_rounded,
                  primary: true,
                  busy: busy,
                  onPressed:
                      code.text.length != 6
                          ? null
                          : () {
                            final c = code.text;
                            code.clear();
                            _act(o, () => jpatch('/orders/${o.id}/deliver', {'deliveryOtp': c}), '${o.number} delivered. The payment is released.');
                          },
                ),
              ],
            ),
            Tiny(_isCod(o.raw) ? "Collect the cash, then enter the code shown on the buyer's order page." : "Enter the code shown on the buyer's order page. It releases the held payment."),
          ],
          if (o.handedOver && !o.done) const Tiny('Your items are delivered and your payment is released. Waiting for the other sellers in this order.', color: MvColors.successText),
          if (o.canShip) ...[
            const SizedBox(height: 8),
            ActionChipBtn(
              'Mark as shipped',
              icon: Icons.local_shipping_outlined,
              primary: true,
              busy: busy,
              onPressed: () => _act(o, () => jpost('/wholesale/orders/${o.id}/ship'), '${o.number} marked as shipped.'),
            ),
            const Tiny("The vendor's payment is already secured in escrow."),
          ],
          if (note != null && note.$2.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(text: note.$2, ok: note.$1)),
        ],
      ),
    );
  }
}
