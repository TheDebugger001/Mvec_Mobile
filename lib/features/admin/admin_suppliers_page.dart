import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import '../wholesale/wholesale_shared.dart';
import 'verification_list.dart';

const _wholesaleLabel = {
  'PENDING_PAYMENT': 'Waiting for payment',
  'ESCROW_HELD': 'Paid · to ship',
  'SHIPPED': 'Shipped',
  'DELIVERED': 'Delivered',
  'CONFIRMED_RELEASED': 'Completed',
  'DISPUTED': 'Problem reported',
  'CANCELLED': 'Cancelled',
};

/// `/admin/suppliers` — tabs for supplier work (`AdminSuppliers`).
class AdminSuppliersPage extends StatefulWidget {
  const AdminSuppliersPage({super.key, this.tab});
  final String? tab;

  @override
  State<AdminSuppliersPage> createState() => _AdminSuppliersPageState();
}

class _AdminSuppliersPageState extends State<AdminSuppliersPage> {
  late String _tab = widget.tab ?? 'accounts';
  late final _attention = Loader(() async => {for (final i in asMaps((await jget('/admin/attention'))['items'])) '${i['key']}': numOf(i['count']).toInt()});

  @override
  void dispose() {
    _attention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'People & stores',
      title: 'Suppliers',
      subtitle: 'Verify suppliers, follow wholesale orders and quote requests, decide wholesale problems and send bank payouts.',
      children: [
        ListenableBuilder(
          listenable: _attention,
          builder: (context, _) {
            final c = _attention.data ?? const <String, int>{};
            return TabChips(
              tabs: const [('accounts', 'Verification'), ('wholesale', 'Wholesale orders'), ('quotes', 'Quote requests'), ('payouts', 'Bank payouts')],
              value: _tab,
              counts: {
                if (c['suppliers'] != null) 'accounts': c['suppliers']!,
                if (c['wholesaleDisputes'] != null) 'wholesale': c['wholesaleDisputes']!,
                if (c['supplierPayouts'] != null) 'payouts': c['supplierPayouts']!,
              },
              onChanged: (v) => setState(() => _tab = v),
            );
          },
        ),
        switch (_tab) {
          'wholesale' => _WholesaleOversight(onChanged: _attention.reload),
          'quotes' => const _QuoteOversight(),
          'payouts' => _SupplierPayouts(onChanged: _attention.reload),
          _ => const VerificationList(kind: 'supplier'),
        },
      ],
    );
  }
}

