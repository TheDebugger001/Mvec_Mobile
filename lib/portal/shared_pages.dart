import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'api.dart';
import 'kit.dart';

// Pages shared by several roles: a problem-report case (buyer, seller and
// MVEC each see their own actions), the list of cases, and MVEC Support.

const _reason = {
  'ITEM_NOT_RECEIVED': 'Item not received',
  'DAMAGED_GOODS': 'Damaged item',
  'WRONG_ITEM': 'Wrong item',
  'INCOMPLETE_ORDER': 'Items missing',
  'SLA_BREACH': 'Late delivery',
  'OTHER': 'Other problem',
};
const _closed = ['RESOLVED_BUYER_REFUNDED', 'RESOLVED_VENDOR_RELEASED', 'RESOLVED_SPLIT', 'REJECTED', 'WITHDRAWN'];
const _steps = ['Reported', 'Seller responding', 'MVEC reviewing', 'Resolved'];

int _stepOf(Map<String, dynamic> c) {
  if (_closed.contains(c['status'])) return 3;
  if (c['status'] == 'UNDER_REVIEW') return 2;
  if (c['status'] == 'EVIDENCE_SUBMITTED' || c['offerStatus'] == 'PENDING') return 1;
  return 0;
}

String _outcome(Map<String, dynamic> c) {
  final d = asMap(c['arbitrationDecision']);
  switch (c['status']) {
    case 'WITHDRAWN':
      return 'The buyer withdrew the report. The order continued as normal.';
    case 'RESOLVED_BUYER_REFUNDED':
      return 'The buyer was refunded ${money(d['buyerRefundAmount'] ?? asMap(c['order'])['totalAmount'])}.';
    case 'RESOLVED_VENDOR_RELEASED':
      return 'The payment was released to the seller.';
    case 'RESOLVED_SPLIT':
      return 'The buyer was refunded ${money(d['buyerRefundAmount'])} and ${money(d['vendorReleaseAmount'])} was released to the seller.';
  }
  return '';
}

String _next(Map<String, dynamic> c, String you) {
  if (_closed.contains(c['status'])) return _outcome(c);
  final due = parseDate(c['respondBy']);
  final deadline = due == null ? '' : '${due.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][due.month - 1]}';
  if (c['status'] == 'UNDER_REVIEW') {
    return you == 'admin'
        ? 'Both sides are waiting for your decision. Read the conversation, ask for anything missing, then decide below.'
        : "MVEC is reviewing both sides and will decide. You can still add information below. You'll be told the outcome.";
  }
  if (c['offerStatus'] == 'PENDING') {
    return you == 'buyer'
        ? 'The seller offers to refund ${money(c['offerAmount'])}. Accept it to close the case, or decline and MVEC will decide.'
        : you == 'seller'
        ? 'Waiting for the buyer to answer your ${money(c['offerAmount'])} offer.'
        : 'The seller offered ${money(c['offerAmount'])}; waiting for the buyer.';
  }
  if (you == 'seller') {
    return "The payment for this order is on hold. Refund the buyer, offer a partial refund, or reply with your side${deadline.isNotEmpty ? ' before $deadline' : ''}. If you don't respond in time, MVEC will decide.";
  }
  if (you == 'buyer') {
    return "The seller has been told and has ${deadline.isNotEmpty ? 'until $deadline' : 'a few days'} to respond. The payment stays on hold meanwhile. If you can't agree, ask MVEC to decide.";
  }
  return "Waiting for the seller to respond${deadline.isNotEmpty ? ' (by $deadline)' : ''}. If they don't, the case comes to you automatically.";
}

/// One problem report as the person looking at it sees it (`DisputeCase`).
class DisputeCaseView extends StatefulWidget {
  const DisputeCaseView({super.key, required this.caseId, this.onChanged});
  final String caseId;
  final VoidCallback? onChanged;

  @override
  State<DisputeCaseView> createState() => _DisputeCaseViewState();
}

