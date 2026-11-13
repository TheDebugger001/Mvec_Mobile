import 'dart:async';
import 'package:flutter/material.dart';
import 'wholesale_shared.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

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
