import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

// Admin money and insights (web: AdminOps.jsx, payments → trust scores).

const _gateway = {'PAYPACK': 'Mobile money', 'FLUTTERWAVE': 'Card', 'KPAY': 'K-Pay', 'MOMO': 'MTN MoMo', 'AIRTEL': 'Airtel Money'};
const _method = {'MOMO': 'MTN MoMo', 'AIRTEL': 'Airtel Money', 'CARD': 'Card', 'SPENN': 'SPENN', 'CASH_ON_DELIVERY': 'Cash'};
const periods = [('7', 'Last 7 days'), ('30', 'Last 30 days'), ('90', 'Last 90 days'), ('365', 'Last 12 months')];

/// Horizontal share bar (`.progress-row`).
class ShareBar extends StatelessWidget {
  const ShareBar(this.label, this.fraction, this.value, {super.key});
  final String label;
  final num fraction;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))), Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))]),
        const SizedBox(height: 4),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: fraction.toDouble().clamp(0, 1), minHeight: 7)),
      ],
    ),
  );
}

/// A page whose loader depends on filters: rebuilds the loader on change.
mixin _Reloadable<W extends StatefulWidget, T> on State<W> {
  late Loader<T> data = makeLoader();
  Loader<T> makeLoader();

  void refilter(VoidCallback change) {
    final old = data;
    setState(() {
      change();
      data = makeLoader();
    });
    old.dispose();
  }

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }
}

/// `/admin/payments` — every payment attempt from every provider.
class AdminPaymentsPage extends StatefulWidget {
  const AdminPaymentsPage({super.key, this.status = ''});
  final String status;

