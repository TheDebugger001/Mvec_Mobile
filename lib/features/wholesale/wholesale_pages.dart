import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

// Wholesale between sellers (buying stock) and suppliers (selling it), same
// as the web's pages/Wholesale.jsx and VendorNetwork.jsx.

String partyName(dynamic p) => p is Map ? strOf(p['companyName'] ?? p['Fullname'] ?? p['fullName'] ?? p['email'], '—') : '—';
num _units(Map<String, dynamic> o) => asMaps(o['items']).fold<num>(0, (n, i) => n + numOf(i['quantity']));

/// status -> label, tone, what it means for the seller, for the supplier.
const _status = {
  'PENDING_PAYMENT': ('Waiting for payment', StatusTone.warn, 'Pay within 48 hours or the order expires and the stock is released.', 'The vendor has not paid yet. Do not ship.'),
  'ESCROW_HELD': (
    'Paid · MVEC holds the money',
    StatusTone.warn,
    'The supplier has 7 days to ship. You can still cancel for a full refund.',
    'Paid. Ship within 7 days or the order is cancelled and refunded.',
  ),
  'SHIPPED': (
    'Shipped',
    StatusTone.warn,
    'Confirm when the goods arrive, or report a problem. After 7 days the supplier is paid automatically.',
    'Waiting for the vendor to confirm. You are paid automatically after 7 days if no problem is reported.',
  ),
  'DELIVERED': ('Delivered', StatusTone.warn, 'Confirm receipt to pay the supplier.', 'Waiting for the vendor to confirm receipt.'),
  'CONFIRMED_RELEASED': ('Completed', StatusTone.good, 'Received. The supplier was paid.', "Completed. The money (minus MVEC's commission) is in your balance."),
  'DISPUTED': ('Problem reported', StatusTone.bad, 'MVEC is reviewing the problem; the money stays on hold.', 'The vendor reported a problem. MVEC will decide; the money stays on hold.'),
  'CANCELLED': ('Cancelled', StatusTone.bad, 'Cancelled. If you had paid, the money is being refunded.', 'Cancelled.'),
};

StatusChip wholesaleChip(dynamic s) {
  final x = _status['$s'];
  return StatusChip(x?.$1 ?? titleCase(s), tone: x?.$2 ?? StatusTone.warn);
}

const _active = ['PENDING_PAYMENT', 'ESCROW_HELD', 'SHIPPED', 'DELIVERED', 'DISPUTED'];

/// `/vendor/purchases` (role vendor) and `/supplier/orders` (role supplier).
class WholesaleOrdersPage extends StatefulWidget {
  const WholesaleOrdersPage({super.key, required this.supplier, this.notice});
  final bool supplier;
  final String? notice;

  @override
  State<WholesaleOrdersPage> createState() => _WholesaleOrdersPageState();
}

