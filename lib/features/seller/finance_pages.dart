import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'products_pages.dart' show productImage;

const _payoutTabs = <(String, String, List<String>?)>[
  ('ALL', 'All', null),
  ('OPEN', 'In progress', ['PENDING', 'PROCESSING']),
  ('PAID', 'Paid', ['PAID']),
  ('CLOSED', 'Rejected / cancelled', ['REJECTED', 'CANCELLED', 'FAILED']),
];
const _payoutStep = {
  'PENDING': 'Waiting for MVEC review',
  'PROCESSING': 'Being sent to your mobile money',
  'PAID': 'Sent',
  'REJECTED': 'Rejected — the amount is back in your balance',
  'CANCELLED': 'Cancelled — the amount is back in your balance',
  'FAILED': 'Failed — the amount is back in your balance',
};

/// `/vendor/payouts` — balance breakdown, withdraw to mobile money, history.
class SellerPayoutsPage extends StatefulWidget {
  const SellerPayoutsPage({super.key});

  @override
  State<SellerPayoutsPage> createState() => _SellerPayoutsPageState();
}

class _SellerPayoutsPageState extends State<SellerPayoutsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([jget('/payouts/balance'), jget('/payouts/history')]);
    return (summary: asMap(r[0]['summary']), commissionRate: strOf(r[0]['commissionRate'], '5%'), payouts: asMaps(r[1]['payouts']));
  });
  final _amount = TextEditingController();
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();
  bool _prefilled = false;
  bool _requesting = false;
  String _busy = '';
  String _tab = 'ALL';

  @override
  void dispose() {
    _data.dispose();
    for (final c in [_amount, _accountName, _accountNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _request(Map<String, dynamic> s) async {
    final min = numOf(s['minimumPayout'], 1000);
    final available = numOf(s['available']);
    final amount = num.tryParse(_amount.text.trim());
    String? problem;
    if (_amount.text.trim().isEmpty || _accountName.text.trim().isEmpty || _accountNumber.text.trim().isEmpty) {
      problem = 'Enter the amount, account name and mobile money number.';
    } else if (amount == null || amount != amount.roundToDouble()) {
      problem = 'Use a whole amount in RWF.';
    } else if (amount < min) {
      problem = 'The minimum payout is ${money(min)}.';
    } else if (amount > available) {
      problem = 'You can withdraw up to ${money(available)}.';
    } else if (mobileProvider(_accountNumber.text).isEmpty) {
      problem = 'Use an MTN (078/079) or Airtel (072/073) number.';
    }
    if (problem != null) {
      toast(context, problem, error: true);
      return;
    }
    setState(() => _requesting = true);
    final ok = await runAction(
      context,
      () => jpost('/payouts/request', {
        'amount': amount!.toInt(),
        'payoutDetails': {'accountName': _accountName.text.trim(), 'accountNumber': _accountNumber.text.trim()},
      }),
    );
    if (mounted) setState(() => _requesting = false);
    if (ok) {
      _amount.clear();
      _data.reload();
    }
  }

  Future<void> _cancel(Map<String, dynamic> p) async {
    if (!await confirmDialog(context, 'Cancel payout ${p['payoutNumber']} of ${money(p['amount'])}? The amount goes back to your available balance.', confirm: 'Cancel payout', danger: true)) return;
    if (!mounted) return;
    setState(() => _busy = idOf(p));
    final ok = await runAction(context, () => jpost('/payouts/${idOf(p)}/cancel'));
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Payouts',
      subtitle: 'Withdraw money released from delivered orders to your mobile money.',
      onRefresh: _data.reload,
      action: OutlineBtn(label: 'View statement', compact: true, onPressed: () => context.go('/vendor/transactions')),
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final s = d.summary;
            final min = numOf(s['minimumPayout'], 1000);
            final available = numOf(s['available']);
            if (!_prefilled) {
              _prefilled = true;
              final last = d.payouts.map((p) => asMap(p['payoutDetails'])).where((x) => strOf(x['accountNumber']).isNotEmpty).firstOrNull;
              if (last != null) {
                _accountName.text = strOf(last['accountName']);
                _accountNumber.text = strOf(last['accountNumber']);
              }
            }
            final st = _payoutTabs.firstWhere((t) => t.$1 == _tab).$3;
            final shown = st == null ? d.payouts : d.payouts.where((p) => st.contains(p['status'])).toList();
            final provider = mobileProvider(_accountNumber.text);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Available', value: money(available), icon: 'wallet', sub: 'Ready to withdraw'),
                    MetricCard(label: 'In escrow', value: money(s['inEscrow']), icon: 'shield', sub: '${numOf(s['escrowOrders']).toInt()} orders · released after delivery'),
                    MetricCard(label: 'Withdrawals in progress', value: money(s['pendingPayouts']), icon: 'bell', sub: 'Requested, not sent yet'),
                    MetricCard(label: 'Paid out', value: money(s['paidOut']), icon: 'chart', sub: 'Sent to your account'),
                  ],
                ),
                const SizedBox(height: 14),
                if (numOf(s['frozen']) > 0)
                  Notice(info: true, text: '${money(s['frozen'])} from ${s['frozenOrders']} order${numOf(s['frozenOrders']) == 1 ? '' : 's'} is on hold because of an open dispute.'),
                Section(
                  title: 'Request payout',
                  children: [
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Amount (RWF)',
                        hintText: 'Minimum ${money(min)}',
                        suffixIcon: TextButton(onPressed: available < min ? null : () => setState(() => _amount.text = '${available.floor()}'), child: const Text('All')),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: _accountName, decoration: const InputDecoration(labelText: 'Account name', hintText: 'Name registered on the mobile money account')),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _accountNumber,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: 'Mobile money number', hintText: '078 / 079 (MTN) or 072 / 073 (Airtel)', helperText: provider.isEmpty ? null : 'Paid to $provider'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    GradientButton(label: 'Request payout', loading: _requesting, onPressed: available < min ? null : () => _request(s)),
                    const Tiny('MVEC reviews requests and sends the money, usually within 1 business day. You can cancel while a request is waiting for review.'),
                  ],
                ),
                Section(
                  title: 'Where your money is',
                  children: [
                    RecordCard(title: 'In escrow', subtitle: 'Paid by buyers, released when they confirm delivery', amount: money(s['inEscrow'])),
                    RecordCard(title: 'On hold', subtitle: 'Orders with an open dispute', amount: money(s['frozen'])),
                    RecordCard(title: 'Available', subtitle: 'Released to you, ready to withdraw', amount: money(available)),
                    if (numOf(s['collectedBySeller']) > 0)
                      RecordCard(title: 'Collected by you', subtitle: 'Manual orders paid in cash or offline — not in your MVEC balance', amount: money(s['collectedBySeller'])),
                    RecordCard(title: 'MVEC commission', subtitle: '${d.commissionRate} of each released sale', amount: money(s['commissionPaid'])),
                  ],
                ),
                Section(
                  title: 'Payout history',
                  children: [
                    TabChips(
                      tabs: [for (final t in _payoutTabs) (t.$1, t.$2)],
                      value: _tab,
                      counts: {for (final t in _payoutTabs) t.$1: t.$3 == null ? d.payouts.length : d.payouts.where((p) => t.$3!.contains(p['status'])).length},
                      onChanged: (v) => setState(() => _tab = v),
                    ),
                    if (shown.isEmpty) const Tiny('No payouts here yet.'),
                    for (final p in shown)
                      RecordCard(
                        title: strOf(p['payoutNumber']),
                        subtitle: [formatDate(p['createdAt']), strOf(asMap(p['payoutDetails'])['bankName']), strOf(asMap(p['payoutDetails'])['accountNumber'])].where((x) => x.isNotEmpty).join(' · '),
                        lines: [
                          '${_payoutStep[p['status']] ?? titleCase(p['status'])}${strOf(p['transferReference']).isNotEmpty ? ' · Ref ${p['transferReference']}' : ''}${strOf(p['rejectionReason']).isNotEmpty ? ' · Reason: ${p['rejectionReason']}' : ''}',
                        ],
                        amount: money(p['amount']),
                        status: Pill(p['status']),
                        actions: [if (p['status'] == 'PENDING') ActionChipBtn('Cancel', danger: true, busy: _busy == idOf(p), onPressed: () => _cancel(p))],
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

const _typeLabel = {'SALE': 'Sale', 'DISPUTE_RELEASE': 'Dispute release', 'PAYOUT': 'Payout', 'SUBSCRIPTION': 'Subscription', 'ADVERTISING': 'Advertising', 'ADJUSTMENT': 'Adjustment'};
const _stateLabel = {
  'IN_ESCROW': 'In escrow',
  'FROZEN': 'On hold',
  'RELEASED': 'Released',
  'ARBITRATED': 'Dispute resolved',
  'COLLECTED_BY_SELLER': 'Collected by you',
  'REFUNDED': 'Refunded',
  'CANCELLED': 'Cancelled',
  'CHARGED': 'Charged',
};
const _periods = [('30', 'Last 30 days'), ('90', 'Last 90 days'), ('365', 'Last 12 months'), ('ALL', 'All time'), ('CUSTOM', 'Custom')];

String _dateParam(DateTime d) => d.toIso8601String().substring(0, 10);

/// `/vendor/transactions` — the statement of sales, commission, payouts and
/// charges with each one's effect on the balance.
class SellerTransactionsPage extends StatefulWidget {
  const SellerTransactionsPage({super.key});

  @override
  State<SellerTransactionsPage> createState() => _SellerTransactionsPageState();
}

class _SellerTransactionsPageState extends State<SellerTransactionsPage> {
  String _period = '90';
  String _from = _dateParam(DateTime.now().subtract(const Duration(days: 30)));
  String _to = _dateParam(DateTime.now());
  String _type = 'ALL';
  String _q = '';
  late Loader<({Map<String, dynamic> statement, Map<String, dynamic> summary})> _data = _load();

  Loader<({Map<String, dynamic> statement, Map<String, dynamic> summary})> _load() {
    final params =
        _period == 'ALL'
            ? <String, dynamic>{}
            : _period == 'CUSTOM'
            ? {'from': _from, 'to': _to}
            : {'from': _dateParam(DateTime.now().subtract(Duration(days: int.parse(_period))))};
    return Loader(() async {
      final r = await Future.wait([jget('/payouts/statement', params), jget('/payouts/balance')]);
      return (statement: r[0], summary: asMap(r[1]['summary']));
    });
  }

  void _reload() {
    final old = _data;
    setState(() => _data = _load());
    old.dispose();
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final cur = DateTime.tryParse(from ? _from : _to) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d == null) return;
    if (from) {
      _from = _dateParam(d);
    } else {
      _to = _dateParam(d);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Transactions',
      subtitle: 'Your statement: every sale, commission, payout and charge, and how it changed your balance.',
      onRefresh: () async => _reload(),
      action: OutlineBtn(label: 'Request payout', compact: true, onPressed: () => context.go('/vendor/payouts')),
      children: [
        FilterRow(
          children: [
            FilterSelect(
              label: 'Period',
              value: _period,
              options: _periods,
              onChanged: (v) {
                _period = v;
                _reload();
              },
            ),
            FilterSelect(
              label: 'Type',
              value: _type,
              options: const [('ALL', 'All types'), ('SALE', 'Sales'), ('PAYOUT', 'Payouts'), ('CHARGE', 'Charges'), ('DISPUTE_RELEASE', 'Dispute releases')],
              onChanged: (v) => setState(() => _type = v),
            ),
          ],
        ),
        if (_period == 'CUSTOM')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: OutlineBtn(label: 'From ${formatDate(_from)}', compact: true, onPressed: () => _pick(true))),
                const SizedBox(width: 10),
                Expanded(child: OutlineBtn(label: 'To ${formatDate(_to)}', compact: true, onPressed: () => _pick(false))),
              ],
            ),
          ),
        LoadView(
          loader: _data,
          builder: (d) {
            final t = asMap(d.statement['totals']);
            final s = d.summary;
            final rows =
                asMaps(d.statement['entries'])
                    .where((e) => _type == 'ALL' || (_type == 'CHARGE' ? ['SUBSCRIPTION', 'ADVERTISING', 'ADJUSTMENT'].contains(e['type']) : e['type'] == _type))
                    .where((e) => matches(_q, [e['reference'], e['detail'], e['type']]))
                    .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Released to you', value: money(t['released']), icon: 'wallet', sub: 'In this period'),
                    MetricCard(label: 'Commission', value: money(t['commission']), icon: 'tag', sub: 'On released sales'),
                    MetricCard(label: 'Paid out', value: money(t['paidOut']), icon: 'chart', sub: 'Charges ${money(t['charges'])}'),
                    MetricCard(label: 'Available now', value: money(s['available']), icon: 'shield', sub: '${money(s['inEscrow'])} still in escrow'),
                  ],
                ),
                const SizedBox(height: 14),
                SearchBox(hint: 'Search reference, order…', onChanged: (v) => setState(() => _q = v)),
                Paged<Map<String, dynamic>>(
                  items: rows,
                  perPage: 12,
                  empty: const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions in this period.'),
                  itemBuilder: (e) {
                    final effect = numOf(e['effect']);
                    final net = numOf(e['net']);
                    return RecordCard(
                      title: _typeLabel[e['type']] ?? titleCase(e['type']),
                      subtitle: '${formatDate(e['date'])} · ${e['reference'] ?? ''}',
                      lines: [
                        strOf(e['detail']),
                        if (e['gross'] != null)
                          'Gross ${money(e['gross'])}${numOf(e['delivery']) > 0 ? ' (incl. ${money(e['delivery'])} delivery)' : ''}${numOf(e['commission']) > 0 ? ' · commission -${money(e['commission'])}' : ''}',
                        'Balance effect: ${effect == 0 ? 'none yet' : '${effect > 0 ? '+' : ''}${money(effect)}'}',
                        if (strOf(e['transferReference']).isNotEmpty) 'Transfer ref ${e['transferReference']}',
                        if (strOf(e['rejectionReason']).isNotEmpty) 'Reason: ${e['rejectionReason']}',
                      ],
                      amount: money(net),
                      status: Pill(e['state'], label: _stateLabel[e['state']] ?? titleCase(e['state'])),
                      onTap: strOf(e['orderId']).isEmpty ? null : () => context.push('/vendor/orders/${e['orderId']}'),
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

// ─── Advertisements ──────────────────────────────────────────────────────────

const _placements = [('HOMEPAGE_HERO', 'Homepage hero'), ('CATEGORY_BANNER', 'Category banner'), ('SEARCH_RESULTS', 'Search results'), ('FEATURED', 'Featured'), ('PROMOTION', 'Promotion')];
const _minAdBudget = 5000;
const _adTabs = <(String, String, List<String>?)>[
  ('ALL', 'All', null),
  ('LIVE', 'Live', ['ACTIVE']),
  ('REVIEW', 'In review', ['PENDING']),
  ('PAUSED', 'Paused', ['PAUSED']),
  ('ENDED', 'Ended', ['COMPLETED', 'REJECTED']),
];

/// `/vendor/advertisements` — pay-per-click sponsored products.
class SellerAdsPage extends StatefulWidget {
  const SellerAdsPage({super.key});

  @override
  State<SellerAdsPage> createState() => _SellerAdsPageState();
}

class _SellerAdsPageState extends State<SellerAdsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([
      jget('/vendor/advertisements'),
      vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
      jget('/payouts/balance').catchError((_) => <String, dynamic>{}),
    ]);
    final balance = r[2] as Map<String, dynamic>;
    return (
      ads: asMaps((r[0] as Map<String, dynamic>)['data']),
      products: r[1] as List<Map<String, dynamic>>,
      available: numOf(asMap(balance['summary'])['available'] ?? asMap(balance['balance'])['availableBalance']),
    );
  });
  String _tab = 'ALL';
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _run(Map<String, dynamic> ad, Future<dynamic> Function() fn, [String? confirm]) async {
    if (confirm != null && !await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = '${ad['id']}');
    final ok = await runAction(context, fn);
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  Future<void> _create(List<Map<String, dynamic>> products, num available, num cpc) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'New ad campaign',
      subtitle: 'Paid from your available balance (${money(available)}). Reviewed by MVEC before it goes live.',
      fields: [
        FieldSpec('productId', 'Product', type: FieldType.select, required: true, placeholderOption: 'Select a product', options: [for (final p in products) (idOf(p), strOf(p['name']))]),
        const FieldSpec('placement', 'Where to show it', type: FieldType.select, options: _placements),
        FieldSpec('budget', 'Budget (RWF)', type: FieldType.number, required: true, help: 'Minimum ${money(_minAdBudget)} · about ${(_minAdBudget / cpc).floor()} clicks per ${money(_minAdBudget)}'),
        const FieldSpec('startDate', 'Start date', type: FieldType.date),
        const FieldSpec('endDate', 'End date (optional)', type: FieldType.date),
      ],
      initial: {'placement': 'SEARCH_RESULTS', 'budget': '$_minAdBudget', 'startDate': _dateParam(DateTime.now())},
      submitLabel: 'Pay & submit for review',
      onSubmit: (v) async {
        final budget = num.tryParse('${v['budget']}');
        if (budget == null || budget != budget.roundToDouble() || budget < _minAdBudget) throw ApiException('The minimum budget is ${money(_minAdBudget)}.');
        if (budget > available) throw ApiException('Your available balance is ${money(available)}. Lower the budget or wait for more sales to be released.');
        return jpost('/vendor/advertisements', {
          'productId': v['productId'],
          'placement': v['placement'],
          'budget': budget.toInt(),
          if ('${v['startDate'] ?? ''}'.isNotEmpty) 'startDate': v['startDate'],
          if ('${v['endDate'] ?? ''}'.isNotEmpty) 'endDate': v['endDate'],
        });
      },
    );
    if (res != null && mounted) {
      toast(context, strOf(res['message'], 'Campaign submitted.'));
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final ads = d.ads;
        final cpc = ads.isEmpty ? 100 : numOf(ads.first['costPerClick'], 100);
        final spent = ads.fold<num>(0, (s, a) => s + numOf(a['spent']));
        final clicks = ads.fold<num>(0, (s, a) => s + numOf(a['clicks']));
        final views = ads.fold<num>(0, (s, a) => s + numOf(a['impressions']));
        final st = _adTabs.firstWhere((t) => t.$1 == _tab).$3;
        final rows = st == null ? ads : ads.where((a) => st.contains(a['statusKey'])).toList();
        final products = d.products.where((p) => p['status'] == 'ACTIVE' && numOf(p['stockQuantity']) > 0).toList();
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Advertisements',
          subtitle: 'Sponsor your products on the homepage, search and category pages. You pay ${money(cpc)} per buyer click from a budget you set; unspent budget comes back to you.',
          onRefresh: _data.reload,
          action: GradientButton(label: 'New campaign', icon: Icons.add_rounded, compact: true, onPressed: products.isEmpty ? null : () => _create(products, d.available, cpc)),
          children: [
            if (products.isEmpty) const Tiny('You need an active, in-stock product to advertise.'),
            MetricGrid(
              children: [
                MetricCard(
                  label: 'Live campaigns',
                  value: '${ads.where((a) => a['statusKey'] == 'ACTIVE').length}',
                  icon: 'tag',
                  sub: '${ads.where((a) => a['statusKey'] == 'PENDING').length} in review',
                ),
                MetricCard(label: 'Views', value: compact(views), icon: 'eye', sub: 'Times your ads were shown'),
                MetricCard(label: 'Clicks', value: compact(clicks), icon: 'cart', sub: views > 0 ? '${(clicks / views * 100).toStringAsFixed(1)}% click rate' : 'No views yet'),
                MetricCard(label: 'Spent', value: money(spent), icon: 'wallet', sub: 'Balance ${money(d.available)}'),
              ],
            ),
            const SizedBox(height: 14),
            TabChips(
              tabs: [for (final t in _adTabs) (t.$1, t.$2)],
              value: _tab,
              counts: {for (final t in _adTabs) t.$1: t.$3 == null ? ads.length : ads.where((a) => t.$3!.contains(a['statusKey'])).length},
              onChanged: (v) => setState(() => _tab = v),
            ),
            Paged<Map<String, dynamic>>(
              items: rows,
              empty: const EmptyState(icon: Icons.campaign_outlined, title: 'No campaigns here', message: 'Create one to put a product in front of more buyers.'),
              itemBuilder: (r) {
                final key = '${r['statusKey']}';
                final live = ['ACTIVE', 'PAUSED', 'PENDING'].contains(key);
                final busy = _busy == '${r['id']}';
                return RecordCard(
                  title: strOf(r['product']),
                  subtitle: '${r['placement']} · ${r['startDate']} → ${r['endDate'] == '—' ? 'until budget ends' : r['endDate']}',
                  lines: [
                    'Budget ${money(r['budget'])} · ${money(r['spent'])} spent${live
                        ? ' · ${money(r['remaining'])} left'
                        : numOf(r['refunded']) > 0
                        ? ' · ${money(r['refunded'])} returned'
                        : ''}',
                    '${compact(r['impressions'])} views · ${compact(r['clicks'])} clicks (${r['ctr'] ?? '0%'})',
                    strOf(r['rejectionReason']),
                  ],
                  status: Pill(key == 'PENDING' ? 'IN_REVIEW' : key),
                  actions: [
                    if (key == 'ACTIVE') ActionChipBtn('Pause', busy: busy, onPressed: () => _run(r, () => jpatch('/vendor/advertisements/${r['id']}/status', {'status': 'PAUSED'}))),
                    if (key == 'PAUSED') ActionChipBtn('Resume', busy: busy, onPressed: () => _run(r, () => jpatch('/vendor/advertisements/${r['id']}/status', {'status': 'ACTIVE'}))),
                    if (live)
                      ActionChipBtn(
                        key == 'PENDING' ? 'Withdraw' : 'End',
                        danger: true,
                        busy: busy,
                        onPressed:
                            () => _run(
                              r,
                              () => jpost('/vendor/advertisements/${r['id']}/end'),
                              key == 'PENDING'
                                  ? 'Withdraw this campaign? The full ${money(r['budget'])} goes back to your balance.'
                                  : 'End this campaign now? ${money(r['remaining'])} unspent goes back to your balance.',
                            ),
                      ),
                  ],
                );
              },
            ),
            InfoBox(
              title: 'How ads work',
              text:
                  'Your budget is reserved from your available balance when you submit. MVEC reviews the campaign, usually within a day. Once live, each buyer click costs ${money(cpc)}; views are free. When the end date passes, the budget runs out or you end it, any unspent amount returns to your balance.',
            ),
          ],
        );
      },
    );
  }
}

