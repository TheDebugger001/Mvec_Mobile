import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'pay_wholesale_sheet.dart';
import 'wholesale_shared.dart';

num _units(Map<String, dynamic> o) => asMaps(o['items']).fold<num>(0, (n, i) => n + numOf(i['quantity']));

/// status -> label, tone, what it means for the seller, for the supplier.
const _status = {
  'PENDING_PAYMENT': ('Waiting for payment', StatusTone.warn, 'Pay within 48 hours or the order expires and the stock is released.', 'The vendor has not paid yet. Do not ship.'),
  'ESCROW_HELD': (
    'Paid · Ikiguzi holds the money',
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
  'CONFIRMED_RELEASED': ('Completed', StatusTone.good, 'Received. The supplier was paid.', "Completed. The money (minus Ikiguzi's commission) is in your balance."),
  'DISPUTED': ('Problem reported', StatusTone.bad, 'Ikiguzi is reviewing the problem; the money stays on hold.', 'The vendor reported a problem. Ikiguzi will decide; the money stays on hold.'),
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

  /// Confirm the goods arrived, then ask whether to put them in stock now
  /// (existing products restocked, new ones listed from the supplier's details).
  Future<void> _confirmReceipt(Map<String, dynamic> o) async {
    final number = o['orderNumber'];
    if (!await confirmDialog(context, 'Confirm you received everything in $number? ${money(o['totalAmount'])} is released to ${partyName(o['supplier'])}. This cannot be undone.')) return;
    if (!mounted) return;
    final store = strOf(asMap(o['store'])['storeName'], 'your store');
    final add = await confirmDialog(
      context,
      "Add these goods to $store's stock now? Products you bought before are restocked; new ones are listed for you from the supplier's details, so you don't start from scratch.",
      title: 'Add to your stock?',
      confirm: 'Add to my stock',
      cancel: 'Not now',
    );
    if (!mounted) return;
    setState(() => _busy = idOf(o));
    final ok = await runAction(context, () => jpost('/wholesale/orders/${idOf(o)}/confirm-receipt', {'addToStock': add}), success: '$number confirmed. The supplier has been paid.${add ? '' : ' Use "Add to my stock" when you want the goods in your store.'}');
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  Future<void> _reason(Map<String, dynamic> o, {required bool problem}) async {
    final ok = await showFormSheet<bool>(
      context,
      title: problem ? 'Report a problem with ${o['orderNumber']}' : 'Cancel ${o['orderNumber']}',
      subtitle:
          problem
              ? 'Ikiguzi holds the payment while it reviews. Describe what you received and what you expected.'
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
      toast(context, problem ? 'Problem reported. Ikiguzi will review it; the payment stays on hold.' : 'Order cancelled. The vendor was told.');
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
            onPressed: () => _confirmReceipt(o),
          ),
        if (s == 'CONFIRMED_RELEASED' && o['stockedAt'] == null)
          ActionChipBtn(
            'Add to my stock',
            icon: Icons.inventory_2_outlined,
            primary: true,
            busy: b,
            onPressed: () => _run(o, () => jpost('/wholesale/orders/${idOf(o)}/add-to-stock'), 'Added to your stock.'),
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
              : 'Stock you buy from suppliers. Ikiguzi holds your payment until you confirm the goods arrived.',
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
                      MetricCard(icon: 'wallet', label: 'Held by Ikiguzi', value: money(sum(held)), sub: '${held.length} order${held.length == 1 ? '' : 's'}'),
                      MetricCard(
                        icon: 'chart',
                        label: supplier ? 'Completed sales' : 'Completed purchases',
                        value: money(sum(rows.where((o) => o['status'] == 'CONFIRMED_RELEASED'))),
                        sub: "Before Ikiguzi's commission",
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

