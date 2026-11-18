import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/returns_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import '../common/page_frame.dart';

/// Returns after delivery, as on the website (`components/returns/*`):
/// the buyer asks from the order, the seller answers, Ikiguzi decides when
/// they disagree. Refunds go back to the number or card that paid.

String _items(Map<String, dynamic> r) => [
      for (final i in asMaps(r['items'])) '${numOf(i['quantity']).toInt()} × ${strOf(i['name'])}${strOf(i['variantLabel']).isEmpty ? '' : ' (${i['variantLabel']})'}',
    ].join(', ');

/// On a delivered order: "Start a return" for what can still be sent back.
class ReturnRequestSection extends StatefulWidget {
  const ReturnRequestSection({super.key, required this.orderId});
  final String orderId;

  @override
  State<ReturnRequestSection> createState() => _ReturnRequestSectionState();
}

class _ReturnRequestSectionState extends State<ReturnRequestSection> {
  Map<String, dynamic>? _info;
  String? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await ReturnsApi.eligibility(widget.orderId);
      if (mounted) setState(() => _info = info);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final items = asMaps(info['items']).where((i) => numOf(i['returnable']) > 0).toList();
    if (items.isEmpty && _done == null) return const SizedBox.shrink();
    final deadline = items.map((i) => parseDate(i['deadline'])).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return Section(
      title: 'Return items',
      children: [
        if (_done != null) Notice(ok: true, text: _done!, child: GestureDetector(onTap: () => context.push('/account/returns'), child: const Padding(padding: EdgeInsets.only(top: 4), child: Text('See my returns', style: TextStyle(fontWeight: FontWeight.w700))))),
        if (items.isNotEmpty) ...[
          Text("You can send items back until ${formatDate(deadline)}. Once the seller has them, you're refunded to the number or card you paid with. The delivery fee isn't refunded.", style: TextStyle(color: context.mv.textMuted, fontSize: 12.5)),
          const SizedBox(height: 8),
          OutlineBtn(label: 'Start a return', icon: Icons.assignment_return_outlined, onPressed: () => _start(items, asMaps(info['reasons']))),
        ],
      ],
    );
  }

  Future<void> _start(List<Map<String, dynamic>> items, List<Map<String, dynamic>> reasons) async {
    final sent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ReturnSheet(orderId: widget.orderId, items: items, reasons: reasons),
    );
    if (sent != null && mounted) {
      setState(() => _done = sent);
      _load();
    }
  }
}

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({required this.orderId, required this.items, required this.reasons});
  final String orderId;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> reasons;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _qty = <String, int>{};
  String _reason = '';
  final _text = TextEditingController();
  final _photos = <String>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _needsPhoto => widget.reasons.any((r) => r['code'] == _reason && r['needsPhoto'] == true);

  Future<void> _addPhotos() async {
    setState(() => _busy = true);
    try {
      final urls = await pickAndUploadImages(path: '/uploads/photos', field: 'photos');
      setState(() => _photos.addAll(urls.take(5 - _photos.length)));
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final items = [for (final e in _qty.entries) if (e.value > 0) {'orderItemId': e.key, 'quantity': e.value}];
    if (items.isEmpty) return setState(() => _error = 'Choose at least one item to return.');
    if (_reason.isEmpty) return setState(() => _error = 'Choose why you are returning it.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await ReturnsApi.create(orderId: widget.orderId, items: items, reason: _reason, description: _text.text.trim(), photos: _photos);
      if (mounted) Navigator.pop(context, 'Return ${rows.map((r) => r['returnNumber']).join(', ')} sent. The seller answers within a few days; you\'ll get a message.');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Return items', style: context.mvH1.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final i in widget.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                ProductImage(src: strOf(i['image']), size: 44, radius: 8),
                const SizedBox(width: 10),
                Expanded(child: Text('${strOf(i['name'])}${strOf(i['variantLabel']).isEmpty ? '' : ' (${i['variantLabel']})'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w600))),
                DropdownButton<int>(
                  value: _qty[strOf(i['orderItemId'])] ?? 0,
                  items: [for (var n = 0; n <= numOf(i['returnable']).toInt(); n++) DropdownMenuItem(value: n, child: Text(n == 0 ? 'Keep' : 'Return $n'))],
                  onChanged: (v) => setState(() => _qty[strOf(i['orderItemId'])] = v ?? 0),
                ),
              ]),
            ),
          DropdownButtonFormField<String>(
            initialValue: _reason.isEmpty ? null : _reason,
            decoration: const InputDecoration(labelText: 'Why are you returning it?'),
            items: [for (final r in widget.reasons) DropdownMenuItem(value: strOf(r['code']), child: Text(strOf(r['label'])))],
            onChanged: (v) => setState(() => _reason = v ?? ''),
          ),
          const SizedBox(height: 10),
          TextField(controller: _text, maxLines: 3, maxLength: 2000, decoration: const InputDecoration(labelText: 'Tell the seller more', hintText: "What's wrong with it?")),
          Text(_needsPhoto ? 'Photos (needed: show the problem)' : 'Photos (optional)', style: TextStyle(color: mv.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final u in _photos)
              Stack(children: [
                ProductImage(src: u, size: 60, radius: 8),
                Positioned(right: 0, top: 0, child: GestureDetector(onTap: () => setState(() => _photos.remove(u)), child: const CircleAvatar(radius: 10, child: Icon(Icons.close, size: 12)))),
              ]),
            if (_photos.length < 5) OutlineBtn(label: 'Add photo', icon: Icons.add_a_photo_outlined, compact: true, onPressed: _busy ? null : _addPhotos),
          ]),
          if (_error != null) ...[const SizedBox(height: 10), Notice(text: _error!)],
          const SizedBox(height: 14),
          GradientButton(label: _busy ? 'Sending…' : 'Send return request', expand: true, loading: _busy, onPressed: _busy ? null : _send),
        ],
      ),
    );
  }
}

