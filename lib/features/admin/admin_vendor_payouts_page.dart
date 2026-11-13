import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _payoutTabs = [('PENDING', 'To review'), ('PROCESSING', 'Processing'), ('PAID', 'Paid'), ('REJECTED', 'Rejected'), ('CANCELLED', 'Cancelled'), ('', 'All')];

/// `/admin/vendor-payouts` — approve, mark paid or reject seller withdrawals.
class AdminVendorPayoutsPage extends StatefulWidget {
  const AdminVendorPayoutsPage({super.key});

  @override
  State<AdminVendorPayoutsPage> createState() => _AdminVendorPayoutsPageState();
}

class _AdminVendorPayoutsPageState extends State<AdminVendorPayoutsPage> {
  String _status = 'PENDING';
  int _page = 1;
  String _busy = '';
  late Loader<Map<String, dynamic>> _data = _load();

  Loader<Map<String, dynamic>> _load() => Loader(() => jget('/admin/vendor-payouts', {'status': _status.isEmpty ? null : _status, 'page': _page, 'limit': 20}));

  void _reload([VoidCallback? change]) {
    final old = _data;
    setState(() {
      change?.call();
      _data = _load();
    });
    old.dispose();
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _act(Map<String, dynamic> p, Future<dynamic> Function() fn, String done) async {
    setState(() => _busy = idOf(p));
    final ok = await runAction(context, fn, success: done);
    if (mounted) setState(() => _busy = '');
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Admin control',
      title: 'Seller payouts',
      subtitle: 'Approve, send the money by mobile money, then mark it paid with the transfer reference.',
      onRefresh: () async => _reload(),
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final totals = asMap(d['totals']);
            final auto = d['autoDisburse'] == true;
            final rows = asMaps(d['data']);
            final pages = numOf(asMap(d['meta'])['pages'], 1).toInt();
            String vendorName(Map<String, dynamic> p) =>
                strOf(asMap(p['vendor'])['companyName'] ?? asMap(p['vendor'])['Fullname'] ?? asMap(p['vendor'])['fullName'] ?? asMap(p['vendor'])['email'], 'Seller');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (auto) const Notice(info: true, text: 'Approving sends the money automatically through mobile money.'),
                MetricGrid(
                  children: [
                    for (final (k, label, icon) in const [('PENDING', 'To review', 'bell'), ('PROCESSING', 'Processing', 'wallet'), ('PAID', 'Paid', 'chart'), ('REJECTED', 'Rejected', 'shield')])
                      MetricCard(label: label, value: money(asMap(totals[k])['amount']), icon: icon, sub: '${numOf(asMap(totals[k])['count']).toInt()} requests'),
                  ],
                ),
                const SizedBox(height: 14),
                TabChips(
                  tabs: [for (final t in _payoutTabs) (t.$1, t.$2)],
                  value: _status,
                  counts: {
                    for (final t in _payoutTabs)
                      if (t.$1.isNotEmpty && numOf(asMap(totals[t.$1])['count']) > 0) t.$1: numOf(asMap(totals[t.$1])['count']).toInt(),
                  },
                  onChanged:
                      (v) => _reload(() {
                        _status = v;
                        _page = 1;
                      }),
                ),
                if (rows.isEmpty) const Tiny('Nothing here.'),
                for (final p in rows)
                  Builder(
                    builder: (_) {
                      final det = asMap(p['payoutDetails']);
                      final busy = _busy == idOf(p);
                      Future<void> reject() async {
                        final reason = await promptDialog(context, 'Why reject ${p['payoutNumber']}? The seller sees this and the amount returns to their balance.', confirm: 'Reject');
                        if (reason == null || reason.trim().isEmpty || !mounted) return;
                        await _act(p, () => jpost('/admin/vendor-payouts/${idOf(p)}/reject', {'reason': reason.trim()}), 'Payout rejected.');
                      }

                      return RecordCard(
                        title: '${p['payoutNumber'] ?? ''} · ${vendorName(p)}',
                        subtitle: '${formatDate(p['createdAt'])} · balance left ${money(p['sellerAvailableBalance'])}',
                        lines: [
                          '${det['accountName'] ?? ''} · ${[det['bankName'], det['accountNumber']].where((x) => strOf(x).isNotEmpty).join(' · ')}',
                          if (strOf(p['transferReference']).isNotEmpty) 'Ref ${p['transferReference']}',
                          if (strOf(p['rejectionReason']).isNotEmpty) strOf(p['rejectionReason']),
                        ],
                        amount: money(p['amount']),
                        status: Pill(p['status']),
                        actions: [
                          if (p['status'] == 'PENDING') ...[
                            ActionChipBtn(
                              'Approve',
                              primary: true,
                              busy: busy,
                              onPressed: () async {
                                final ok = await confirmDialog(
                                  context,
                                  auto
                                      ? 'Send ${money(p['amount'])} to ${det['accountNumber']} now?'
                                      : 'Approve ${p['payoutNumber']}? Send ${money(p['amount'])} to ${det['accountNumber']}, then mark it paid with the transfer reference.',
                                  confirm: 'Approve',
                                );
                                if (ok && mounted) await _act(p, () => jpost('/admin/vendor-payouts/${idOf(p)}/approve'), 'Payout approved.');
                              },
                            ),
                            ActionChipBtn('Reject', danger: true, busy: busy, onPressed: reject),
                          ],
                          if (p['status'] == 'PROCESSING') ...[
                            ActionChipBtn(
                              'Mark paid',
                              busy: busy,
                              onPressed: () async {
                                final ref = await promptDialog(context, 'Transfer reference for ${money(p['amount'])} sent to ${det['accountNumber']}:', confirm: 'Mark paid');
                                if (ref == null || ref.trim().isEmpty || !mounted) return;
                                await _act(p, () => jpost('/admin/vendor-payouts/${idOf(p)}/mark-paid', {'transferReference': ref.trim()}), 'Payout marked as paid.');
                              },
                            ),
                            ActionChipBtn('Reject', danger: true, busy: busy, onPressed: reject),
                          ],
                        ],
                      );
                    },
                  ),
                if (pages > 1) PaginationBar(page: _page, total: pages * 20, perPage: 20, onPage: (n) => _reload(() => _page = n)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Advertising review ─────────────────────────────────────────────────────