// ─── Subscription ────────────────────────────────────────────────────────────

const _planPerks = {
  'FREE': ['Create a seller or supplier account and store', 'List products up to the Free limit', 'Receive and manage orders', 'Basic sales and inventory tools', 'Standard support'],
  'PREMIUM': [
    'Higher or unlimited product listings (fair use)',
    'Advanced sales reports and product analytics',
    'Bulk product upload',
    'Premium store branding',
    'Promotional campaigns and featured listings',
    'Priority support',
    'Low-stock alerts',
    'Growth insights',
  ],
};

/// `/vendor/subscription` and `/supplier/subscription` — Free vs Seller
/// Premium (shows "Coming soon" while MVEC's paid plans are off).
class SellerSubscriptionPage extends StatefulWidget {
  const SellerSubscriptionPage({super.key, this.endpoint = '/vendor/subscription', this.balanceLink = '/vendor/payouts'});
  final String endpoint;
  final String balanceLink;

  @override
  State<SellerSubscriptionPage> createState() => _SellerSubscriptionPageState();
}

class _SellerSubscriptionPageState extends State<SellerSubscriptionPage> {
  late final _data = Loader(() => jget(widget.endpoint));
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _change(String plan, [String? confirm]) async {
    if (confirm != null && !await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = plan);
    final ok = await runAction(context, () => jpost(widget.endpoint, {'plan': plan}));
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Subscription',
      subtitle: 'Selling on MVEC is free. Premium adds visibility and advanced tools, paid monthly from your sales balance.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final tiers = asMaps(d['tiers']);
            final sub = asMap(d['subscription']);
            final premium = sub['planKey'] == 'PREMIUM' && sub['status'] == 'Active';
            final plans = asMap(d['plans']);
            final programActive = plans['programActive'] == true;
            List<String> perks(String k) {
              final fromServer = k == 'FREE' ? plans['freeIncludes'] : plans['premiumFeatures'];
              return fromServer is List && fromServer.isNotEmpty ? [for (final x in fromServer) '$x'] : _planPerks[k]!;
            }

            final price = numOf(plans['sellerPremiumPrice'] ?? tiers.where((t) => t['planKey'] == 'PREMIUM').map((t) => t['price']).firstOrNull, 5000);
            final balance = numOf(d['availableBalance']);
            final short = !premium && balance < price;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!programActive)
                  const InfoBox(
                    title: 'Every tool is free for now',
                    text: "While MVEC grows, you have everything, including the Premium tools, at no cost. Paid plans will start later, and you'll be told well before anything changes.",
                  ),
                MetricGrid(
                  children: [
                    MetricCard(
                      label: 'Current plan',
                      value:
                          premium
                              ? 'Seller Premium'
                              : programActive
                              ? 'Free'
                              : 'Free · all tools',
                      icon: 'tag',
                      sub: premium ? (sub['autoRenew'] == true ? 'Renews ${formatDate(sub['renewalDate'])}' : 'Ends ${formatDate(sub['renewalDate'])}') : 'No monthly fee',
                    ),
                    MetricCard(label: 'Available balance', value: money(balance), icon: 'wallet', sub: 'Premium is paid from this'),
                    MetricCard(
                      label: 'Auto-renew',
                      value: premium ? (sub['autoRenew'] == true ? 'On' : 'Off') : '—',
                      icon: 'shield',
                      sub: premium ? '${money(sub['price'] ?? price)} every 30 days' : 'Starts with Premium',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final t in tiers)
                  Builder(
                    builder: (context) {
                      final isPremium = t['planKey'] == 'PREMIUM';
                      final current = isPremium == premium;
                      return DataCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(strOf(t['plan']).toUpperCase(), style: context.mvEyebrow.copyWith(fontSize: 11, letterSpacing: 1.4))),
                                if (current) const StatusChip('Active', tone: StatusTone.good),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(numOf(t['price']) > 0 ? '${money(t['price'])} / 30 days' : 'Free', style: context.mvH1.copyWith(fontSize: 20)),
                            const SizedBox(height: 8),
                            for (final p in perks('${t['planKey']}'))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.check_rounded, size: 16, color: MvColors.successText),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        t['planKey'] == 'FREE' && p.startsWith('List products') && plans['freeProductLimit'] != null ? '$p (${plans['freeProductLimit']})' : p,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            if (isPremium && !programActive && !premium) const OutlineBtn(label: 'Coming soon', onPressed: null),
                            if (isPremium && (programActive || premium))
                              premium
                                  ? (sub['autoRenew'] == true
                                      ? OutlineBtn(
                                        label: 'Turn off auto-renew',
                                        loading: _busy.isNotEmpty,
                                        onPressed: () => _change('FREE', 'Turn off auto-renew? Premium stays active until ${formatDate(sub['renewalDate'])}, then you move to Free.'),
                                      )
                                      : GradientButton(label: 'Resume auto-renew', loading: _busy.isNotEmpty, onPressed: () => _change('PREMIUM')))
                                  : Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      GradientButton(
                                        label: 'Upgrade · pay ${money(t['price'])}',
                                        loading: _busy == 'PREMIUM',
                                        onPressed:
                                            short
                                                ? null
                                                : () => _change(
                                                  'PREMIUM',
                                                  'Pay ${money(price)} from your available balance (${money(balance)}) for 30 days of Seller Premium? It renews monthly from your balance until you turn auto-renew off.',
                                                ),
                                      ),
                                      if (short) ...[
                                        Tiny('You need ${money(price - balance)} more in your available balance. Money becomes available when buyers confirm delivery.'),
                                        TextButton(onPressed: () => context.go(widget.balanceLink), child: const Text('See balance')),
                                      ],
                                    ],
                                  ),
                            if (!isPremium)
                              OutlineBtn(label: premium ? (sub['autoRenew'] == true ? 'Free after you stop renewal' : 'Starts ${formatDate(sub['renewalDate'])}') : 'Current plan', onPressed: null),
                          ],
                        ),
                      );
                    },
                  ),
                Section(
                  title: 'Billing history',
                  children: [
                    if (asMaps(d['charges']).isEmpty) const Tiny('No subscription charges yet.'),
                    for (final c in asMaps(d['charges']))
                      RecordCard(title: strOf(c['reference']), subtitle: '${formatDate(c['createdAt'])} · ${c['description'] ?? ''}', amount: '-${money(c['amount'])}', status: Pill(c['status'])),
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

/// Thumbnail for product rows that only carry the product map.
Widget productThumb(Map<String, dynamic> p, [double size = 46]) => ProductImage(src: productImage(p), size: size, radius: 8);