/// `/account/returns`: the buyer's returns and what they can do next.
class MyReturnsPage extends StatefulWidget {
  const MyReturnsPage({super.key});

  @override
  State<MyReturnsPage> createState() => _MyReturnsPageState();
}

class _MyReturnsPageState extends State<MyReturnsPage> {
  late final Loader<List<Map<String, dynamic>>> _rows = Loader(ReturnsApi.mine);

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'My returns',
      storefront: true,
      body: RefreshIndicator(
        onRefresh: _rows.reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text("Start a return from a delivered order. You're refunded once the seller has the items back.", style: TextStyle(color: context.mv.textMuted, fontSize: 12.5)),
            const SizedBox(height: 12),
            LoadView<List<Map<String, dynamic>>>(
              loader: _rows,
              builder: (rows) => rows.isEmpty
                  ? EmptyState(title: 'No returns', message: 'To return something, open the order in My orders.', action: OutlineBtn(label: 'My orders', compact: true, onPressed: () => context.go('/orders')))
                  : Column(children: [for (final r in rows) _buyerCard(context, r)]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buyerCard(BuildContext context, Map<String, dynamic> r) {
    final id = strOf(r['id'] ?? r['_id']);
    final status = strOf(r['status']);
    return RecordCard(
      title: '${r['returnNumber']} · ${r['statusLabel']}',
      subtitle: '${r['reasonLabel']} · ${formatDate(r['createdAt'])} · refund ${money(r['refundAmount'])}',
      lines: [
        _items(r),
        if (status == 'APPROVED') 'How to send it back: ${r['sellerNote']}',
        if (status == 'REJECTED') '${strOf(r['adminNote']).isEmpty ? 'The seller said' : 'Ikiguzi decided'}: ${strOf(r['adminNote']).isEmpty ? r['sellerNote'] : r['adminNote']}',
        if (status == 'REFUNDED') '${money(r['refundAmount'])} refunded ${formatDate(r['refundedAt'])}.',
      ],
      onTap: () => context.push('/orders/${r['order']}'),
      actions: [
        if (['REQUESTED', 'APPROVED'].contains(status))
          OutlineBtn(label: 'Cancel return', compact: true, onPressed: () async {
            if (!await confirmDialog(context, 'Cancel this return and keep the items?')) return;
            if (context.mounted && await runAction(context, () => ReturnsApi.cancel(id), success: 'Return cancelled.')) _rows.reload();
          }),
        if (['REQUESTED', 'APPROVED', 'REJECTED'].contains(status) && strOf(r['adminNote']).isEmpty)
          OutlineBtn(label: 'Ask Ikiguzi to decide', compact: true, onPressed: () async {
            final why = await promptDialog(context, 'Tell Ikiguzi why you disagree or what is taking too long');
            if (why == null || !context.mounted) return;
            if (await runAction(context, () => ReturnsApi.escalate(id, why), success: 'Ikiguzi will review it and decide.')) _rows.reload();
          }),
      ],
    );
  }
}

/// `/vendor/returns`, `/supplier/returns` and `/admin/returns`.
class ReturnsBoardPage extends StatefulWidget {
  const ReturnsBoardPage({super.key, this.admin = false});
  final bool admin;

  @override
  State<ReturnsBoardPage> createState() => _ReturnsBoardPageState();
}

class _ReturnsBoardPageState extends State<ReturnsBoardPage> {
  static const _tabs = [('', 'All'), ('REQUESTED', 'To answer'), ('APPROVED', 'Waiting for items'), ('ESCALATED', 'With Ikiguzi'), ('REFUNDED', 'Refunded'), ('REJECTED', 'Declined')];
  late String _tab = widget.admin ? 'ESCALATED' : 'REQUESTED';
  late Loader<List<Map<String, dynamic>>> _rows = _loader();

  Loader<List<Map<String, dynamic>>> _loader() => Loader(() => widget.admin ? ReturnsApi.forAdmin(_tab) : ReturnsApi.forSeller(_tab));

  @override
  void dispose() {
    _rows.dispose();
    super.dispose();
  }

  void _switch(String tab) {
    setState(() {
      _tab = tab;
      _rows.dispose();
      _rows = _loader();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: widget.admin ? 'Ikiguzi OPERATIONS' : 'ORDERS',
      title: 'Returns',
      subtitle: widget.admin
          ? "Returns the seller declined or didn't answer in time. Refunding takes the seller's share back from their balance."
          : 'Answer each request within a few days, or Ikiguzi decides. When the items are back, confirm it and the buyer is refunded from your balance.',
      onRefresh: _rows.reload,
      children: [
        FilterRow(children: [FilterSelect(label: 'Show', value: _tab, options: _tabs, onChanged: _switch)]),
        LoadView<List<Map<String, dynamic>>>(
          loader: _rows,
          builder: (rows) => rows.isEmpty
              ? const EmptyState(title: 'Nothing here', message: 'No returns in this list.')
              : Column(children: [for (final r in rows) _card(context, r)]),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> r) {
    final id = strOf(r['id'] ?? r['_id']);
    final status = strOf(r['status']);
    final refund = money(r['refundAmount']);
    Future<void> act(Future<void> Function() fn, String ok) async {
      if (await runAction(context, fn, success: ok)) _rows.reload();
    }

    return RecordCard(
      title: '${r['returnNumber']} · ${r['statusLabel']}',
      subtitle: [if (strOf(r['orderNumber']).isNotEmpty) 'Order ${r['orderNumber']}', formatDate(r['createdAt']), 'refund $refund'].join(' · '),
      lines: [
        _items(r),
        '${r['reasonLabel']}: ${r['description']}',
        if (strOf(r['sellerNote']).isNotEmpty) 'Seller: ${r['sellerNote']}',
        if (status == 'REQUESTED' && !widget.admin) 'Answer by ${formatDate(r['respondBy'])}, or Ikiguzi decides.',
      ],
      badges: [for (final u in (r['photos'] as List? ?? const [])) ProductImage(src: '$u', size: 48, radius: 6)],
      actions: [
        if (!widget.admin && status == 'REQUESTED') ...[
          GradientButton(label: 'Approve', compact: true, onPressed: () async {
            final how = await promptDialog(context, 'How should the buyer send it back?', hint: 'e.g. Bring it to our shop in Remera, Mon–Sat 9–18', confirm: 'Approve', required: false);
            if (how != null && context.mounted) await act(() => ReturnsApi.approve(id, how), 'Approved. The buyer has your instructions.');
          }),
          OutlineBtn(label: 'Decline', compact: true, onPressed: () async {
            final why = await promptDialog(context, 'Why are you declining? The buyer sees this and can ask Ikiguzi.', confirm: 'Decline');
            if (why != null && context.mounted) await act(() => ReturnsApi.reject(id, why), 'Declined. The buyer was told why.');
          }),
        ],
        if (!widget.admin && status == 'APPROVED')
          GradientButton(label: 'Items received: refund', compact: true, onPressed: () async {
            if (!await confirmDialog(context, 'Confirm the items are back? The buyer is refunded $refund from your balance.', confirm: 'Refund')) return;
            if (!context.mounted) return;
            final restock = await confirmDialog(context, 'Put them back in stock? Choose "No" if they are damaged.', title: 'Back in stock?', confirm: 'Yes, restock');
            if (context.mounted) await act(() => ReturnsApi.received(id, restock: restock), 'Refunded. The buyer has been told.');
          }),
        if (!widget.admin && ['REQUESTED', 'APPROVED'].contains(status))
          OutlineBtn(label: 'Refund, keep the items', compact: true, onPressed: () async {
            if (!await confirmDialog(context, 'Refund $refund and let the buyer keep the items?', confirm: 'Refund')) return;
            if (context.mounted) await act(() => ReturnsApi.refundNow(id), 'Refunded. The buyer keeps the items.');
          }),
        if (widget.admin && ['ESCALATED', 'REQUESTED', 'APPROVED', 'REJECTED'].contains(status)) ...[
          GradientButton(label: 'Refund the buyer', compact: true, onPressed: () async {
            final note = await promptDialog(context, 'Why refund $refund? Both sides see this.', confirm: 'Refund');
            if (note != null && context.mounted) await act(() => ReturnsApi.decide(id, 'REFUND', note), 'Refunded.');
          }),
          OutlineBtn(label: 'No refund', compact: true, onPressed: () async {
            final note = await promptDialog(context, 'Why no refund? Both sides see this.', confirm: 'Close');
            if (note != null && context.mounted) await act(() => ReturnsApi.decide(id, 'REJECT', note), 'Closed without a refund.');
          }),
        ],
      ],
    );
  }
}
