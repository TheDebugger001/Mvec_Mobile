import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

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
          help: "If accepted, the vendor pays Ikiguzi, you ship, and you are paid when they confirm receipt (minus Ikiguzi's wholesale commission).",
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