  @override
  State<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends State<AdminPaymentsPage> with _Reloadable<AdminPaymentsPage, Map<String, dynamic>> {
  late String _status = widget.status;
  String _gatewayFilter = '';
  String _query = '';
  int _page = 1;
  final _q = TextEditingController();

  @override
  Loader<Map<String, dynamic>> makeLoader() => Loader(() => jget('/admin/payments', {'page': _page, 'pageSize': 25, 'status': _status, 'gateway': _gatewayFilter, 'q': _query}));

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Orders & payments',
      title: 'Payments',
      subtitle: 'Every payment attempt from buyers and sellers, from every provider.',
      onRefresh: data.reload,
      children: [
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Order number or reference',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed:
                  () => refilter(() {
                    _page = 1;
                    _query = _q.text.trim();
                  }),
            ),
          ),
          onSubmitted:
              (v) => refilter(() {
                _page = 1;
                _query = v.trim();
              }),
        ),
        const SizedBox(height: 10),
        FilterRow(
          children: [
            FilterSelect(
              label: 'Status',
              value: _status,
              options: const [('', 'All statuses'), ('SUCCESS', 'Received'), ('PENDING', 'Waiting'), ('FAILED', 'Failed'), ('REFUNDED', 'Refunded')],
              onChanged:
                  (v) => refilter(() {
                    _status = v;
                    _page = 1;
                  }),
            ),
            FilterSelect(
              label: 'Provider',
              value: _gatewayFilter,
              options: const [('', 'All providers'), ('PAYPACK', 'Mobile money'), ('FLUTTERWAVE', 'Card'), ('KPAY', 'K-Pay')],
              onChanged:
                  (v) => refilter(() {
                    _gatewayFilter = v;
                    _page = 1;
                  }),
            ),
          ],
        ),
        LoadView(
          loader: data,
          loadingLabel: 'Loading payments…',
          builder: (d) {
            final s = asMap(d['summary']);
            final by = asMap(s['byGateway']);
            final maxBy = by.values.fold<num>(1, (m, v) => numOf(v) > m ? numOf(v) : m);
            final rows = asMaps(d['data']);
            final total = numOf(asMap(d['meta'])['total']).toInt();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.isNotEmpty) ...[
                  MetricGrid(
                    children: [
                      MetricCard(icon: 'wallet', label: 'Received', value: money(s['successful']), sub: '${s['successfulCount'] ?? 0} payments · last ${s['days'] ?? 30} days'),
                      MetricCard(icon: 'chart', label: 'Waiting for the buyer', value: money(s['pending']), sub: '${s['pendingCount'] ?? 0} not confirmed yet'),
                      MetricCard(icon: 'bell', label: 'Failed', value: '${numOf(s['failedCount']).toInt()}', sub: 'Declined, timed out or cancelled'),
                      MetricCard(icon: 'box', label: 'Refunded', value: money(s['refunded']), sub: 'Provider fees ${money(s['fees'])}'),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (by.isNotEmpty)
                  Section(
                    title: 'Where the money came in',
                    subtitle: 'Successful payments by provider',
                    children: [for (final e in by.entries) ShareBar(_gateway[e.key] ?? e.key, numOf(e.value) / maxBy, money(e.value))],
                  ),
                Tiny('$total payments'),
                if (rows.isEmpty) const EmptyState(icon: Icons.payments_outlined, title: 'No payments match.'),
                for (final r in rows)
                  RecordCard(
                    title: r['order'] != null ? strOf(asMap(r['order'])['orderNumber']) : titleCase(r['purpose']),
                    subtitle: '${strOf(asMap(r['payer'])['name'], '—')} · ${formatDateTime(r['createdAt'])}',
                    lines: ['${r['gateway'] == 'KPAY' ? 'K-Pay · ' : ''}${_method[r['method']] ?? r['method'] ?? ''}'],
                    amount: money(r['amount']),
                    status: Pill(r['status'], label: const {'SUCCESS': 'Received', 'PENDING': 'Waiting', 'PROCESSING': 'Waiting'}[r['status']]),
                    onTap: r['order'] == null ? null : () => context.push('/admin/orders/${idOf(r['order'])}'),
                  ),
                if (total > 25) PaginationBar(page: _page, total: total, perPage: 25, onPage: (p) => refilter(() => _page = p)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── MVEC earnings ──────────────────────────────────────────────────────────

class _MvecWallet extends StatefulWidget {
  const _MvecWallet();

  @override
  State<_MvecWallet> createState() => _MvecWalletState();
}

class _MvecWalletState extends State<_MvecWallet> {
  late final _data = Loader(() async {
    final r = await Future.wait([jget('/admin/payouts/balance'), jget('/admin/payouts/history')]);
    return (wallet: asMap(r[0]['wallet']), history: asMaps(r[1]['payouts']));
  });

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _record(num available) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Record a withdrawal',
      subtitle: "The money sits in MVEC's payment provider accounts (Paypack, Flutterwave, K-Pay). Move it to the company bank there, then record it here so the books match.",
      fields: [
        FieldSpec('amount', 'Amount moved (RWF)', type: FieldType.number, required: true, help: 'Up to ${money(available)}.'),
        const FieldSpec('destination', 'Moved to', required: true, hint: 'e.g. BK account 000400012345'),
        const FieldSpec('note', 'Note (optional)', hint: 'Provider reference, purpose…'),
      ],
      submitLabel: 'Record withdrawal',
      onSubmit: (v) => jpost('/admin/payouts/request', {...v, 'amount': numOf(v['amount'])}),
    );
    if (res != null && mounted) {
      toast(context, strOf(res['message'], 'Withdrawal recorded.'));
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      loadingLabel: 'Loading the wallet…',
      builder: (d) {
        final w = d.wallet;
        final available = numOf(w['availableBalance']);
        return Section(
          title: 'MVEC wallet',
          subtitle: 'What MVEC keeps after sellers, suppliers, affiliates and provider fees, plus ad and subscription income.',
          children: [
            MetricGrid(
              children: [
                MetricCard(icon: 'wallet', label: 'Available', value: money(available), sub: 'From delivered orders'),
                MetricCard(icon: 'chart', label: 'Held until delivery', value: money(w['pendingBalance']), sub: 'Becomes available on delivery'),
                MetricCard(icon: 'box', label: 'Withdrawn', value: money(w['totalWithdrawn']), sub: '${d.history.length} recorded'),
              ],
            ),
            if (available > 0) ...[const SizedBox(height: 10), OutlineBtn(label: 'Record a withdrawal', compact: true, onPressed: () => _record(available))],
            if (d.history.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Recorded withdrawals', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final p in d.history.take(8))
                Tiny(
                  '${formatDate(p['createdAt'])} · ${money(p['amount'])} to ${strOf(asMap(p['accountDetails'])['accountNumber'] ?? p['accountNumber'], '—')} · by ${personName(p['adminUser'], 'admin')}',
                ),
            ],
          ],
        );
      },
    );
  }
}

/// `/admin/commissions` — what MVEC earns on every sale.
class AdminEarningsPage extends StatefulWidget {
  const AdminEarningsPage({super.key});

  @override
  State<AdminEarningsPage> createState() => _AdminEarningsPageState();
}

class _AdminEarningsPageState extends State<AdminEarningsPage> with _Reloadable<AdminEarningsPage, Map<String, dynamic>> {
  String _days = '30';
  int _page = 1;

  @override
  Loader<Map<String, dynamic>> makeLoader() => Loader(() => jget('/admin/earnings', {'days': _days, 'page': _page, 'pageSize': 25}));

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Orders & payments',
      title: 'MVEC earnings',
      subtitle: 'What MVEC earns on every sale, and where the rest of the money goes.',
      onRefresh: data.reload,
      action: FilterSelect(
        label: 'Period',
        value: _days,
        options: periods,
        onChanged:
            (v) => refilter(() {
              _days = v;
              _page = 1;
            }),
      ),
      children: [
        const _MvecWallet(),
        LoadView(
          loader: data,
          loadingLabel: 'Loading earnings…',
          builder: (d) {
            final t = asMap(d['totals']);
            final fee = numOf(t['platformFee']);
            final affiliatesByMvec = (numOf(t['affiliates']) - numOf(t['affiliatesPaidBySellers'])).clamp(0, double.infinity);
            final rows = asMaps(d['data']);
            final total = numOf(asMap(d['meta'])['total']).toInt();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (t.isNotEmpty) ...[
                  MetricGrid(
                    children: [
                      MetricCard(icon: 'chart', label: 'Sales', value: money(t['gross']), sub: 'Paid order lines, excluding refunds'),
                      MetricCard(icon: 'wallet', label: 'MVEC commission', value: money(fee), sub: 'From the commission rules'),
                      MetricCard(icon: 'shop', label: 'MVEC keeps', value: money(t['mvecNet']), sub: '${money(t['released'])} earned · ${money(t['held'])} until delivery'),
                      MetricCard(icon: 'users', label: "Sellers' share", value: money(t['sellers']), sub: "After MVEC's fee; theirs to withdraw once delivered"),
                      if (numOf(t['adRevenue']) > 0 || numOf(t['subscriptionRevenue']) > 0) ...[
                        MetricCard(icon: 'tag', label: 'Ad clicks', value: money(t['adRevenue']), sub: 'Sponsored products, MVEC income'),
                        MetricCard(icon: 'wallet', label: 'Subscriptions', value: money(t['subscriptionRevenue']), sub: 'Premium plans, MVEC income'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Section(
                    title: "Where MVEC's fee goes",
                    subtitle: 'From ${money(fee)} in fees',
                    children: [
                      for (final (label, v) in [('Affiliates (paid by MVEC)', affiliatesByMvec), ('Payment provider fees', numOf(t['gatewayFees'])), ('MVEC keeps', numOf(t['mvecNet']))])
                        ShareBar(label, fee == 0 ? 0 : v / fee, money(v)),
                      if (numOf(t['affiliatesPaidBySellers']) > 0) Tiny('Sellers also paid affiliates ${money(t['affiliatesPaidBySellers'])} from their own share.'),
                    ],
                  ),
                ],
                Section(
                  title: 'Per order line',
                  subtitle: '$total lines',
                  children: [
                    if (rows.isEmpty) const Tiny('No sales in this period.'),
                    for (final r in rows)
                      Builder(
                        builder: (_) {
                          final o = asMap(r['order']);
                          final wholesale = o['kind'] == 'Wholesale';
                          return RecordCard(
                            title: strOf(o['orderNumber'], '—'),
                            badges: [if (wholesale) const StatusChip('Wholesale')],
                            subtitle: 'Paid to ${r['seller'] ?? '—'}',
                            lines: [
                              'Sale ${money(r['gross'])} · commission ${money(r['platformFee'])}${r['rate'] != null ? ' (${r['rate']}%)' : ''}',
                              if (numOf(r['affiliate']) > 0) 'Affiliate ${money(r['affiliate'])}',
                            ],
                            amount: money(r['mvecNet']),
                            status: Pill(
                              r['status'],
                              label: const {'HELD': 'Until delivery', 'RELEASED': 'Earned', 'ADMIN_HOLD': 'On hold', 'REFUNDED': 'Refunded', 'CANCELLED': 'Cancelled'}[r['status']],
                            ),
                            onTap: o.isEmpty || wholesale ? null : () => context.push('/admin/orders/${idOf(o)}'),
                          );
                        },
                      ),
                    if (total > 25) PaginationBar(page: _page, total: total, perPage: 25, onPage: (p) => refilter(() => _page = p)),
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

// ─── Ledger ─────────────────────────────────────────────────────────────────

const ledgerEntry = {
  'PAYMENT_RECEIVED': 'Buyer payment received',
  'PAYMENT_ESCROW_LOCK': 'Buyer payment received',
  'ESCROW_RELEASE_VENDOR': 'Seller paid (delivery)',
  'PLATFORM_COMMISSION_DEDUCTION': 'MVEC commission',
  'AFFILIATE_COMMISSION': 'Affiliate commission',
  'GATEWAY_FEE': 'Payment provider fee',
  'BUYER_REFUND': 'Refund to buyer',
  'PAYOUT_SENT': 'Withdrawal sent',
  'AD_BUDGET_RESERVED': 'Ad budget reserved',
  'AD_BUDGET_RETURNED': 'Ad budget returned',
  'AD_CLICK_REVENUE': 'Ad click (MVEC income)',
  'SUBSCRIPTION_FEE': 'Subscription fee (MVEC income)',
  'COURIER_FEE_PAYOUT': 'Courier fee',
  'ADMIN_MANUAL_ADJUSTMENT': 'Correction',
};
const ledgerAccount = {
  'BUYER_PAYMENTS': 'Buyer payments',
  'ESCROW_HOLDING': 'MVEC holding',
  'PLATFORM_REVENUE': 'MVEC revenue',
  'ADMIN_REVENUE': 'MVEC revenue',
  'DEVELOPER_REVENUE': 'MVEC revenue',
  'VENDOR_PAYABLE': 'Seller balances',
  'SUPPLIER_PAYABLE': 'Supplier balances',
  'COURIER_PAYABLE': 'Courier balances',
  'AFFILIATE_COMMISSION': 'Affiliate commission',
  'GATEWAY_FEES': 'Provider fees',
  'AD_BUDGETS': 'Ad budgets',
  'BUYER_REFUND_HOLD': 'Refunded to buyers',
  'PAID_OUT': 'Paid out',
};
const _balanceRows = [
  ('BUYER_PAYMENTS', 'Total buyers have paid in (shown negative: it came from outside)'),
  ('ESCROW_HOLDING', 'Held by MVEC until delivery'),
  ('VENDOR_PAYABLE', 'Earned by sellers and suppliers, not yet withdrawn'),
  ('PLATFORM_REVENUE', 'Earned by MVEC, not yet withdrawn'),
  ('AFFILIATE_COMMISSION', 'Earned by affiliates, not yet withdrawn'),
  ('GATEWAY_FEES', 'Payment provider fees'),
  ('AD_BUDGETS', 'Ad budgets reserved, not yet spent'),
  ('BUYER_REFUND_HOLD', 'Refunded to buyers'),
  ('PAID_OUT', 'Sent out to sellers, suppliers, affiliates and MVEC'),
];

/// `/admin/ledger` — double-entry books and where the money is.
class AdminLedgerPage extends StatefulWidget {
  const AdminLedgerPage({super.key});

  @override
  State<AdminLedgerPage> createState() => _AdminLedgerPageState();
}

class _AdminLedgerPageState extends State<AdminLedgerPage> with _Reloadable<AdminLedgerPage, Map<String, dynamic>> {
  String _type = '';
  int _page = 1;

  @override
  Loader<Map<String, dynamic>> makeLoader() => Loader(() => jget('/admin/ledger', {'page': _page, 'limit': 25, if (_type.isNotEmpty) 'entryType': _type}));

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Orders & payments',
      title: 'Financial ledger',
      subtitle: "Every movement of money goes from one account to another and both balances change together, so the books always add up. Entries are written automatically and can't be edited.",
      onRefresh: data.reload,
      children: [
        LoadView(
          loader: data,
          loadingLabel: 'Loading the ledger…',
          builder: (d) {
            final b = asMap(d['balances']);
            num bal(String k) =>
                k == 'PLATFORM_REVENUE'
                    ? numOf(b['PLATFORM_REVENUE']) + numOf(b['ADMIN_REVENUE']) + numOf(b['DEVELOPER_REVENUE'])
                    : k == 'VENDOR_PAYABLE'
                    ? numOf(b['VENDOR_PAYABLE']) + numOf(b['SUPPLIER_PAYABLE'])
                    : numOf(b[k]);
            final entries = asMaps(d['entries']);
            final total = numOf(d['total']).toInt();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (b.isNotEmpty)
                  Section(
                    title: 'Where the money is',
                    subtitle: "Real money sits in MVEC's payment provider account; this says whose it is.",
                    trailing: StatusChip(d['balanced'] == true ? 'Books balance' : 'Books do not balance', tone: d['balanced'] == true ? StatusTone.good : StatusTone.warn),
                    children: [
                      for (final (k, label) in _balanceRows) RecordCard(title: ledgerAccount[k]!, subtitle: label, amount: money(bal(k))),
                      const Tiny('Should match your Paypack balance: buyer payments − refunds − money paid out.'),
                    ],
                  ),
                FilterSelect(
                  label: 'Entry type',
                  value: _type,
                  options: [('', 'All entries'), for (final e in ledgerEntry.entries) (e.key, e.value)],
                  onChanged:
                      (v) => refilter(() {
                        _type = v;
                        _page = 1;
                      }),
                ),
                const SizedBox(height: 10),
                Tiny('$total entries'),
                if (entries.isEmpty) const EmptyState(icon: Icons.menu_book_outlined, title: 'No ledger entries yet.'),
                for (final r in entries)
                  RecordCard(
                    title: ledgerEntry[r['entryType']] ?? titleCase(r['entryType']),
                    subtitle: '${ledgerAccount[asMap(r['debitAccount'])['accountType']] ?? '—'} → ${ledgerAccount[asMap(r['creditAccount'])['accountType']] ?? '—'}',
                    lines: [formatDateTime(r['createdAt']), if (r['relatedOrder'] is Map) 'Order ${asMap(r['relatedOrder'])['orderNumber'] ?? ''}'],
                    amount: money(r['amount']),
                    onTap: r['relatedOrder'] == null ? null : () => context.push('/admin/orders/${idOf(r['relatedOrder'])}'),
                  ),
                if (total > 25) PaginationBar(page: _page, total: total, perPage: 25, onPage: (p) => refilter(() => _page = p)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Analytics ──────────────────────────────────────────────────────────────

const _roleTitle = {'buyer': 'Buyers', 'vendor': 'Sellers', 'supplier': 'Suppliers', 'affiliate': 'Affiliates', 'delivery': 'Couriers', 'super_admin': 'Admins', 'developer': 'Developers'};

Widget _breakdown(String title, String? sub, List<(String, num)> entries, [String Function(num)? format]) {
  final maxV = entries.fold<num>(1, (m, e) => e.$2 > m ? e.$2 : m);
  return Section(
    title: title,
    subtitle: sub,
    children: [if (entries.isEmpty) const Tiny('Nothing yet in this period.'), for (final (k, v) in entries) ShareBar(k, v / maxV, format == null ? '$v' : format(v))],
  );
}

/// `/admin/analytics` — sales, orders and growth.
class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> with _Reloadable<AdminAnalyticsPage, Map<String, dynamic>> {
  String _days = '30';

  @override
  Loader<Map<String, dynamic>> makeLoader() => Loader(() => jget('/admin/analytics', {'days': _days}));

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Insights',
      title: 'Marketplace analytics',
      subtitle: 'Sales, orders and growth from real orders. Refunded orders are left out of sales.',
      onRefresh: data.reload,
      action: FilterSelect(label: 'Period', value: _days, options: periods, onChanged: (v) => refilter(() => _days = v)),
      children: [
        LoadView(
          loader: data,
          loadingLabel: 'Loading analytics…',
          builder: (d) {
            final t = asMap(d['totals']);
            final change = t['gmvChange'];
            final series = asMaps(d['series']);
            final bars = series.length > 31 ? series.sublist(series.length - 31) : series;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(
                      icon: 'chart',
                      label: 'Sales',
                      value: money(t['gmv']),
                      sub: change == null ? 'No sales in the period before' : '${numOf(change) >= 0 ? '▲' : '▼'} ${numOf(change).abs()}% vs the period before',
                    ),
                    MetricCard(icon: 'cart', label: 'Paid orders', value: '${numOf(t['paidOrders']).toInt()}', sub: '${numOf(t['orders']).toInt()} placed · ${numOf(t['conversion'])}% paid'),
                    MetricCard(icon: 'wallet', label: 'Average order', value: money(t['averageOrder']), sub: 'MVEC kept ${money(t['mvecEarned'])}'),
                    MetricCard(
                      icon: 'users',
                      label: 'New accounts',
                      value: '${numOf(t['newUsers']).toInt()}',
                      sub: 'Refund rate ${numOf(t['refundRate'])}% · ${numOf(t['disputes']).toInt()} dispute${numOf(t['disputes']) == 1 ? '' : 's'}',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'Daily sales',
                  subtitle: bars.length < series.length ? 'Last ${bars.length} days shown' : null,
                  children: [
                    MiniBars(data: [for (final s in bars) ('${s['day']}'.length >= 10 ? '${s['day']}'.substring(8, 10) : '${s['day']}', numOf(s['gmv']))], height: 110),
                  ],
                ),
                _breakdown('Top sellers', 'By sales', [for (final v in asMaps(d['topSellers'])) (strOf(v['name']), numOf(v['sales']))], money),
                _breakdown('Top products', 'Product sales, before delivery fees (units sold in brackets)', [
                  for (final v in asMaps(d['topProducts'])) ('${v['name']} (${v['units']})', numOf(v['sales'])),
                ], money),
                _breakdown('How buyers pay', null, [for (final e in asMap(d['paymentMix']).entries) (e.key, numOf(e.value))], money),
                _breakdown('Orders by status', null, [for (final e in asMap(d['statusBreakdown']).entries) (titleCase(e.key), numOf(e.value))]),
                _breakdown('New accounts', 'By type', [for (final e in asMap(d['newUsers']).entries) (_roleTitle[e.key] ?? e.key, numOf(e.value))]),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Risk & trust ───────────────────────────────────────────────────────────

/// `/admin/risk` — warning signs found automatically.
class AdminRiskPage extends StatefulWidget {
  const AdminRiskPage({super.key});

  @override
  State<AdminRiskPage> createState() => _AdminRiskPageState();
}

class _AdminRiskPageState extends State<AdminRiskPage> {
  late final _data = Loader(() => jlist('/admin/risk', 'signals'));
  Timer? _timer;
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _data.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  Future<void> _report(Map<String, dynamic> s, String status) async {
    var notes = '';
    if (status == 'RESOLVED' || status == 'REJECTED') {
      final v = await promptDialog(context, 'Add a note for the record (optional)', required: false, confirm: 'Save');
      if (v == null) return;
      notes = v;
    }
    if (!mounted) return;
    setState(() => _busy = '${s['id']}');
    final ok = await runAction(context, () => jpatch('/abuse-reports/${s['reportId']}', {'status': status, 'adminNotes': notes}), success: 'Report updated.');
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Platform',
      title: 'Fraud & risk',
      subtitle: 'Warning signs found automatically in payments, refunds, disputes, deliveries, affiliate sales and abuse reports. The list updates by itself.',
      onRefresh: _data.reload,
      action: OutlineBtn(label: 'Check again', compact: true, onPressed: _data.reload),
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading risk signals…',
          builder:
              (rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      for (final (l, sub) in const [('High', 'Act today'), ('Medium', 'Look this week'), ('Low', 'Keep an eye on')])
                        MetricCard(icon: 'bell', label: '$l risk', value: '${rows.where((r) => r['level'] == l).length}', sub: sub),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (rows.isEmpty)
                    const EmptyState(
                      icon: Icons.verified_user_outlined,
                      title: 'No warning signs',
                      message: 'Checked: repeated failed payments, refunds and disputes per seller, late shipping, reversed affiliate sales and abuse reports.',
                    ),
                  for (final s in rows)
                    RecordCard(
                      title: '${s['partyName'] ?? ''}${strOf(s['partyRole']).isNotEmpty ? ' · ${(_roleTitle[s['partyRole']] ?? '${s['partyRole']}').replaceFirst(RegExp(r's$'), '')}' : ''}',
                      subtitle: '${s['area'] ?? ''}: ${s['signal'] ?? ''}',
                      status: StatusChip('${s['level']} risk', tone: s['level'] == 'High' ? StatusTone.bad : StatusTone.warn),
                      actions: [
                        if (s['reportId'] != null && s['reportStatus'] == 'PENDING') ActionChipBtn('Investigating', busy: _busy == '${s['id']}', onPressed: () => _report(s, 'INVESTIGATE')),
                        if (s['reportId'] != null) ...[
                          ActionChipBtn('Resolved', primary: true, busy: _busy == '${s['id']}', onPressed: () => _report(s, 'RESOLVED')),
                          ActionChipBtn('Not a problem', busy: _busy == '${s['id']}', onPressed: () => _report(s, 'REJECTED')),
                        ],
                        if (strOf(s['link']).startsWith('/')) ActionChipBtn('Open', onPressed: () => context.push(strOf(s['link']))),
                      ],
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

/// `/admin/trust` — seller trust scores.
class AdminTrustPage extends StatefulWidget {
  const AdminTrustPage({super.key});

  @override
  State<AdminTrustPage> createState() => _AdminTrustPageState();
}

class _AdminTrustPageState extends State<AdminTrustPage> {
  late final _data = Loader(() => jlist('/admin/trust', 'data'));
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Insights',
      title: 'Seller trust scores',
      subtitle:
          "Out of 100, from each seller's finished orders in the last 90 days: delivered (50), not refunded (20), no disputes (20) and buyer rating (10). Sellers with fewer than 3 finished orders show as New.",
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading trust scores…',
          builder:
              (rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      for (final (b, sub) in const [('Trusted', '80 and above'), ('Watch', '60 to 79'), ('At risk', 'Below 60'), ('New', 'Not enough orders yet')])
                        MetricCard(icon: 'shop', label: b, value: '${rows.where((r) => r['band'] == b).length}', sub: sub),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SearchBox(hint: 'Search sellers…', onChanged: (v) => setState(() => _q = v)),
                  Paged<Map<String, dynamic>>(
                    items: rows.where((r) => matches(_q, [r['name']])).toList(),
                    perPage: 20,
                    empty: const EmptyState(icon: Icons.storefront_outlined, title: 'No sellers yet.'),
                    itemBuilder:
                        (r) => RecordCard(
                          title: strOf(r['name']),
                          subtitle: '${numOf(r['orders']).toInt()} orders in 90 days${numOf(r['inProgress']) > 0 ? ' · ${r['inProgress']} in progress' : ''}',
                          lines: [
                            if (numOf(r['finished']) > 0) 'Delivered ${numOf(r['completion'])}% · refunded ${numOf(r['refundRate'])}%',
                            numOf(r['rating']) > 0 ? '★ ${numOf(r['rating']).toStringAsFixed(1)}' : 'No reviews',
                          ],
                          amount: r['score'] == null ? '—' : '${r['score']}',
                          status: StatusChip(
                            strOf(r['band']),
                            tone:
                                r['band'] == 'Trusted'
                                    ? StatusTone.good
                                    : r['band'] == 'At risk'
                                    ? StatusTone.bad
                                    : StatusTone.warn,
                          ),
                        ),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}