class _DisputeCaseViewState extends State<DisputeCaseView> {
  late final _data = Loader(() => jget('/disputes/${widget.caseId}/case'));
  final _reply = TextEditingController();
  String _busy = '';
  String _decision = '';
  final _refund = TextEditingController();
  final _release = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _data.dispose();
    for (final c in [_reply, _refund, _release, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _base => '/disputes/${widget.caseId}';

  Future<void> _act(String key, Future<dynamic> Function() fn, [String? confirm]) async {
    if (confirm != null && !await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = key);
    final ok = await runAction(context, fn);
    if (mounted) setState(() => _busy = '');
    if (ok) {
      await _data.reload();
      widget.onChanged?.call();
    }
  }

  Future<void> _offer(num max) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Offer a partial refund',
      fields: [
        FieldSpec('amount', 'Refund amount (RWF)', type: FieldType.number, required: true, help: 'Up to ${money(max - 1)}.'),
        const FieldSpec('note', 'Message to the buyer (optional)', hint: 'e.g. Sorry for the scratch; keep the item with this refund.'),
      ],
      submitLabel: 'Send offer',
      onSubmit: (v) {
        final amount = numOf(v['amount']);
        if (amount <= 0) throw ApiException('Enter an amount greater than 0.');
        return jpost('$_base/offer', {'amount': amount, 'note': v['note'] ?? ''});
      },
    );
    if (res != null && mounted) {
      toast(context, strOf(res['message'], 'Offer sent.'));
      await _data.reload();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return LoadView(
      loader: _data,
      loadingLabel: 'Loading the case…',
      builder: (d) {
        final c = asMap(d['case']);
        final order = asMap(c['order']);
        final held = asMap(c['held']);
        final you = strOf(d['you']);
        final can = asMap(d['actions']);
        final step = _stepOf(c);
        final closed = _closed.contains(c['status']);
        final heldGross = numOf(held['gross'], numOf(order['totalAmount']));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('PROBLEM REPORT · ${c['disputeNumber'] ?? ''}', style: context.mvEyebrow.copyWith(fontSize: 10.5, letterSpacing: 1.3)),
            const SizedBox(height: 4),
            Text('${_reason[c['reason']] ?? 'Problem'} · order ${order['orderNumber'] ?? ''}', style: context.mvH1.copyWith(fontSize: 17)),
            Tiny(
              'Buyer ${strOf(c['buyerName'], '—')} · Seller ${strOf(c['sellerName'], '—')} · Order total ${money(order['totalAmount'])}${numOf(held['gross']) > 0 ? ' · ${money(held['gross'])} on hold' : ''}',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Expanded(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor:
                              i < step || (closed && i == 3)
                                  ? MvColors.successText
                                  : i == step
                                  ? MvColors.primaryDark
                                  : mv.soft,
                          child:
                              i < step || (closed && i == 3)
                                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                  : Text('${i + 1}', style: TextStyle(fontSize: 11, color: i == step ? Colors.white : mv.textMuted, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _steps[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, color: i == step ? mv.text : mv.textMuted, fontWeight: i == step ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InfoBox(
              title: closed ? 'Outcome' : 'What happens next',
              text: _next(c, you),
              child: closed && strOf(asMap(c['arbitrationDecision'])['notes']).isNotEmpty ? Tiny(strOf(asMap(c['arbitrationDecision'])['notes'])) : null,
            ),
            if (can['acceptOffer'] == true || can['declineOffer'] == true)
              DataCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Refund offer: ${money(c['offerAmount'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (strOf(c['offerNote']).isNotEmpty) Tiny('“${c['offerNote']}”'),
                    const SizedBox(height: 8),
                    GradientButton(
                      label: 'Accept ${money(c['offerAmount'])}',
                      loading: _busy == 'accept',
                      onPressed:
                          _busy.isNotEmpty
                              ? null
                              : () => _act('accept', () => jpost('$_base/offer/accept'), 'Accept ${money(c['offerAmount'])} and close the case? The rest of the payment goes to the seller.'),
                    ),
                    const SizedBox(height: 8),
                    OutlineBtn(
                      label: 'Decline, let MVEC decide',
                      onPressed: _busy.isNotEmpty ? null : () => _act('decline', () => jpost('$_base/offer/decline'), 'Decline the offer? MVEC will review the case and decide.'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            _Bubble(who: strOf(c['buyerName'], 'Buyer'), when: formatDateTime(c['createdAt']), text: strOf(c['description']), role: 'buyer'),
            for (final m in asMaps(d['timeline']))
              m['role'] == 'system'
                  ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${m['message']} · ${formatDateTime(m['createdAt'])}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: mv.textMuted, fontStyle: FontStyle.italic)),
                  )
                  : _Bubble(
                    who: strOf(m['who']),
                    when: formatDateTime(m['createdAt']),
                    text: strOf(m['message']),
                    role:
                        m['role'] == 'buyer'
                            ? 'buyer'
                            : m['role'] == 'super_admin'
                            ? 'mvec'
                            : 'seller',
                  ),
            if (can['reply'] == true) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _reply,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  hintText:
                      you == 'admin'
                          ? 'Message both sides (e.g. ask the seller for delivery proof)…'
                          : you == 'seller'
                          ? 'Your side: delivery proof, what was sent, how you’d like to resolve it…'
                          : 'Add details, photo links, or reply to the seller…',
                ),
              ),
              OutlineBtn(
                label: 'Send',
                loading: _busy == 'reply',
                onPressed:
                    _busy.isNotEmpty
                        ? null
                        : () {
                          final text = _reply.text.trim();
                          if (text.isEmpty) return;
                          _act('reply', () async {
                            await jpost('$_base/evidence', {'message': text});
                            _reply.clear();
                            return {'message': 'Sent. Everyone on the case has been told.'};
                          });
                        },
              ),
            ],
            if (you == 'seller' && !closed) ...[
              const SizedBox(height: 10),
              if (can['fullRefund'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GradientButton(
                    label: 'Refund in full',
                    loading: _busy == 'refund',
                    onPressed: _busy.isNotEmpty ? null : () => _act('refund', () => jpost('$_base/full-refund'), 'Refund the buyer ${money(heldGross)} in full and close the case?'),
                  ),
                ),
              if (can['offer'] == true)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlineBtn(label: 'Offer a partial refund', onPressed: _busy.isNotEmpty ? null : () => _offer(heldGross))),
              if (can['escalate'] == true)
                OutlineBtn(label: 'Ask MVEC to decide', onPressed: _busy.isNotEmpty ? null : () => _act('escalate', () => jpost('$_base/escalate'), 'Ask MVEC to decide this case?')),
            ],
            if (you == 'buyer' && !closed) ...[
              const SizedBox(height: 10),
              if (can['escalate'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlineBtn(
                    label: 'Ask MVEC to decide',
                    onPressed: _busy.isNotEmpty ? null : () => _act('escalate', () => jpost('$_base/escalate'), 'Ask MVEC to decide? MVEC will review both sides.'),
                  ),
                ),
              if (can['withdraw'] == true)
                OutlineBtn(
                  label: 'Problem solved: withdraw report',
                  onPressed:
                      _busy.isNotEmpty
                          ? null
                          : () => _act('withdraw', () => jpost('$_base/withdraw'), 'Withdraw the report? Use this only if the problem is solved: the seller will be paid as normal.'),
                ),
            ],
            if (can['decide'] == true)
              Section(
                title: 'MVEC decision',
                children: [
                  RadioGroup<String>(
                    groupValue: _decision,
                    onChanged: (v) => setState(() => _decision = v ?? ''),
                    child: Column(
                      children: [
                        for (final (k, l, desc) in [
                          ('REFUND_BUYER', 'Refund the buyer in full', '${money(heldGross)} goes back to the buyer.'),
                          ('RELEASE_TO_VENDOR', 'Pay the seller', 'The seller is paid as if delivered.'),
                          ('SPLIT_SETTLEMENT', 'Split', 'Refund part to the buyer, release part to the seller; MVEC keeps any rest.'),
                        ])
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            value: k,
                            title: Text(l, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  if (_decision == 'SPLIT_SETTLEMENT') ...[
                    TextField(controller: _refund, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Refund to buyer (RWF)'), onChanged: (_) => setState(() {})),
                    const SizedBox(height: 10),
                    TextField(controller: _release, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Release to seller (RWF)'), onChanged: (_) => setState(() {})),
                    Tiny("On hold: ${money(held['gross'])}. The seller's usual share of the whole order is ${money(held['net'])}."),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Reason (both sides see this)',
                      hintText: 'e.g. The photos show the screen arrived cracked; the seller did not provide packing proof.',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  GradientButton(
                    label: 'Decide and move the money',
                    loading: _busy == 'decide',
                    onPressed:
                        _busy.isNotEmpty || _decision.isEmpty || _notes.text.trim().isEmpty || (_decision == 'SPLIT_SETTLEMENT' && numOf(_refund.text) + numOf(_release.text) <= 0)
                            ? null
                            : () {
                              final label =
                                  _decision == 'REFUND_BUYER'
                                      ? 'refund the buyer ${money(heldGross)}'
                                      : _decision == 'RELEASE_TO_VENDOR'
                                      ? 'pay the seller'
                                      : 'refund ${money(_refund.text)} and release ${money(_release.text)} to the seller';
                              _act(
                                'decide',
                                () => jpost('$_base/decide', {
                                  'decision': _decision,
                                  'notes': _notes.text.trim(),
                                  if (_decision == 'SPLIT_SETTLEMENT') ...{'buyerRefundAmount': numOf(_refund.text), 'vendorReleaseAmount': numOf(_release.text)},
                                }),
                                'Decide to $label? The money moves straight away and both sides are told.',
                              );
                            },
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.who, required this.when, required this.text, required this.role});
  final String who, when, text, role;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final mine = role == 'seller';
    final bg =
        role == 'mvec'
            ? (context.isDarkMode ? MvColors.darkSoft : MvColors.infoBoxBg)
            : role == 'buyer'
            ? mv.surface
            : mv.soft;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: role == 'mvec' ? MvColors.skyBlue : mv.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$who · $when', style: TextStyle(fontSize: 11, color: mv.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(text, style: TextStyle(fontSize: 13.5, color: mv.text, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

/// Opens a case full-screen.
Future<void> openDisputeCase(BuildContext context, String id, {VoidCallback? onChanged}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder:
          (_) => Scaffold(
            appBar: AppBar(title: const Text('Problem report')),
            body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [DisputeCaseView(caseId: id, onChanged: onChanged)])),
          ),
    ),
  );
}

const disputeReasonLabel = {
  'ITEM_NOT_RECEIVED': 'Item not received',
  'DAMAGED_GOODS': 'Damaged goods',
  'WRONG_ITEM': 'Wrong item',
  'INCOMPLETE_ORDER': 'Incomplete order',
  'SLA_BREACH': 'Late delivery',
  'OTHER': 'Other',
};
const _disputeStatus = {
  'OPEN': ('Waiting for seller', StatusTone.warn),
  'EVIDENCE_SUBMITTED': ('Seller responded', StatusTone.warn),
  'UNDER_REVIEW': ('MVEC deciding', StatusTone.warn),
  'RESOLVED_BUYER_REFUNDED': ('Buyer refunded', StatusTone.bad),
  'RESOLVED_VENDOR_RELEASED': ('Seller paid', StatusTone.good),
  'RESOLVED_SPLIT': ('Split', StatusTone.good),
  'REJECTED': ('Rejected', StatusTone.bad),
  'WITHDRAWN': ('Withdrawn by buyer', StatusTone.good),
};
bool disputeIsOpen(dynamic s) => const ['OPEN', 'UNDER_REVIEW', 'EVIDENCE_SUBMITTED'].contains(s);

StatusChip disputeChip(dynamic status) {
  final s = _disputeStatus['$status'];
  return StatusChip(s?.$1 ?? titleCase(status), tone: s?.$2 ?? StatusTone.warn);
}

/// `/vendor/refunds` and `/admin/disputes` — problem reports (`DisputesList`).
class DisputesListPage extends StatefulWidget {
  const DisputesListPage({super.key, required this.role, this.openCase});
  final String role;
  final String? openCase;

  @override
  State<DisputesListPage> createState() => _DisputesListPageState();
}

class _DisputesListPageState extends State<DisputesListPage> {
  bool get _admin => widget.role == 'admin';
  late final _data = Loader(() => _admin ? jlist('/disputes', 'data', {'pageSize': 100}) : jlist('/disputes/mine', 'data'));
  String _q = '';
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _data.addListener(_maybeOpen);
  }

  void _maybeOpen() {
    final id = widget.openCase;
    if (_opened || id == null || id.isEmpty || _data.data == null) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openDisputeCase(context, id, onChanged: _data.reload);
    });
  }

  @override
  void dispose() {
    _data.removeListener(_maybeOpen);
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: '${widget.role} · refunds',
      title: 'Refunds & disputes',
      subtitle: _admin ? 'Review reported problems, evidence and their resolution.' : 'Problems buyers reported with your orders. Respond with your side so MVEC can resolve them fairly.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (rows) {
            final active = rows.where((r) => disputeIsOpen(r['status'])).toList();
            final shown = rows.where((r) => matches(_q, [r['disputeNumber'], asMap(r['order'])['orderNumber'], asMap(r['raisedBy'])['Fullname'], r['reason']])).toList();
            if (rows.isEmpty) {
              return EmptyState(
                icon: Icons.verified_outlined,
                title: 'No refund requests',
                message: _admin ? 'Disputes raised by buyers will appear here.' : 'Good news: no buyer has reported a problem with your orders.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(icon: 'bell', label: 'Open cases', value: '${active.length}', sub: '${rows.length} in total'),
                    MetricCard(icon: 'edit', label: _admin ? 'Awaiting evidence' : 'Need your response', value: '${active.where((r) => r['status'] == 'OPEN').length}', sub: 'Not yet answered'),
                    MetricCard(icon: 'shield', label: 'Amount at stake', value: money(active.fold<num>(0, (s, r) => s + numOf(r['disputedAmount']))), sub: 'Held until resolved'),
                    MetricCard(icon: 'check', label: 'Resolved', value: '${rows.length - active.length}', sub: 'Closed by MVEC'),
                  ],
                ),
                const SizedBox(height: 14),
                SearchBox(hint: 'Search cases…', onChanged: (v) => setState(() => _q = v)),
                Paged<Map<String, dynamic>>(
                  items: shown,
                  empty: const Tiny('No cases match your search.'),
                  itemBuilder:
                      (r) => RecordCard(
                        title: strOf(r['disputeNumber']),
                        subtitle: 'Order ${strOf(asMap(r['order'])['orderNumber'], '—')} · ${formatDate(r['createdAt'])}',
                        lines: ['${disputeReasonLabel[r['reason']] ?? r['reason']} · raised by ${strOf(asMap(r['raisedBy'])['Fullname'] ?? asMap(r['raisedBy'])['email'], 'Buyer')}'],
                        amount: money(r['disputedAmount']),
                        status: disputeChip(r['status']),
                        onTap: () => openDisputeCase(context, idOf(r), onChanged: _data.reload),
                        actions: [
                          if (disputeIsOpen(r['status']))
                            ActionChipBtn(
                              _admin ? (r['status'] == 'UNDER_REVIEW' ? 'Decide' : 'Open case') : 'Respond',
                              primary: true,
                              onPressed: () => openDisputeCase(context, idOf(r), onChanged: _data.reload),
                            ),
                        ],
                      ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── MVEC Support ────────────────────────────────────────────────────────────

const supportCategories = [
  ('ORDER', 'Order or delivery'),
  ('PAYMENT', 'Payment or payout'),
  ('ACCOUNT', 'My account'),
  ('VENDOR_ONBOARDING', 'Store setup'),
  ('TECHNICAL', 'Technical problem'),
  ('OTHER', 'Something else'),
];
const _caseStatus = {'OPEN': ('Open', StatusTone.warn), 'IN_PROGRESS': ('In progress', StatusTone.warn), 'RESOLVED': ('Resolved', StatusTone.good), 'CLOSED': ('Closed', StatusTone.good)};
StatusChip supportChip(dynamic s) {
  final x = _caseStatus['$s'];
  return StatusChip(x?.$1 ?? titleCase(s), tone: x?.$2 ?? StatusTone.warn);
}

/// `/<role>/support` — send MVEC a request and follow the replies.
class SupportPage extends StatefulWidget {
  const SupportPage({super.key, required this.role});
  final String role;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  late final _cases = Loader(() => jlist('/support/cases', 'cases', {'pageSize': 50}));
  final _subject = TextEditingController();
  final _reference = TextEditingController();
  final _message = TextEditingController();
  String _category = 'ORDER';
  String _priority = 'MEDIUM';
  bool _sending = false;

  @override
  void dispose() {
    _cases.dispose();
    for (final c in [_subject, _reference, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      toast(context, 'Add a subject and a message.', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final description = _reference.text.trim().isNotEmpty ? 'Reference: ${_reference.text.trim()}\n\n${_message.text.trim()}' : _message.text.trim();
      final res = await jpost('/support/cases', {'subject': _subject.text.trim(), 'category': _category, 'priority': _priority, 'description': description});
      if (!mounted) return;
      toast(context, 'Ticket ${asMap(res['case'])['ticketNumber'] ?? ''} created. MVEC support will reply here.');
      _subject.clear();
      _reference.clear();
      _message.clear();
      _cases.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _open(Map<String, dynamic> c) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => _TicketPage(id: idOf(c), onChanged: _cases.reload)));
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: '${widget.role} · support',
      title: 'MVEC Support',
      subtitle: 'Contact the MVEC team about payments, deliveries, orders or your account, and follow every request here.',
      onRefresh: _cases.reload,
      children: [
        Section(
          title: 'New request',
          children: [
            TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject *', hintText: 'e.g. Payout not received')),
            const SizedBox(height: 10),
            FilterSelect(label: 'Topic', value: _category, options: supportCategories, onChanged: (v) => setState(() => _category = v)),
            if (widget.role == 'buyer' && _category == 'ORDER')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () => context.go('/orders'),
                  child: const Tiny(
                    "Problem with a specific order? Open it in My orders and choose Report a problem. The seller and MVEC both receive it, and the payment stays on hold until it's resolved.",
                  ),
                ),
              ),
            const SizedBox(height: 10),
            FilterSelect(
              label: 'Urgency',
              value: _priority,
              options: const [('LOW', 'Low'), ('MEDIUM', 'Normal'), ('HIGH', 'High'), ('URGENT', 'Urgent: money or orders blocked')],
              onChanged: (v) => setState(() => _priority = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Order or transaction ID', hintText: 'Optional')),
            const SizedBox(height: 10),
            TextField(controller: _message, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'Message *', hintText: "Describe the issue and what you've already tried…")),
            const SizedBox(height: 12),
            GradientButton(label: 'Send to MVEC', loading: _sending, onPressed: _send),
          ],
        ),
        LoadView(
          loader: _cases,
          builder:
              (cases) => Section(
                title: 'Your requests',
                subtitle: '${cases.where((c) => c['status'] == 'OPEN' || c['status'] == 'IN_PROGRESS').length} open',
                children: [
                  if (cases.isEmpty) const EmptyState(icon: Icons.support_agent_outlined, title: 'No requests yet', message: "Requests you send will appear here with MVEC's replies."),
                  for (final c in cases)
                    RecordCard(
                      title: strOf(c['subject']),
                      subtitle: '${c['ticketNumber'] ?? ''} · ${formatDate(c['createdAt'])}',
                      lines: [
                        '${supportCategories.where((x) => x.$1 == c['category']).map((x) => x.$2).firstOrNull ?? c['category']} · ${(c['comments'] is List ? (c['comments'] as List).length : 0)} replies',
                      ],
                      status: supportChip(c['status']),
                      onTap: () => _open(c),
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

class _TicketPage extends StatefulWidget {
  const _TicketPage({required this.id, this.onChanged, this.staff = false});
  final String id;
  final VoidCallback? onChanged;
  final bool staff;

  @override
  State<_TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<_TicketPage> {
  late final _data = Loader(() async => asMap((await jget('/support/cases/${widget.id}'))['case']));
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _data.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final ok = await runAction(context, () => jpost('/support/cases/${widget.id}/comments', {'message': _reply.text.trim()}));
    if (mounted) setState(() => _sending = false);
    if (ok) {
      _reply.clear();
      _data.reload();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support ticket')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            LoadView(
              loader: _data,
              builder: (c) {
                final open = !['RESOLVED', 'CLOSED'].contains(c['status']);
                final author = asMap(c['createdBy'] ?? c['user']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(strOf(c['subject']), style: context.mvH1.copyWith(fontSize: 18)),
                    const SizedBox(height: 6),
                    Row(children: [supportChip(c['status']), const SizedBox(width: 8), Expanded(child: Tiny('${c['ticketNumber'] ?? ''} · opened ${formatDate(c['createdAt'])}'))]),
                    const SizedBox(height: 8),
                    _Bubble(who: widget.staff ? personName(author, 'Customer') : 'You', when: formatDate(c['createdAt']), text: strOf(c['description']), role: widget.staff ? 'buyer' : 'seller'),
                    for (final m in asMaps(c['comments']))
                      Builder(
                        builder: (_) {
                          final a = m['author'];
                          final staff = a is Map && a['role'] != null && !['vendor', 'supplier', 'buyer', 'affiliate', 'delivery'].contains(a['role']);
                          final who = staff ? (widget.staff ? 'MVEC (${personName(a, 'support')})' : 'MVEC support') : (widget.staff ? personName(a, 'Customer') : 'You');
                          return _Bubble(who: who, when: formatDate(m['createdAt']), text: strOf(m['message']), role: staff ? 'mvec' : (widget.staff ? 'buyer' : 'seller'));
                        },
                      ),
                    if (open) ...[
                      const SizedBox(height: 10),
                      TextField(controller: _reply, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Reply', hintText: 'Add more details…')),
                      const SizedBox(height: 8),
                      GradientButton(label: 'Send reply', loading: _sending, onPressed: _send),
                    ],
                    if (widget.staff) ...[
                      const SizedBox(height: 12),
                      FilterSelect(
                        label: 'Status',
                        value: strOf(c['status'], 'OPEN'),
                        options: const [('OPEN', 'Open'), ('IN_PROGRESS', 'In progress'), ('RESOLVED', 'Resolved'), ('CLOSED', 'Closed')],
                        onChanged: (v) async {
                          if (await runAction(context, () => jpatch('/support/cases/${widget.id}/status', {'status': v}), success: 'Status updated.')) {
                            _data.reload();
                            widget.onChanged?.call();
                          }
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin side of support tickets (`/admin/support`).
Future<void> openTicketAsStaff(BuildContext context, String id, {VoidCallback? onChanged}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => _TicketPage(id: id, onChanged: onChanged, staff: true)));
