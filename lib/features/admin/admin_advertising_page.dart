import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

const _adTabs = [('PENDING', 'To review'), ('ACTIVE', 'Live'), ('PAUSED', 'Paused'), ('COMPLETED', 'Ended'), ('REJECTED', 'Rejected'), ('ALL', 'All')];

/// `/admin/advertising` — review seller ad campaigns.
class AdminAdvertisingPage extends StatefulWidget {
  const AdminAdvertisingPage({super.key});

  @override
  State<AdminAdvertisingPage> createState() => _AdminAdvertisingPageState();
}

class _AdminAdvertisingPageState extends State<AdminAdvertisingPage> {
  late final _data = Loader(() => jlist('/admin/advertisements', 'data', {'limit': 200}));
  String _tab = 'PENDING';
  String _busy = '';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _act(Map<String, dynamic> ad, String status, [String? confirm]) async {
    String? reason;
    if (status == 'REJECTED') {
      reason = await promptDialog(context, 'Why reject the campaign for ${ad['product']}? The seller sees this and gets ${money(ad['remaining'])} back.', confirm: 'Reject');
      if (reason == null || reason.trim().isEmpty) return;
    } else if (confirm != null && !await confirmDialog(context, confirm)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = '${ad['id']}');
    final ok = await runAction(context, () => jpatch('/admin/advertisements/${ad['id']}/status', {'status': status, if (reason != null) 'reason': reason.trim()}));
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (ads) {
        num sum(Iterable<Map<String, dynamic>> l, String f) => l.fold<num>(0, (t, a) => t + numOf(a[f]));
        int count(String k) => k == 'ALL' ? ads.length : ads.where((a) => a['statusKey'] == k).length;
        final live = ads.where((a) => a['statusKey'] == 'ACTIVE');
        final rows = (_tab == 'ALL' ? ads : ads.where((a) => a['statusKey'] == _tab)).where((a) => matches(_q, [a['product'], a['vendor'], a['id']])).toList();
        return PortalPage(
          eyebrow: 'Admin control',
          title: 'Advertising',
          subtitle: 'Review seller campaigns. Budgets are prepaid from seller balances; each click costs ${money(ads.isEmpty ? 100 : numOf(ads.first['costPerClick'], 100))}.',
          onRefresh: _data.reload,
          children: [
            MetricGrid(
              children: [
                MetricCard(label: 'To review', value: '${count('PENDING')}', icon: 'bell', sub: '${money(sum(ads.where((a) => a['statusKey'] == 'PENDING'), 'budget'))} in budgets'),
                MetricCard(label: 'Live campaigns', value: '${live.length}', icon: 'tag', sub: '${money(sum(live, 'remaining'))} budget left'),
                MetricCard(label: 'Ad revenue', value: money(sum(ads, 'spent')), icon: 'wallet', sub: '${compact(sum(ads, 'clicks'))} paid clicks'),
                MetricCard(label: 'Views', value: compact(sum(ads, 'impressions')), icon: 'eye', sub: 'All campaigns'),
              ],
            ),
            const SizedBox(height: 14),
            TabChips(tabs: _adTabs, value: _tab, counts: {for (final t in _adTabs) t.$1: count(t.$1)}, onChanged: (v) => setState(() => _tab = v)),
            SearchBox(hint: 'Search campaigns or sellers…', onChanged: (v) => setState(() => _q = v)),
            Paged<Map<String, dynamic>>(
              items: rows,
              empty: const EmptyState(icon: Icons.campaign_outlined, title: 'No campaigns here.'),
              itemBuilder: (r) {
                final k = '${r['statusKey']}';
                final busy = _busy == '${r['id']}';
                return RecordCard(
                  title: strOf(r['product']),
                  subtitle: '${r['vendor'] ?? ''} · ${r['placement'] ?? ''} · ${r['startDate']} → ${r['endDate']}',
                  lines: [
                    'Budget ${money(r['budget'])} · ${money(r['spent'])} spent · ${money(r['remaining'])} left',
                    '${compact(r['impressions'])} views · ${compact(r['clicks'])} clicks (${r['ctr'] ?? '0%'})',
                    strOf(r['rejectionReason']),
                  ],
                  status: Pill(k == 'PENDING' ? 'IN_REVIEW' : k),
                  actions: [
                    if (k == 'PENDING') ...[
                      ActionChipBtn('Approve', primary: true, busy: busy, onPressed: () => _act(r, 'ACTIVE', 'Approve and publish the campaign for ${r['product']}?')),
                      ActionChipBtn('Reject', danger: true, busy: busy, onPressed: () => _act(r, 'REJECTED')),
                    ],
                    if (k == 'ACTIVE') ActionChipBtn('Pause', busy: busy, onPressed: () => _act(r, 'PAUSED')),
                    if (k == 'PAUSED') ActionChipBtn('Resume', busy: busy, onPressed: () => _act(r, 'ACTIVE')),
                    if (k == 'ACTIVE' || k == 'PAUSED')
                      ActionChipBtn('End', busy: busy, onPressed: () => _act(r, 'COMPLETED', 'End this campaign? ${money(r['remaining'])} unspent returns to the seller.')),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// ─── Affiliates ─────────────────────────────────────────────────────────────
