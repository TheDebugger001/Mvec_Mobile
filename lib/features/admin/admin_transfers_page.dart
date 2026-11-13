import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _payMethod = {'MTN_MOMO': 'MTN MoMo', 'AIRTEL_MONEY': 'Airtel Money', 'BANK_TRANSFER': 'Bank transfer'};

const _transferStatus = {'QUEUED': ('Queued', StatusTone.warn), 'SENT': ('Waiting for provider', StatusTone.warn), 'SUCCESS': ('Sent', StatusTone.good), 'FAILED': ('Failed', StatusTone.bad)};

/// `/admin/transfers` — affiliate withdrawals to approve and every transfer.
class AdminTransfersPage extends StatefulWidget {
  const AdminTransfersPage({super.key});

  @override
  State<AdminTransfersPage> createState() => _AdminTransfersPageState();
}

class _AdminTransfersPageState extends State<AdminTransfersPage> {
  String _filter = 'FAILED';
  late Loader<({List<Map<String, dynamic>> payouts, List<Map<String, dynamic>> transfers})> _data = _load();
  String _busy = '';

  Loader<({List<Map<String, dynamic>> payouts, List<Map<String, dynamic>> transfers})> _load() => Loader(() async {
    final r = await Future.wait([
      jlist('/affiliates/admin/payouts', 'data'),
      jlist('/admin/disbursements', 'data', {if (_filter.isNotEmpty) 'status': _filter}),
    ]);
    return (payouts: r[0].where((x) => ['PENDING', 'APPROVED', 'PROCESSING'].contains(x['status'])).toList(), transfers: r[1]);
  });

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _process(Map<String, dynamic> p, String status) async {
    String? ref;
    if (status == 'REJECTED' && !await confirmDialog(context, "Reject this withdrawal? The amount returns to the affiliate's balance.", confirm: 'Reject', danger: true)) return;
    if (!mounted) return;
    if (status == 'COMPLETED') {
      ref = await promptDialog(context, 'Bank transfer reference', confirm: 'Mark paid');
      if (ref == null || ref.trim().isEmpty) return;
    }
    if (!mounted) return;
    setState(() => _busy = idOf(p));
    final ok = await runAction(
      context,
      () => jpost('/affiliates/payouts/${idOf(p)}/process', {'status': status, if (ref != null) 'transactionReference': ref.trim(), if (status == 'REJECTED') 'rejectionReason': 'Rejected by Ikiguzi'}),
      success:
          status == 'REJECTED'
              ? 'Withdrawal rejected.'
              : status == 'APPROVED'
              ? 'Approved and sent to mobile money.'
              : 'Marked as paid.',
    );
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Admin · money out',
      title: 'Refunds & withdrawals',
      subtitle: 'Refunds and small affiliate withdrawals are sent automatically. Approve larger withdrawals here and retry any transfer that failed.',
      onRefresh: _data.reload,
      children: [
        FilterSelect(
          label: 'Show transfers',
          value: _filter,
          options: const [('FAILED', 'Failed'), ('SENT', 'Waiting for provider'), ('SUCCESS', 'Sent'), ('', 'All')],
          onChanged: (v) {
            final old = _data;
            setState(() {
              _filter = v;
              _data = _load();
            });
            old.dispose();
          },
        ),
        const SizedBox(height: 12),
        LoadView(
          loader: _data,
          builder:
              (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Section(
                    title: 'Affiliate withdrawals waiting',
                    subtitle: '${d.payouts.length} request${d.payouts.length == 1 ? '' : 's'}',
                    children: [
                      if (d.payouts.isEmpty) const EmptyState(icon: Icons.task_alt_rounded, title: 'Nothing to approve'),
                      for (final p in d.payouts)
                        RecordCard(
                          title: personName(p['affiliate'], 'Affiliate'),
                          subtitle:
                              '${_payMethod[p['paymentMethod']] ?? p['paymentMethod']} · ${strOf(p['phoneNumber'], [p['bankName'], p['accountNumber']].where((x) => strOf(x).isNotEmpty).join(' '))}',
                          lines: ['Requested ${formatDate(p['createdAt'])} · ${p['payoutNumber'] ?? ''}'],
                          amount: money(p['amount']),
                          status: StatusChip(p['status'] == 'PROCESSING' ? 'Sending' : 'Waiting', tone: StatusTone.warn),
                          actions:
                              p['status'] != 'PENDING'
                                  ? const []
                                  : [
                                    if (p['paymentMethod'] != 'BANK_TRANSFER') ActionChipBtn('Approve & send', primary: true, busy: _busy == idOf(p), onPressed: () => _process(p, 'APPROVED')),
                                    if (p['paymentMethod'] == 'BANK_TRANSFER') ActionChipBtn('Mark paid', primary: true, busy: _busy == idOf(p), onPressed: () => _process(p, 'COMPLETED')),
                                    ActionChipBtn('Reject', danger: true, busy: _busy == idOf(p), onPressed: () => _process(p, 'REJECTED')),
                                  ],
                        ),
                    ],
                  ),
                  Section(
                    title: 'Transfers',
                    subtitle: 'Refunds and withdrawals sent to mobile money',
                    children: [
                      if (d.transfers.isEmpty) const EmptyState(icon: Icons.swap_horiz_rounded, title: 'No transfers here'),
                      for (final t in d.transfers)
                        RecordCard(
                          title: t['kind'] == 'REFUND' ? 'Refund · ${asMap(t['order'])['orderNumber'] ?? ''}' : 'Affiliate withdrawal',
                          subtitle: '${personName(t['recipient'], '')} · +${'${t['phone'] ?? ''}'.replaceFirst('+', '')}',
                          lines: [
                            if (strOf(t['lastError']).isNotEmpty) strOf(t['lastError']),
                            '${numOf(t['attempts']).toInt()} attempt${numOf(t['attempts']) == 1 ? '' : 's'} · ${formatDate(t['updatedAt'])}',
                          ],
                          amount: money(t['amount']),
                          status: StatusChip(_transferStatus[t['status']]?.$1 ?? '${t['status']}', tone: _transferStatus[t['status']]?.$2 ?? StatusTone.neutral),
                          actions: [
                            if (t['status'] == 'FAILED')
                              ActionChipBtn(
                                'Retry now',
                                busy: _busy == idOf(t),
                                onPressed: () async {
                                  setState(() => _busy = idOf(t));
                                  final ok = await runAction(context, () => jpost('/admin/disbursements/${idOf(t)}/retry'));
                                  if (mounted) setState(() => _busy = '');
                                  if (ok) _data.reload();
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

// ─── Seller payouts ─────────────────────────────────────────────────────────