class _WholesaleOversight extends StatefulWidget {
  const _WholesaleOversight({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_WholesaleOversight> createState() => _WholesaleOversightState();
}

class _WholesaleOversightState extends State<_WholesaleOversight> {
  String _status = 'DISPUTED';
  late Loader<List<Map<String, dynamic>>> _data = _load();
  final _notes = <String, TextEditingController>{};
  String _busy = '';

  Loader<List<Map<String, dynamic>>> _load() => Loader(() => jlist('/wholesale/admin/orders', 'orders', {if (_status.isNotEmpty) 'status': _status}));

  @override
  void dispose() {
    _data.dispose();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _decide(Map<String, dynamic> o, String decision) async {
    final ok = await confirmDialog(
      context,
      decision == 'RELEASE' ? 'Pay ${partyName(o['supplier'])} ${money(o['totalAmount'])} (minus commission)?' : 'Refund ${partyName(o['vendor'])} ${money(o['totalAmount'])}?',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = idOf(o));
    final done = await runAction(context, () => jpost('/wholesale/admin/orders/${idOf(o)}/resolve', {'decision': decision, 'note': _notes[idOf(o)]?.text ?? ''}));
    if (mounted) setState(() => _busy = '');
    if (done) {
      _data.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Wholesale orders',
      subtitle: 'Vendors buying stock from suppliers. Ikiguzi holds the money until the vendor confirms receipt; problems are decided here.',
      children: [
        FilterSelect(
          label: 'Show',
          value: _status,
          options: const [('DISPUTED', 'Problem reported'), ('ESCROW_HELD', 'Paid, not shipped'), ('SHIPPED', 'Shipped'), ('PENDING_PAYMENT', 'Waiting for payment'), ('', 'All')],
          onChanged: (v) {
            final old = _data;
            setState(() {
              _status = v;
              _data = _load();
            });
            old.dispose();
          },
        ),
        const SizedBox(height: 10),
        LoadView(
          loader: _data,
          builder:
              (rows) => Column(
                children: [
                  if (rows.isEmpty) EmptyState(title: _status == 'DISPUTED' ? 'No reported problems' : 'No orders here'),
                  for (final o in rows)
                    RecordCard(
                      title: '${o['orderNumber']} · ${partyName(o['vendor'])} ← ${partyName(o['supplier'])}',
                      lines: [
                        for (final i in asMaps(o['items'])) '${i['quantity']} ${i['unit'] ?? ''} × ${i['productName']} at ${money(i['unitPrice'])}',
                        if (strOf(o['disputeReason']).isNotEmpty) 'Problem: ${o['disputeReason']}',
                        if (strOf(o['cancelReason']).isNotEmpty) 'Cancelled: ${o['cancelReason']}',
                        'Placed ${formatDate(o['createdAt'])}${o['paidAt'] != null ? ' · paid ${formatDate(o['paidAt'])}' : ''}${o['shippedAt'] != null ? ' · shipped ${formatDate(o['shippedAt'])}' : ''}',
                      ],
                      amount: money(o['totalAmount']),
                      status: StatusChip(
                        _wholesaleLabel[o['status']] ?? titleCase(o['status']),
                        tone:
                            o['status'] == 'CONFIRMED_RELEASED'
                                ? StatusTone.good
                                : ['DISPUTED', 'CANCELLED'].contains(o['status'])
                                ? StatusTone.bad
                                : StatusTone.warn,
                      ),
                      actions:
                          o['status'] != 'DISPUTED'
                              ? const []
                              : [
                                SizedBox(
                                  width: 260,
                                  child: TextField(
                                    controller: _notes.putIfAbsent(idOf(o), TextEditingController.new),
                                    decoration: const InputDecoration(isDense: true, hintText: 'Decision note (both sides see it)'),
                                  ),
                                ),
                                ActionChipBtn('Pay supplier', primary: true, busy: _busy == idOf(o), onPressed: () => _decide(o, 'RELEASE')),
                                ActionChipBtn('Refund vendor', busy: _busy == idOf(o), onPressed: () => _decide(o, 'REFUND')),
                              ],
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

class _QuoteOversight extends StatefulWidget {
  const _QuoteOversight();

  @override
  State<_QuoteOversight> createState() => _QuoteOversightState();
}

class _QuoteOversightState extends State<_QuoteOversight> {
  late final _data = Loader(() => jlist('/quotes/admin/requests', 'requests'));
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Quote requests',
      subtitle: 'Vendors ask for goods; verified suppliers quote; accepted quotes become wholesale orders. Nothing to approve here.',
      children: [
        SearchBox(hint: 'Search requests…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder:
              (rows) => Paged<Map<String, dynamic>>(
                items: rows.where((r) => matches(_q, [r['reference'], r['category'], partyName(r['vendor'])])).toList(),
                empty: const Tiny('No quote requests yet.'),
                itemBuilder:
                    (r) => RecordCard(
                      title: '${r['reference']} · ${r['category'] ?? ''}',
                      subtitle: '${partyName(r['vendor'])} · needed by ${formatDate(r['neededBy'])}',
                      lines: [asMaps(r['lines']).map((l) => '${l['units']} ${l['unit']} ${l['product']}').join(', '), '${numOf(r['quoteCount']).toInt()} quotes'],
                      status: StatusChip(
                        const {'OPEN': 'Open', 'AWARDED': 'Quote accepted', 'CANCELLED': 'Cancelled', 'EXPIRED': 'Expired'}[r['status']] ?? '${r['status']}',
                        tone:
                            r['status'] == 'AWARDED'
                                ? StatusTone.good
                                : r['status'] == 'OPEN'
                                ? StatusTone.warn
                                : StatusTone.bad,
                      ),
                    ),
              ),
        ),
      ],
    );
  }
}

class _SupplierPayouts extends StatefulWidget {
  const _SupplierPayouts({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_SupplierPayouts> createState() => _SupplierPayoutsState();
}

class _SupplierPayoutsState extends State<_SupplierPayouts> {
  late final _data = Loader(() => jlist('/admin/suppliers/payouts', 'payouts'));
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _act(Map<String, dynamic> p, String status) async {
    var reason = '';
    if (status == 'REJECTED') {
      reason = await promptDialog(context, "Why is this payout declined? The amount goes back to the supplier's balance.", confirm: 'Decline') ?? '';
      if (reason.trim().isEmpty) return;
    }
    if (!mounted) return;
    if (status == 'PAID' && !await confirmDialog(context, 'Confirm you sent ${money(p['amount'])} to ${strOf(p['destination'], 'the supplier')}?')) return;
    if (!mounted) return;
    setState(() => _busy = idOf(p));
    final ok = await runAction(
      context,
      () => jpatch('/admin/suppliers/payouts/${idOf(p)}', {'status': status, 'reason': reason}),
      success:
          status == 'PAID'
              ? 'Marked as paid. The supplier was notified.'
              : status == 'PROCESSING'
              ? 'Marked as being sent.'
              : "Declined; the money is back in the supplier's balance.",
    );
    if (mounted) setState(() => _busy = '');
    if (ok) {
      _data.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Supplier bank payouts',
      subtitle: "Mobile money payouts are sent automatically. Bank transfers: send from Ikiguzi's account, then mark paid. The supplier is notified.",
      trailing: IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _data.reload),
      children: [
        LoadView(
          loader: _data,
          builder:
              (rows) => Column(
                children: [
                  if (rows.isEmpty) const EmptyState(icon: Icons.account_balance_outlined, title: 'No payouts waiting'),
                  for (final p in rows)
                    RecordCard(
                      title: strOf(p['supplierName'] ?? p['accountName'], 'Supplier'),
                      subtitle: '${p['bankName'] ?? ''} · ${p['destination'] ?? ''}${strOf(p['accountName']).isNotEmpty ? ' · ${p['accountName']}' : ''}',
                      lines: ['${p['payoutNumber'] ?? ''} · requested ${formatDate(p['requestedAt'])}${strOf(p['note']).isNotEmpty ? ' · “${p['note']}”' : ''}'],
                      amount: money(p['amount']),
                      status: StatusChip(p['status'] == 'PROCESSING' ? 'Being sent' : 'Waiting', tone: StatusTone.warn),
                      actions: [
                        if (p['status'] == 'PENDING') ActionChipBtn('Sending now', busy: _busy == idOf(p), onPressed: () => _act(p, 'PROCESSING')),
                        ActionChipBtn('Mark paid', primary: true, busy: _busy == idOf(p), onPressed: () => _act(p, 'PAID')),
                        ActionChipBtn('Decline', danger: true, busy: _busy == idOf(p), onPressed: () => _act(p, 'REJECTED')),
                      ],
                    ),
                ],
              ),
        ),
      ],
    );
  }
}