class _WholesaleOrdersPageState extends State<WholesaleOrdersPage> {
  late final _data = Loader(() => jlist('/wholesale/orders/mine', 'orders', {'limit': 100}));
  String _tab = 'ACTIVE';
  String _busy = '';
  String _q = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _data.reload());
    if (widget.notice != null) WidgetsBinding.instance.addPostFrameCallback((_) => toast(context, widget.notice!));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _data.dispose();
    super.dispose();
  }

  Future<void> _run(Map<String, dynamic> o, Future<dynamic> Function() fn, String text, [String? confirm]) async {
    if (confirm != null && !await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = idOf(o));
    final ok = await runAction(context, fn, success: text);
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  Future<void> _reason(Map<String, dynamic> o, {required bool problem}) async {
    final ok = await showFormSheet<bool>(
      context,
      title: problem ? 'Report a problem with ${o['orderNumber']}' : 'Cancel ${o['orderNumber']}',
      subtitle:
          problem
              ? 'MVEC holds the payment while it reviews. Describe what you received and what you expected.'
              : (o['status'] == 'ESCROW_HELD' ? 'The vendor is refunded in full.' : 'The vendor has not paid yet.'),
      fields: [FieldSpec('reason', problem ? 'What is wrong?' : "Why can't you fulfil it? The vendor sees this.", type: FieldType.textarea, required: true)],
      submitLabel: problem ? 'Report problem' : 'Cancel order',
      danger: !problem,
      onSubmit: (v) async {
        final reason = '${v['reason']}'.trim();
        if (reason.length < (problem ? 10 : 5)) throw ApiException('Write at least ${problem ? 10 : 5} characters.');
        if (problem) {
          await jpost('/wholesale/orders/${idOf(o)}/report-problem', {'reason': reason});
        } else {
          await jpost('/wholesale/orders/${idOf(o)}/cancel', {'reason': reason});
        }
        return true;
      },
    );
    if (ok == true && mounted) {
      toast(context, problem ? 'Problem reported. MVEC will review it; the payment stays on hold.' : 'Order cancelled. The vendor was told.');
      _data.reload();
    }
  }

  Future<void> _pay(Map<String, dynamic> o) async {
    final paid = await showModalBottomSheet<String>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => PayWholesaleSheet(order: o));
    if (paid != null && mounted) {
      toast(context, paid);
      _data.reload();
    }
  }

  List<Widget> _actions(Map<String, dynamic> o) {
    final b = _busy == idOf(o);
    final s = o['status'];
    if (!widget.supplier) {
      return [
        if (s == 'PENDING_PAYMENT') ActionChipBtn('Pay now', icon: Icons.account_balance_wallet_outlined, primary: true, onPressed: () => _pay(o)),
        if (['SHIPPED', 'DELIVERED', 'ESCROW_HELD'].contains(s))
          ActionChipBtn(
            'Confirm receipt',
            icon: Icons.check_rounded,
            primary: true,
            busy: b,
            onPressed:
                () => _run(
                  o,
                  () => jpost('/wholesale/orders/${idOf(o)}/confirm-receipt'),
                  '${o['orderNumber']} confirmed. The supplier has been paid.',
                  'Confirm you received everything in ${o['orderNumber']}? ${money(o['totalAmount'])} is released to ${partyName(o['supplier'])}. This cannot be undone.',
                ),
          ),
        if (['SHIPPED', 'DELIVERED', 'ESCROW_HELD'].contains(s)) ActionChipBtn('Report a problem', busy: b, onPressed: () => _reason(o, problem: true)),
        if (['PENDING_PAYMENT', 'ESCROW_HELD'].contains(s))
          ActionChipBtn(
            'Cancel',
            danger: true,
            busy: b,
            onPressed:
                () => _run(
                  o,
                  () => jpost('/wholesale/orders/${idOf(o)}/cancel', {'reason': ''}),
                  '${o['orderNumber']} cancelled.${s == 'ESCROW_HELD' ? ' Your refund is on its way.' : ''}',
                  s == 'PENDING_PAYMENT'
                      ? 'Cancel ${o['orderNumber']}? The reserved stock goes back to the supplier.'
                      : 'Cancel ${o['orderNumber']}? Your ${money(o['totalAmount'])} is refunded the way you paid.',
                ),
          ),
      ];
    }
    return [
      if (s == 'ESCROW_HELD')
        ActionChipBtn(
          'Mark shipped',
          icon: Icons.local_shipping_outlined,
          primary: true,
          busy: b,
          onPressed: () => _run(o, () => jpost('/wholesale/orders/${idOf(o)}/ship'), '${o['orderNumber']} marked as shipped. The vendor was notified.'),
        ),
      if (['PENDING_PAYMENT', 'ESCROW_HELD'].contains(s)) ActionChipBtn(s == 'ESCROW_HELD' ? "Can't fulfil" : 'Decline', danger: true, busy: b, onPressed: () => _reason(o, problem: false)),
    ];
  }

  void _details(Map<String, dynamic> o) {
    final counterpart = widget.supplier ? 'vendor' : 'supplier';
    final party = asMap(o[counterpart]);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder:
          (ctx) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strOf(o['orderNumber']), style: ctx.mvH1.copyWith(fontSize: 18)),
                Tiny('${widget.supplier ? 'Vendor' : 'Supplier'}: ${partyName(party)}${strOf(party['phone']).isNotEmpty ? ' · ${party['phone']}' : ''} · placed ${formatDate(o['createdAt'])}'),
                const SizedBox(height: 8),
                Row(children: [wholesaleChip(o['status'])]),
                Tiny(widget.supplier ? (_status[o['status']]?.$4 ?? '') : (_status[o['status']]?.$3 ?? '')),
                if (strOf(o['cancelReason']).isNotEmpty) Tiny('Reason: ${o['cancelReason']}'),
                if (strOf(o['disputeReason']).isNotEmpty) Tiny('Problem reported: ${o['disputeReason']}'),
                const SizedBox(height: 8),
                for (final i in asMaps(o['items'])) KV('${i['productName']} · ${i['quantity']} ${i['unit'] ?? ''} × ${money(i['unitPrice'])}', money(numOf(i['quantity']) * numOf(i['unitPrice']))),
                const Divider(),
                KV('Total', money(o['totalAmount']), bold: true),
                Tiny(
                  [
                    for (final (l, k) in const [('Paid', 'paidAt'), ('Shipped', 'shippedAt'), ('Completed', 'confirmedAt')])
                      if (o[k] != null) '$l ${formatDate(o[k])}',
                  ].join(' · '),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: _actions(o)),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    final counterpart = supplier ? 'vendor' : 'supplier';
    final newPurchase =
        supplier
            ? null
            : Row(
              children: [
                Expanded(child: OutlineBtn(label: 'Ask for quotes', compact: true, onPressed: () => context.go('/vendor/quotes'))),
                const SizedBox(width: 10),
                Expanded(child: GradientButton(label: 'Buy from a catalog', icon: Icons.add_rounded, compact: true, onPressed: () => context.go('/vendor/suppliers'))),
              ],
            );
    return PortalPage(
      eyebrow: supplier ? 'Supplier · orders' : 'Vendor · purchases',
      title: supplier ? 'Orders from vendors' : 'Purchases',
      subtitle:
          supplier
              ? 'Ship paid orders within 7 days. You are paid when the vendor confirms receipt (or automatically 7 days after shipping).'
              : 'Stock you buy from suppliers. MVEC holds your payment until you confirm the goods arrived.',
      onRefresh: _data.reload,
      action: newPurchase,
      children: [
        LoadView(
          loader: _data,
          builder: (rows) {
            num sum(Iterable<Map<String, dynamic>> l) => l.fold<num>(0, (n, o) => n + numOf(o['totalAmount']));
            final held = rows.where((o) => ['ESCROW_HELD', 'SHIPPED', 'DELIVERED', 'DISPUTED'].contains(o['status'])).toList();
            final toAct = rows.where((o) => supplier ? o['status'] == 'ESCROW_HELD' : ['SHIPPED', 'DELIVERED', 'PENDING_PAYMENT'].contains(o['status'])).length;
            final shown =
                rows
                    .where((o) => _tab == 'ACTIVE' ? _active.contains(o['status']) : !_active.contains(o['status']))
                    .where((o) => matches(_q, [o['orderNumber'], partyName(o[counterpart]), ...asMaps(o['items']).map((i) => i['productName'])]))
                    .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rows.isNotEmpty) ...[
                  MetricGrid(
                    children: [
                      MetricCard(icon: 'bell', label: supplier ? 'To ship' : 'Needs you', value: '$toAct', sub: supplier ? 'Paid and waiting' : 'To pay or confirm'),
                      MetricCard(icon: 'wallet', label: 'Held by MVEC', value: money(sum(held)), sub: '${held.length} order${held.length == 1 ? '' : 's'}'),
                      MetricCard(
                        icon: 'chart',
                        label: supplier ? 'Completed sales' : 'Completed purchases',
                        value: money(sum(rows.where((o) => o['status'] == 'CONFIRMED_RELEASED'))),
                        sub: "Before MVEC's commission",
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                TabChips(tabs: const [('ACTIVE', 'In progress'), ('DONE', 'Completed & cancelled')], value: _tab, onChanged: (v) => setState(() => _tab = v)),
                SearchBox(hint: 'Search by order, name or product…', onChanged: (v) => setState(() => _q = v)),
                Paged<Map<String, dynamic>>(
                  items: shown,
                  empty: EmptyState(
                    icon: Icons.inventory_outlined,
                    title: _tab == 'ACTIVE' ? 'Nothing in progress' : 'Nothing here yet',
                    message: supplier ? 'Orders from vendors and accepted quotes appear here.' : "Buy from a supplier's catalog, or ask several suppliers for quotes.",
                  ),
                  itemBuilder: (o) {
                    final items = asMaps(o['items']);
                    return RecordCard(
                      title: strOf(o['orderNumber']),
                      subtitle: '${partyName(o[counterpart])} · ${formatDate(o['createdAt'])}${o['quote'] != null ? ' · from a quote' : ''}',
                      lines: ['${items.isEmpty ? '—' : items.first['productName']}${items.length > 1 ? ' +${items.length - 1} more' : ''} · ${_units(o)} units'],
                      amount: money(o['totalAmount']),
                      status: wholesaleChip(o['status']),
                      onTap: () => _details(o),
                      actions: _actions(o),
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
            Tiny('${o['orderNumber']} · ${partyName(o['supplier'])}. MVEC holds the money and pays the supplier only after you confirm the goods arrived.'),
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

const units = ['piece', 'pack', 'box', 'carton', 'dozen', 'set', 'pair', 'bag', 'sack', 'kg', 'g', 'litre', 'ml', 'metre', 'roll', 'bottle', 'crate', 'tray'];
const _reqStatus = {
  'OPEN': ('Waiting for quotes', StatusTone.warn),
  'AWARDED': ('Quote accepted', StatusTone.good),
  'CANCELLED': ('Cancelled', StatusTone.bad),
  'EXPIRED': ('Expired', StatusTone.bad),
};

/// `/vendor/quotes` — ask suppliers for goods and accept a quote.
class VendorQuotesPage extends StatefulWidget {
  const VendorQuotesPage({super.key});

  @override
  State<VendorQuotesPage> createState() => _VendorQuotesPageState();
}

class _VendorQuotesPageState extends State<VendorQuotesPage> {
  late final _data = Loader(() => jlist('/quotes/requests/mine', 'requests'));
  String _busy = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _data.reload());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _data.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final res = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _QuoteRequestForm()));
    if (res != null && mounted) {
      toast(context, res);
      _data.reload();
    }
  }

  Future<void> _accept(Map<String, dynamic> q) async {
    if (!await confirmDialog(context, "Accept ${q['supplierName']}'s quote for ${money(q['totalAmount'])}? The other quotes are declined, and you then pay into escrow.", confirm: 'Accept')) return;
    if (!mounted) return;
    setState(() => _busy = '${q['id']}');
    try {
      final res = await jpost('/quotes/${q['id']}/accept');
      if (mounted) context.go('/vendor/purchases?notice=${Uri.encodeQueryComponent(strOf(res['message'], 'Quote accepted.'))}');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _busy = '');
      }
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    if (!await confirmDialog(context, 'Cancel ${r['reference']}? Suppliers who quoted are told.', confirm: 'Cancel request', danger: true)) return;
    if (!mounted) return;
    setState(() => _busy = '${r['id']}');
    final ok = await runAction(context, () => jpost('/quotes/requests/${r['id']}/cancel'));
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Vendor · quote requests',
      title: 'Quote requests',
      subtitle: "Need stock that isn't in a supplier's catalog, or want the best price? Describe it once; verified suppliers send quotes; you accept one and pay into escrow.",
      onRefresh: _data.reload,
      action: GradientButton(label: 'New request', icon: Icons.add_rounded, compact: true, onPressed: _new),
      children: [
        LoadView(
          loader: _data,
          builder: (requests) {
            if (requests.isEmpty) {
              return const EmptyState(icon: Icons.request_quote_outlined, title: 'No quote requests yet', message: 'Suppliers in the category you choose are notified straight away.');
            }
            return Column(
              children: [
                for (final r in requests)
                  Section(
                    title: '${r['reference']} · ${r['category']}',
                    subtitle: '${asMaps(r['lines']).map((l) => '${l['units']} ${l['unit']} ${l['product']}').join(', ')} · needed by ${formatDate(r['neededBy'])}',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(_reqStatus[r['status']]?.$1 ?? titleCase(r['status']), tone: _reqStatus[r['status']]?.$2 ?? StatusTone.warn),
                          if (r['status'] == 'OPEN') ActionChipBtn('Cancel request', danger: true, busy: _busy == '${r['id']}', onPressed: () => _cancel(r)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (asMaps(r['quotes']).isEmpty) Tiny(r['status'] == 'OPEN' ? 'No quotes yet. You will get a notification when one arrives.' : 'No quotes were received.'),
                      for (final (i, q) in asMaps(r['quotes']).indexed)
                        RecordCard(
                          title: '${q['supplierName']}${i == 0 && asMaps(r['quotes']).length > 1 && q['status'] == 'SUBMITTED' ? ' · lowest price' : ''}',
                          lines: [
                            for (final l in asMaps(q['lines'])) '${l['units']} ${l['unit']} ${l['product']} × ${money(l['unitPrice'])}',
                            'Delivery in ${q['deliveryDays']} day${numOf(q['deliveryDays']) == 1 ? '' : 's'}${q['validUntil'] != null ? ' · valid until ${formatDate(q['validUntil'])}' : ''}${strOf(q['note']).isNotEmpty ? ' · “${q['note']}”' : ''}',
                          ],
                          amount: money(q['totalAmount']),
                          status: StatusChip(
                            const {'SUBMITTED': 'Offered', 'ACCEPTED': 'Accepted', 'DECLINED': 'Declined'}[q['status']] ?? '${q['status']}',
                            tone:
                                q['status'] == 'ACCEPTED'
                                    ? StatusTone.good
                                    : q['status'] == 'DECLINED'
                                    ? StatusTone.bad
                                    : StatusTone.warn,
                          ),
                          actions: [
                            if (r['status'] == 'OPEN' && q['status'] == 'SUBMITTED') ActionChipBtn('Accept', primary: true, busy: _busy == '${q['id']}', onPressed: () => _accept(q)),
                            if (q['status'] == 'ACCEPTED') ActionChipBtn('Go to order', onPressed: () => context.go('/vendor/purchases')),
                          ],
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuoteLine {
  final product = TextEditingController();
  final unitsCount = TextEditingController(text: '1');
  final target = TextEditingController();
  String unit = 'piece';
  void dispose() {
    product.dispose();
    unitsCount.dispose();
    target.dispose();
  }
}

class _QuoteRequestForm extends StatefulWidget {
  const _QuoteRequestForm();

  @override
  State<_QuoteRequestForm> createState() => _QuoteRequestFormState();
}

class _QuoteRequestFormState extends State<_QuoteRequestForm> {
  List<Map<String, dynamic>> _categories = [];
  String _category = '';
  DateTime _neededBy = DateTime.now().add(const Duration(days: 7));
  final _deliverTo = TextEditingController();
  final _note = TextEditingController();
  final _lines = [_QuoteLine()];
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
  }

  @override
  void dispose() {
    _deliverTo.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = '');
    if (_category.isEmpty) return setState(() => _error = 'Choose a category.');
    if (_lines.any((l) => l.product.text.trim().isEmpty || numOf(l.unitsCount.text) < 1)) return setState(() => _error = 'Each item needs a name and a quantity of at least 1.');
    setState(() => _busy = true);
    try {
      final r = await jpost('/quotes/requests', {
        'category': _category,
        'neededBy': _neededBy.toIso8601String().substring(0, 10),
        'deliverTo': _deliverTo.text.trim(),
        'note': _note.text.trim(),
        'lines': [
          for (final l in _lines) {'product': l.product.text.trim(), 'units': numOf(l.unitsCount.text).toInt(), 'unit': l.unit, 'targetPrice': l.target.text.trim()},
        ],
      });
      if (mounted) Navigator.of(context).pop(strOf(r['message'], 'Request sent to suppliers.'));
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
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Cancel', onPressed: () => Navigator.of(context).pop()), title: const Text('What do you need?')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_error.isNotEmpty) Notice(text: _error),
            FilterSelect(
              label: 'Category *',
              value: _category,
              options: [('', 'Choose a category'), for (final c in _categories) (strOf(c['name']), strOf(c['name']))],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 10),
            OutlineBtn(
              label: 'Needed by ${formatDate(_neededBy)}',
              icon: Icons.event_outlined,
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _neededBy, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _neededBy = d);
              },
            ),
            const SizedBox(height: 12),
            for (final (i, l) in _lines.indexed)
              DataCard(
                child: Column(
                  children: [
                    TextField(controller: l.product, decoration: InputDecoration(labelText: 'Item ${i + 1} *', hintText: 'e.g. Maize flour 25kg')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: l.unitsCount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity *'))),
                        const SizedBox(width: 10),
                        Expanded(child: FilterSelect(label: 'Unit', value: l.unit, options: [for (final u in units) (u, u)], onChanged: (v) => setState(() => l.unit = v))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: l.target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target price per unit (optional)')),
                    if (_lines.length > 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed:
                              () => setState(() {
                                _lines.removeAt(i).dispose();
                              }),
                          child: const Text('Remove'),
                        ),
                      ),
                  ],
                ),
              ),
            OutlineBtn(label: 'Add another item', icon: Icons.add_rounded, onPressed: () => setState(() => _lines.add(_QuoteLine()))),
            const SizedBox(height: 12),
            TextField(controller: _deliverTo, decoration: const InputDecoration(labelText: 'Deliver to', hintText: 'District, sector or address')),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note for suppliers', hintText: 'Brand, quality, packaging…')),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: GradientButton(label: 'Send to suppliers', loading: _busy, onPressed: _submit))),
    );
  }
}

// ─── Supplier: quotes ────────────────────────────────────────────────────────

/// `/supplier/quotes` — open requests from sellers and the supplier's quotes.
class SupplierQuotesPage extends StatefulWidget {
  const SupplierQuotesPage({super.key});

  @override
  State<SupplierQuotesPage> createState() => _SupplierQuotesPageState();
}

class _SupplierQuotesPageState extends State<SupplierQuotesPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([jlist('/quotes/open', 'requests'), jlist('/quotes/mine', 'quotes')]);
    return (open: r[0], mine: r[1]);
  });
  String _tab = 'open';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _data.reload());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _data.dispose();
    super.dispose();
  }

  Future<void> _quote(Map<String, dynamic> r) async {
    final mine = asMap(r['myQuote']);
    final lines = asMaps(r['lines']);
    final res = await showFormSheet<bool>(
      context,
      title: '${mine.isEmpty ? 'Send a quote' : 'Update your quote'} · ${r['reference']}',
      subtitle:
          '${r['vendorName']} · needed by ${formatDate(r['neededBy'])}${strOf(r['deliverTo']).isNotEmpty ? ' · deliver to ${r['deliverTo']}' : ''}${strOf(r['note']).isNotEmpty ? ' · “${r['note']}”' : ''}',
      fields: [
        for (final (i, l) in lines.indexed)
          FieldSpec(
            'p$i',
            '${l['units']} ${l['unit']} ${l['product']}: your price per ${l['unit']}${l['targetPrice'] != null && '${l['targetPrice']}'.isNotEmpty ? " (vendor's target ${money(l['targetPrice'])})" : ''}',
            type: FieldType.number,
            required: true,
          ),
        const FieldSpec('days', 'Delivery takes (days)', type: FieldType.number, required: true),
        const FieldSpec('valid', 'Offer valid for', type: FieldType.select, options: [('3', '3 days'), ('7', '7 days'), ('14', '14 days'), ('30', '30 days')]),
        const FieldSpec(
          'note',
          'Note (optional)',
          hint: 'Brand, delivery terms…',
          help: "If accepted, the vendor pays MVEC, you ship, and you are paid when they confirm receipt (minus MVEC's wholesale commission).",
        ),
      ],
      initial: {
        for (final (i, _) in lines.indexed) 'p$i': '${asMaps(mine['lines']).elementAtOrNull(i)?['unitPrice'] ?? ''}',
        'days': '${mine['deliveryDays'] ?? 2}',
        'valid': '7',
        'note': strOf(mine['note']),
      },
      submitLabel: mine.isEmpty ? 'Send quote' : 'Update quote',
      onSubmit: (v) async {
        await jpost('/quotes/requests/${r['id']}/quotes', {
          'lines': [
            for (final (i, _) in lines.indexed) {'unitPrice': numOf(v['p$i'])},
          ],
          'deliveryDays': numOf(v['days']).toInt(),
          'validDays': numOf(v['valid'], 7).toInt(),
          'note': v['note'] ?? '',
        });
        return true;
      },
    );
    if (res == true && mounted) {
      toast(context, 'Quote sent to ${r['vendorName']}.');
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Supplier · quotes',
      title: 'Quote requests',
      subtitle: 'Vendors describe what they need; send a price. If they accept, it becomes an order they pay into escrow before you ship.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder:
              (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TabChips(
                    tabs: const [('open', 'Open requests'), ('mine', 'My quotes')],
                    value: _tab,
                    counts: {'open': d.open.length, 'mine': d.mine.length},
                    onChanged: (v) => setState(() => _tab = v),
                  ),
                  if (_tab == 'open') ...[
                    if (d.open.isEmpty) const EmptyState(icon: Icons.request_quote_outlined, title: 'No open requests', message: 'You are notified when a vendor asks for goods in your category.'),
                    if (d.open.isNotEmpty) Tiny('${d.open.where((r) => r['matchesMyCategory'] == true).length} in your category.'),
                    for (final r in d.open)
                      RecordCard(
                        title: '${r['category']} · ${r['vendorName']}${r['matchesMyCategory'] == true ? ' · your category' : ''}',
                        lines: [
                          for (final l in asMaps(r['lines']))
                            '${l['units']} ${l['unit']} ${l['product']}${l['targetPrice'] != null && '${l['targetPrice']}'.isNotEmpty ? ' (target ${money(l['targetPrice'])} each)' : ''}',
                          'Needed by ${formatDate(r['neededBy'])}${strOf(r['deliverTo']).isNotEmpty ? ' · ${r['deliverTo']}' : ''} · ${r['quoteCount'] ?? 0} quote${numOf(r['quoteCount']) == 1 ? '' : 's'} so far',
                        ],
                        status: r['myQuote'] != null ? StatusChip('You quoted ${money(asMap(r['myQuote'])['totalAmount'])}', tone: StatusTone.warn) : null,
                        actions: [ActionChipBtn(r['myQuote'] != null ? 'Update quote' : 'Send a quote', primary: r['myQuote'] == null, onPressed: () => _quote(r))],
                      ),
                  ],
                  if (_tab == 'mine') ...[
                    if (d.mine.isEmpty) const EmptyState(icon: Icons.request_quote_outlined, title: 'No quotes yet'),
                    for (final q in d.mine)
                      RecordCard(
                        title: '${asMap(q['request'])['reference'] ?? ''} · ${asMap(q['request'])['category'] ?? ''}',
                        lines: [asMaps(q['lines']).map((l) => '${l['units']} ${l['unit']} ${l['product']} × ${money(l['unitPrice'])}').join(' · '), 'Sent ${formatDate(q['updatedAt'])}'],
                        amount: money(q['totalAmount']),
                        status: StatusChip(
                          const {'SUBMITTED': 'Waiting for the vendor', 'ACCEPTED': 'Accepted', 'DECLINED': 'Not chosen', 'WITHDRAWN': 'Withdrawn'}[q['status']] ?? '${q['status']}',
                          tone:
                              q['status'] == 'ACCEPTED'
                                  ? StatusTone.good
                                  : ['DECLINED', 'WITHDRAWN'].contains(q['status'])
                                  ? StatusTone.bad
                                  : StatusTone.warn,
                        ),
                        actions: [
                          if (q['status'] == 'SUBMITTED')
                            ActionChipBtn(
                              'Withdraw',
                              danger: true,
                              onPressed: () async {
                                if (!await confirmDialog(context, 'Withdraw this quote?', confirm: 'Withdraw', danger: true)) return;
                                if (context.mounted && await runAction(context, () => jpost('/quotes/${q['id']}/withdraw'), success: 'Quote withdrawn.')) _data.reload();
                              },
                            ),
                          if (q['status'] == 'ACCEPTED') ActionChipBtn('See order', onPressed: () => context.go('/supplier/orders')),
                        ],
                      ),
                  ],
                ],
              ),
        ),
      ],
    );
  }
}

// ─── Seller: find suppliers ──────────────────────────────────────────────────

String _locationOf(Map<String, dynamic> s) {
  final l = s['location'];
  if (l == null) return 'Rwanda';
  if (l is String) return l.isEmpty ? 'Rwanda' : l;
  final m = asMap(l);
  final parts = [m['sector'], m['district'] ?? m['city'], m['province']].where((x) => strOf(x).isNotEmpty).join(', ');
  return parts.isEmpty ? 'Rwanda' : parts;
}

num wholesaleUnitPrice(Map<String, dynamic> p) => numOf(p['wholesalePrice']) * (1 - numOf(p['bulkDiscount']) / 100);

/// [fromCatalog]: called from the catalog screen, which sits on top of the
/// dashboard, so it closes first and the chat opens in the dashboard.
Future<void> _messageSupplier(BuildContext context, Map<String, dynamic> s, {bool fromCatalog = false}) async {
  try {
    await jpost('/conversations', {'recipientId': idOf(s['user']), 'subject': 'Wholesale enquiry: ${s['businessName']}'});
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    if (fromCatalog) Navigator.of(context).pop();
    router.go('/vendor/messages');
  } catch (e) {
    if (context.mounted) toast(context, errorText(e), error: true);
  }
}

/// `/vendor/suppliers` — verified suppliers and their wholesale catalogs.
class FindSuppliersPage extends StatefulWidget {
  const FindSuppliersPage({super.key});

  @override
  State<FindSuppliersPage> createState() => _FindSuppliersPageState();
}

class _FindSuppliersPageState extends State<FindSuppliersPage> {
  late final _data = Loader(() => jlist('/suppliers', 'data', {'pageSize': 100}));
  String _q = '';
  String _sort = 'rating';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'B2B marketplace',
      title: 'Find suppliers',
      subtitle: 'Browse verified suppliers, compare wholesale prices and order stock in bulk, protected by escrow.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search by supplier, location or what they sell…', onChanged: (v) => setState(() => _q = v)),
        FilterSelect(label: 'Sort', value: _sort, options: const [('rating', 'Top rated'), ('name', 'Name A–Z')], onChanged: (v) => setState(() => _sort = v)),
        const SizedBox(height: 12),
        LoadView(
          loader: _data,
          builder: (all) {
            final list =
                all.where((s) => matches(_q, [s['businessName'], _locationOf(s), s['description']])).toList()
                  ..sort((a, b) => _sort == 'name' ? strOf(a['businessName']).compareTo(strOf(b['businessName'])) : numOf(b['ratingAvg']).compareTo(numOf(a['ratingAvg'])));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tiny('${list.length} supplier${list.length == 1 ? '' : 's'}'),
                Paged<Map<String, dynamic>>(
                  items: list,
                  perPage: 9,
                  empty: EmptyState(
                    icon: Icons.storefront_outlined,
                    title: _q.isNotEmpty ? 'No suppliers match your search' : 'No verified suppliers yet',
                    message: _q.isNotEmpty ? 'Try a different name or location.' : 'Verified suppliers will appear here as they join MVEC.',
                  ),
                  itemBuilder:
                      (s) => RecordCard(
                        leading: Avatar(name: strOf(s['businessName'], '?'), url: strOf(s['logoUrl']), radius: 22),
                        title: strOf(s['businessName']),
                        badges: const [StatusChip('Verified ✓', tone: StatusTone.good)],
                        subtitle: '${_locationOf(s)} · ${numOf(s['ratingAvg']) > 0 ? '★ ${numOf(s['ratingAvg']).toStringAsFixed(1)}' : 'New'}',
                        lines: [strOf(s['description'], 'Wholesale supplier on MVEC.')],
                        actions: [
                          ActionChipBtn(
                            'View catalog',
                            icon: Icons.inventory_2_outlined,
                            primary: true,
                            onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => SupplierCatalogPage(supplier: s))),
                          ),
                          ActionChipBtn('Message', icon: Icons.chat_bubble_outline_rounded, onPressed: () => _messageSupplier(context, s)),
                        ],
                      ),
                ),
                const InfoBox(
                  title: '✓ B2B trust',
                  text: 'Every supplier here is verified by MVEC. Minimum order quantities and stock are checked when you order, and your payment stays in escrow until you confirm the delivery.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A supplier's wholesale catalog and the order being built (`CatalogModal`).
class SupplierCatalogPage extends StatefulWidget {
  const SupplierCatalogPage({super.key, required this.supplier});
  final Map<String, dynamic> supplier;

  @override
  State<SupplierCatalogPage> createState() => _SupplierCatalogPageState();
}

class _SupplierCatalogPageState extends State<SupplierCatalogPage> {
  late final _data = Loader(() => jlist('/suppliers/${idOf(widget.supplier)}/products', 'products'));
  final _qty = <String, int>{};
  String _q = '';
  bool _placing = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  String _lineError(Map<String, dynamic> p, int q) {
    final moq = numOf(p['moq'], 1);
    if (q < moq) return 'Minimum order is $moq ${p['unit']}${moq == 1 ? '' : 's'}.';
    if (q > numOf(p['stockQuantity'])) return 'Only ${p['stockQuantity']} in stock.';
    return '';
  }

  Future<void> _place(List<(Map<String, dynamic>, int)> lines) async {
    setState(() => _placing = true);
    try {
      await jpost('/wholesale/orders', {
        'supplierId': idOf(widget.supplier),
        'items': [
          for (final (p, q) in lines) {'productId': idOf(p), 'productName': p['name'], 'quantity': q},
        ],
      });
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go('/vendor/purchases?notice=${Uri.encodeQueryComponent('Order placed and stock reserved. Pay now (within 48 hours) to confirm it.')}');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _placing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;
    return Scaffold(
      appBar: AppBar(
        title: Text(strOf(s['businessName'], 'Catalog')),
        actions: [IconButton(tooltip: 'Message supplier', icon: const Icon(Icons.chat_bubble_outline_rounded), onPressed: () => _messageSupplier(context, s, fromCatalog: true))],
      ),
      body: SafeArea(
        child: LoadView(
          loader: _data,
          page: true,
          loadingLabel: 'Loading catalog…',
          builder: (products) {
            final lines = [
              for (final p in products)
                if ((_qty[idOf(p)] ?? 0) > 0) (p, _qty[idOf(p)]!),
            ];
            final total = lines.fold<num>(0, (n, l) => n + wholesaleUnitPrice(l.$1) * l.$2);
            final invalid = lines.any((l) => _lineError(l.$1, l.$2).isNotEmpty);
            final shown = products.where((p) => matches(_q, [p['name'], p['category']])).toList();
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    children: [
                      Row(
                        children: [
                          Avatar(name: strOf(s['businessName'], '?'), url: strOf(s['logoUrl']), radius: 24),
                          const SizedBox(width: 10),
                          Expanded(child: Tiny('${numOf(s['ratingAvg']) > 0 ? '★ ${numOf(s['ratingAvg']).toStringAsFixed(1)}' : 'New'} · ${_locationOf(s)} · Verified ✓')),
                        ],
                      ),
                      if (strOf(s['description']).isNotEmpty) Tiny(strOf(s['description'])),
                      const SizedBox(height: 8),
                      if (products.length > 4) SearchBox(hint: 'Search this catalog…', onChanged: (v) => setState(() => _q = v)),
                      if (products.isEmpty) const EmptyState(icon: Icons.inventory_2_outlined, title: 'No wholesale products yet', message: 'Message this supplier to ask what they can supply.'),
                      for (final p in shown)
                        Builder(
                          builder: (_) {
                            final id = idOf(p);
                            final n = _qty[id] ?? 0;
                            final moq = numOf(p['moq'], 1).toInt();
                            final out = numOf(p['stockQuantity']) < moq;
                            return RecordCard(
                              selected: n > 0,
                              leading: ProductImage(src: strOf(asMap(p['media'])['mainImage']), size: 52, radius: 8),
                              title: strOf(p['name']),
                              subtitle: '${p['category'] ?? ''} · MOQ $moq ${p['unit']}${moq == 1 ? '' : 's'} · ${p['stockQuantity']} in stock',
                              lines: [
                                '${money(wholesaleUnitPrice(p))}/${p['unit']}${numOf(p['bulkDiscount']) > 0 ? ' (was ${money(p['wholesalePrice'])}, -${p['bulkDiscount']}%)' : ''}',
                                if (n > 0 && _lineError(p, n).isNotEmpty) _lineError(p, n),
                              ],
                              status: out ? const StatusChip('Out of stock', tone: StatusTone.bad) : null,
                              actions:
                                  out
                                      ? const []
                                      : n > 0
                                      ? [QtyStepper(value: n, min: 0, max: numOf(p['stockQuantity']).toInt(), onChanged: (v) => setState(() => _qty[id] = v < moq ? 0 : v))]
                                      : [ActionChipBtn('Add $moq', icon: Icons.add_rounded, onPressed: () => setState(() => _qty[id] = moq))],
                            );
                          },
                        ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: context.mv.surface, border: Border(top: BorderSide(color: context.mv.border))),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (lines.isEmpty)
                        const Tiny("Add products to build a wholesale order. Quantities start at each product's minimum order.")
                      else
                        KV('${lines.length} product${lines.length == 1 ? '' : 's'}', money(total), bold: true),
                      const SizedBox(height: 6),
                      GradientButton(label: 'Place wholesale order', loading: _placing, onPressed: lines.isEmpty || invalid ? null : () => _place(lines)),
                      const Tiny('Your payment is held in escrow and only released to the supplier after you confirm delivery.'),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
