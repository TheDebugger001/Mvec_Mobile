import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import '../seller/seller_common.dart';
import '../wholesale/wholesale_pages.dart' show units;

// The supplier dashboard (web: pages/SupplierDashboard.jsx).

const kSupplierPayoutMinimum = 50000;

/// Reloads every 30 seconds while shown, like the web's `Remote`.
mixin _Polling<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  void startPolling(Future<void> Function() reload) => _timer = Timer.periodic(const Duration(seconds: 30), (_) => reload());

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _VerificationBanner extends ConsumerWidget {
  const _VerificationBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((a) => a.user));
    if (user?.verificationStatus == 'REJECTED') {
      return Notice(
        text: 'MVEC asked you to update your profile.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tiny('${user!.verificationNote.isEmpty ? 'Check your details.' : user.verificationNote} Saving your profile sends it back for review automatically.'),
            ActionChipBtn('Fix it in Settings', primary: true, onPressed: () => context.go('/supplier/settings')),
          ],
        ),
      );
    }
    if (user?.verificationStatus == 'PENDING') return const Notice(info: true, text: 'MVEC is reviewing your profile. You will get a message, SMS and email when it is done.');
    return const SizedBox.shrink();
  }
}

/// `/supplier` — what needs doing now and how the business is doing.
class SupplierOverviewPage extends ConsumerStatefulWidget {
  const SupplierOverviewPage({super.key});

  @override
  ConsumerState<SupplierOverviewPage> createState() => _SupplierOverviewPageState();
}

class _SupplierOverviewPageState extends ConsumerState<SupplierOverviewPage> with _Polling {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([
      jget('/suppliers/me/finance/summary'),
      jlist('/suppliers/me/products', 'products'),
      jget('/suppliers/me/delivery/summary'),
      jlist('/wholesale/orders/mine', 'orders').catchError((_) => <Map<String, dynamic>>[]),
      jlist('/quotes/open', 'requests').catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (
      finance: asMap((r[0] as Map)['summary']),
      products: r[1] as List<Map<String, dynamic>>,
      delivery: asMap((r[2] as Map)['summary']),
      orders: r[3] as List<Map<String, dynamic>>,
      requests: r[4] as List<Map<String, dynamic>>,
    );
  }, auto: false);

  @override
  void initState() {
    super.initState();
    if (ref.read(authProvider).user?.isOnboarded != false) {
      _data.reload();
      startPolling(_data.reload);
    }
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider.select((a) => a.user));
    if (user?.isOnboarded == false) {
      return const PortalPage(
        eyebrow: 'Supplier platform',
        title: 'Supplier dashboard',
        subtitle: 'Complete onboarding to unlock live supplier operations.',
        children: [
          OnboardingBanner(),
          MetricGrid(
            children: [
              MetricCard(icon: 'box', label: 'Wholesale products', value: '—', sub: 'Available after onboarding'),
              MetricCard(icon: 'cart', label: 'Vendor orders', value: '—', sub: 'Available after onboarding'),
              MetricCard(icon: 'chart', label: 'Sales', value: '—', sub: 'Available after onboarding'),
              MetricCard(icon: 'wallet', label: 'Protected funds', value: '—', sub: 'Available after onboarding'),
            ],
          ),
        ],
      );
    }
    return PortalPage(
      eyebrow: 'Supplier platform',
      title: 'Supplier dashboard',
      subtitle: 'What needs your attention, and how your wholesale business is doing.',
      onRefresh: _data.reload,
      children: [
        const OnboardingBanner(),
        const _VerificationBanner(),
        LoadView(
          loader: _data,
          loadingLabel: 'Loading live supplier data…',
          builder: (d) {
            final toShip = d.orders.where((o) => o['status'] == 'ESCROW_HELD').length;
            final disputed = d.orders.where((o) => o['status'] == 'DISPUTED').length;
            final low = d.products.where((p) => numOf(p['stockQuantity']) < (numOf(p['moq']) > 10 ? numOf(p['moq']) : 10)).toList();
            final toQuote = d.requests.where((r) => r['matchesMyCategory'] == true && r['myQuote'] == null).toList();
            final todo = <(String, String, String, bool)>[
              if (toShip > 0) ('$toShip paid order${toShip == 1 ? '' : 's'} to ship', 'Ship within 7 days. MVEC holds the money until the vendor confirms receipt.', '/supplier/orders', true),
              if (disputed > 0)
                ('$disputed order${disputed == 1 ? '' : 's'} with a reported problem', 'MVEC is reviewing; contact the vendor in Messages if you can fix it.', '/supplier/orders', true),
              if (low.isNotEmpty) ('${low.length} product${low.length == 1 ? '' : 's'} running low', low.take(3).map((p) => p['name']).join(', '), '/supplier/inventory', false),
              if (numOf(d.finance['availablePayout']) >= kSupplierPayoutMinimum)
                ('${money(d.finance['availablePayout'])} ready to withdraw', 'Request a payout to mobile money or your bank.', '/supplier/payments', false),
              if (toQuote.isNotEmpty)
                (
                  '${toQuote.length} vendor${toQuote.length == 1 ? '' : 's'} asking for quotes in your category',
                  toQuote.take(3).map((r) => asMaps(r['lines']).map((l) => '${l['units']} ${l['unit']} ${l['product']}').join(', ')).join(' · '),
                  '/supplier/quotes',
                  false,
                ),
              if (d.products.isEmpty) ('Add your first wholesale product', 'Vendors can only order what is in your catalog.', '/supplier/products', true),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Section(
                  title: 'To do',
                  subtitle: todo.isEmpty ? 'You are all caught up' : 'Updates every 30 seconds',
                  children: [
                    if (todo.isEmpty) const EmptyState(icon: Icons.task_alt_rounded, title: 'Nothing waiting', message: 'New orders, low stock and payouts show up here.'),
                    for (final (text, hint, link, urgent) in todo)
                      RecordCard(
                        title: text,
                        subtitle: hint,
                        leading: Icon(urgent ? Icons.priority_high_rounded : Icons.arrow_forward_rounded, color: urgent ? MvColors.errorText : context.mv.accentDeep),
                        onTap: () => context.go(link),
                      ),
                  ],
                ),
                MetricGrid(
                  children: [
                    MetricCard(icon: 'box', label: 'Wholesale products', value: '${d.products.length}', sub: 'In your catalog'),
                    MetricCard(
                      icon: 'cart',
                      label: 'Vendor orders',
                      value: '${numOf(d.delivery['activeShipments']) + numOf(d.delivery['deliveredThisMonth'])}',
                      sub: '${numOf(d.delivery['activeShipments']).toInt()} in progress',
                    ),
                    MetricCard(icon: 'chart', label: 'Sales', value: money(d.finance['grossSales']), sub: 'Total wholesale sales'),
                    MetricCard(icon: 'wallet', label: 'Held by MVEC', value: money(d.finance['escrowHeld']), sub: 'Paid to you when vendors confirm receipt'),
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

// ─── Products & inventory ────────────────────────────────────────────────────

/// `/supplier/products` — the wholesale catalog.
class SupplierProductsPage extends StatefulWidget {
  const SupplierProductsPage({super.key});

  @override
  State<SupplierProductsPage> createState() => _SupplierProductsPageState();
}

class _SupplierProductsPageState extends State<SupplierProductsPage> with _Polling {
  late final _data = Loader(() => jlist('/suppliers/me/products', 'products'));
  List<Map<String, dynamic>> _categories = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    startPolling(_data.reload);
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? p) async {
    final v = p ?? {'name': '', 'category': 'General', 'unit': 'piece', 'wholesalePrice': 0, 'moq': 1, 'stockQuantity': 0, 'bulkDiscount': 0, 'shortDescription': ''};
    final cats = [for (final c in _categories) (strOf(c['name']), strOf(c['name']))];
    final cat = strOf(v['category']);
    if (cat.isNotEmpty && !cats.any((c) => c.$1 == cat)) cats.insert(0, (cat, cat));
    final unit = strOf(v['unit'], 'piece');
    final saved = await showFormSheet<bool>(
      context,
      title: '${p == null ? 'Add' : 'Edit'} wholesale product',
      fields: [
        const FieldSpec('name', 'Product name', required: true),
        FieldSpec('category', 'Category', type: FieldType.select, required: true, options: cats),
        FieldSpec(
          'unit',
          'Sold per',
          type: FieldType.select,
          required: true,
          options: [
            for (final u in units.contains(unit) ? units : [unit, ...units]) (u, u),
          ],
        ),
        const FieldSpec('wholesalePrice', 'Wholesale price (RWF)', type: FieldType.number, required: true),
        const FieldSpec('retailPrice', 'Suggested retail price (RWF)', type: FieldType.number),
        const FieldSpec('moq', 'Minimum order (units)', type: FieldType.number, required: true),
        const FieldSpec('stockQuantity', 'Units in stock', type: FieldType.number, required: true),
        const FieldSpec('bulkDiscount', 'Bulk discount (%)', type: FieldType.number),
        const FieldSpec('status', 'Status', type: FieldType.select, options: [('ACTIVE', 'Active: vendors can order it'), ('ARCHIVED', 'Archived: hidden from vendors')]),
        const FieldSpec('shortDescription', 'Short description', type: FieldType.textarea),
      ],
      initial: {
        for (final k in ['name', 'category', 'unit', 'shortDescription']) k: strOf(v[k]),
        for (final k in ['wholesalePrice', 'retailPrice', 'moq', 'stockQuantity', 'bulkDiscount']) k: v[k] == null ? '' : '${numOf(v[k])}',
        'status': v['status'] == 'ARCHIVED' ? 'ARCHIVED' : 'ACTIVE',
      },
      onSubmit: (f) async {
        if (numOf(f['moq']) < 1) throw ApiException('The minimum order must be at least 1 unit.');
        if (numOf(f['bulkDiscount']) > 100) throw ApiException('The bulk discount must be 100% or less.');
        final body = {
          ...f,
          for (final k in ['wholesalePrice', 'moq', 'stockQuantity', 'bulkDiscount']) k: numOf(f[k]),
          'retailPrice': '${f['retailPrice'] ?? ''}'.isEmpty ? null : numOf(f['retailPrice']),
        };
        if (p == null) {
          await jpost('/suppliers/me/products', body);
        } else {
          await jput('/suppliers/me/products/${idOf(p)}', body);
        }
        return true;
      },
    );
    if (saved == true && mounted) {
      toast(context, p == null ? 'Product added.' : 'Product saved.');
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Supplier platform',
      title: 'Wholesale products',
      subtitle: 'Manage products stored in the supplier catalog.',
      onRefresh: _data.reload,
      action: GradientButton(label: 'Add wholesale product', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null)),
      children: [
        SearchBox(hint: 'Search wholesale products…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder:
              (rows) => Paged<Map<String, dynamic>>(
                items: rows.where((p) => matches(_q, [p['name'], p['category']])).toList(),
                empty: const EmptyState(icon: Icons.inventory_2_outlined, title: 'No wholesale products yet', message: 'Vendors can only order what is in your catalog.'),
                itemBuilder:
                    (p) => RecordCard(
                      leading: ProductImage(src: strOf(asMap(p['media'])['mainImage']), size: 48, radius: 8),
                      title: strOf(p['name']),
                      subtitle: '${p['category'] ?? ''} · per ${p['unit'] ?? 'piece'} · MOQ ${numOf(p['moq'], 1).toInt()}',
                      lines: ['${money(p['wholesalePrice'])}${numOf(p['bulkDiscount']) > 0 ? ' · -${p['bulkDiscount']}% bulk' : ''} · ${numOf(p['stockQuantity']).toInt()} in stock'],
                      status: Pill(p['status']),
                      actions: [
                        ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(p)),
                        ActionChipBtn(
                          'Delete',
                          danger: true,
                          onPressed: () async {
                            if (!await confirmDialog(context, 'Delete ${p['name']}?', confirm: 'Delete', danger: true)) return;
                            if (context.mounted && await runAction(context, () => jdelete('/suppliers/me/products/${idOf(p)}'), success: 'Product deleted.')) _data.reload();
                          },
                        ),
                      ],
                    ),
              ),
        ),
      ],
    );
  }
}

/// `/supplier/inventory` — stock per wholesale product.
class SupplierInventoryPage extends StatefulWidget {
  const SupplierInventoryPage({super.key});

  @override
  State<SupplierInventoryPage> createState() => _SupplierInventoryPageState();
}

class _SupplierInventoryPageState extends State<SupplierInventoryPage> with _Polling {
  late final _data = Loader(() => jlist('/suppliers/me/products', 'products'));
  String _q = '';

  @override
  void initState() {
    super.initState();
    startPolling(_data.reload);
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Inventory',
      title: 'Inventory',
      subtitle: 'Stock quantities from supplier product records.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder:
              (rows) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      MetricCard(icon: 'box', label: 'Stock units', value: compact(rows.fold<num>(0, (s, p) => s + numOf(p['stockQuantity']))), sub: 'Across your products'),
                      MetricCard(icon: 'grid', label: 'Low stock', value: '${rows.where((p) => numOf(p['stockQuantity']) < 10).length}', sub: 'Below 10 units'),
                      MetricCard(icon: 'cart', label: 'Catalog items', value: '${rows.length}', sub: 'Supplier products'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SearchBox(hint: 'Search inventory…', onChanged: (v) => setState(() => _q = v)),
                  Paged<Map<String, dynamic>>(
                    items: rows.where((p) => matches(_q, [p['name']])).toList(),
                    empty: const EmptyState(icon: Icons.inventory_2_outlined, title: 'No inventory records yet'),
                    itemBuilder:
                        (p) => RecordCard(
                          title: strOf(p['name']),
                          subtitle: 'MOQ ${numOf(p['moq'], 1).toInt()} · ${p['unit'] ?? 'piece'}',
                          amount: '${numOf(p['stockQuantity']).toInt()} available',
                          status: numOf(p['stockQuantity']) < 10 ? const StatusChip('Low stock', tone: StatusTone.warn) : Pill(p['status']),
                        ),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

// ─── Analytics, payments, reports, transactions, reviews ────────────────────

/// `/supplier/analytics` — wholesale performance (Premium: growth insights).
class SupplierAnalyticsPage extends StatefulWidget {
  const SupplierAnalyticsPage({super.key});

  @override
  State<SupplierAnalyticsPage> createState() => _SupplierAnalyticsPageState();
}

class _SupplierAnalyticsPageState extends State<SupplierAnalyticsPage> {
  String _range = '30d';
  late Loader<Map<String, dynamic>> _data = _load();

  Loader<Map<String, dynamic>> _load() => Loader(() async => asMap((await jget('/suppliers/me/finance/analytics', {'range': _range}))['analytics']));

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      feature: 'growthInsights',
      title: 'Growth insights',
      base: '/supplier',
      child: PortalPage(
        eyebrow: 'Analytics',
        title: 'Analytics',
        subtitle: 'Wholesale performance calculated from your orders.',
        onRefresh: _data.reload,
        action: FilterSelect(
          label: 'Period',
          value: _range,
          options: const [('30d', '30 days'), ('3m', '3 months'), ('1y', '1 year')],
          onChanged: (v) {
            final old = _data;
            setState(() {
              _range = v;
              _data = _load();
            });
            old.dispose();
          },
        ),
        children: [
          LoadView(
            loader: _data,
            builder:
                (a) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MetricGrid(
                      children: [
                        MetricCard(icon: 'chart', label: 'Sales', value: money(a['grossSales']), sub: '${numOf(a['orderCount']).toInt()} orders'),
                        MetricCard(icon: 'cart', label: 'Units sold', value: compact(a['unitsSold']), sub: 'Recorded order items'),
                        MetricCard(icon: 'users', label: 'Average order', value: money(a['averageOrderValue']), sub: 'Calculated from orders'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Section(
                      title: 'Top products',
                      children: [
                        if (asMaps(a['topProducts']).isEmpty) const Tiny('No sales in this period.'),
                        for (final p in asMaps(a['topProducts'])) RecordCard(title: strOf(p['name']), subtitle: '${numOf(p['units']).toInt()} units', amount: money(p['revenue'])),
                      ],
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

const _payoutMethods = {'MTN_MOMO': 'MTN MoMo', 'AIRTEL_MONEY': 'Airtel Money', 'BANK_TRANSFER': 'Bank transfer'};
const _payoutStatus = {'PENDING': 'Waiting for MVEC', 'PROCESSING': 'Being sent', 'PAID': 'Sent', 'REJECTED': 'Declined', 'FAILED': 'Failed'};

/// `/supplier/payments` — balance and payouts to mobile money or bank.
class SupplierPaymentsPage extends StatefulWidget {
  const SupplierPaymentsPage({super.key});

  @override
  State<SupplierPaymentsPage> createState() => _SupplierPaymentsPageState();
}

class _SupplierPaymentsPageState extends State<SupplierPaymentsPage> with _Polling {
  late final _data = Loader(() async {
    final r = await Future.wait([jget('/suppliers/me/finance/summary'), jlist('/suppliers/me/finance/payouts', 'payouts')]);
    return (summary: asMap((r[0] as Map)['summary']), payouts: r[1] as List<Map<String, dynamic>>);
  });

  @override
  void initState() {
    super.initState();
    startPolling(_data.reload);
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _request(num available) async {
    final ok = await showFormSheet<bool>(
      context,
      title: 'Request a payout',
      subtitle: 'MVEC sends it and you get a notification at each step. You can withdraw up to ${money(available)}.',
      fields: const [],
      fieldsFor:
          (v) => [
            FieldSpec('amount', 'Amount (RWF)', type: FieldType.number, required: true, hint: 'Up to ${available.floor()}'),
            FieldSpec('method', 'Send to', type: FieldType.select, options: [for (final e in _payoutMethods.entries) (e.key, e.value)]),
            FieldSpec(
              'destination',
              v['method'] == 'BANK_TRANSFER' ? 'Bank and account number' : 'Mobile money number',
              required: true,
              hint: v['method'] == 'BANK_TRANSFER' ? 'e.g. Bank of Kigali 000400012345' : '07…',
            ),
            const FieldSpec('note', 'Note for MVEC (optional)'),
          ],
      initial: {'method': 'MTN_MOMO', 'amount': '${available.floor()}'},
      submitLabel: 'Request payout',
      onSubmit: (v) async {
        final amount = num.tryParse('${v['amount']}');
        if (amount == null || amount != amount.roundToDouble() || amount < kSupplierPayoutMinimum) throw ApiException('The minimum payout is ${money(kSupplierPayoutMinimum)}.');
        if (amount > available) throw ApiException('You can withdraw up to ${money(available)}.');
        await jpost('/suppliers/me/finance/payouts', {...v, 'amount': amount.toInt()});
        return true;
      },
    );
    if (ok == true && mounted) {
      toast(context, 'Payout requested. MVEC sends it and you get a notification when it is on its way.');
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Payments',
      title: 'Payments',
      subtitle: 'Your balance, and payouts to mobile money or your bank.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (d) {
            final s = d.summary;
            final available = numOf(s['availablePayout']);
            final declined = d.payouts.where((p) => strOf(p['rejectionReason']).isNotEmpty).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(icon: 'wallet', label: 'Available to withdraw', value: money(available), sub: 'Released after vendors confirm receipt'),
                    MetricCard(icon: 'chart', label: 'Payouts in progress', value: money(s['pendingPayouts']), sub: 'Requested, not sent yet'),
                    MetricCard(icon: 'box', label: 'Released this period', value: money(s['releasedThisPeriod']), sub: 'Orders vendors confirmed'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'Request a payout',
                  subtitle: 'MVEC sends it and you get a notification at each step.',
                  children: [
                    if (available < kSupplierPayoutMinimum)
                      Tiny('You can request a payout once you have ${money(kSupplierPayoutMinimum)} available. Money becomes available when vendors confirm they received their orders.')
                    else
                      GradientButton(label: 'Request payout', onPressed: () => _request(available)),
                  ],
                ),
                Section(
                  title: 'Payout history',
                  children: [
                    if (d.payouts.isEmpty) const Tiny('No payouts yet.'),
                    for (final p in d.payouts)
                      RecordCard(
                        title: strOf(p['payoutNumber'], idOf(p)),
                        subtitle: '${_payoutMethods[p['method']] ?? p['method']} · ${p['destination'] ?? ''}',
                        lines: ['Requested ${formatDate(p['requestedAt'])}'],
                        amount: money(p['amount']),
                        status: StatusChip(
                          _payoutStatus[p['status']] ?? '${p['status']}',
                          tone:
                              p['status'] == 'PAID'
                                  ? StatusTone.good
                                  : ['REJECTED', 'FAILED'].contains(p['status'])
                                  ? StatusTone.bad
                                  : StatusTone.warn,
                        ),
                      ),
                    if (declined.isNotEmpty) Tiny('Declined: ${declined.map((p) => '${p['payoutNumber']}: ${p['rejectionReason']}').join(' · ')}'),
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

/// `/supplier/reports` (Premium) and `/supplier/transactions` — ledger records.
class SupplierLedgerPage extends StatefulWidget {
  const SupplierLedgerPage({super.key, this.reports = false});
  final bool reports;

  @override
  State<SupplierLedgerPage> createState() => _SupplierLedgerPageState();
}

class _SupplierLedgerPageState extends State<SupplierLedgerPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([
      jlist('/suppliers/me/finance/ledger', 'entries', {'limit': 100}),
      widget.reports ? jget('/suppliers/me/finance/summary') : Future.value(<String, dynamic>{}),
      widget.reports ? jget('/suppliers/me/finance/analytics', {'range': '30d'}) : Future.value(<String, dynamic>{}),
    ]);
    return (entries: r[0] as List<Map<String, dynamic>>, summary: asMap((r[1] as Map)['summary']), analytics: asMap((r[2] as Map)['analytics']));
  });
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = PortalPage(
      eyebrow: widget.reports ? 'Reports' : 'Supplier · transactions',
      title: widget.reports ? 'Reports' : 'Transactions',
      subtitle: widget.reports ? 'Reports generated from your financial and order records.' : 'Every supplier payment and settlement has an auditable record.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search records…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder:
              (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.reports) Tiny('30 day sales: ${money(d.analytics['grossSales'])} · Total recorded sales: ${money(d.summary['grossSales'])}'),
                  Paged<Map<String, dynamic>>(
                    items: d.entries.where((e) => matches(_q, [e['description'], e['kind']])).toList(),
                    perPage: 12,
                    empty: const EmptyState(icon: Icons.receipt_long_outlined, title: 'No records yet'),
                    itemBuilder: (e) => RecordCard(title: strOf(e['description']), subtitle: '${titleCase(e['kind'])} · ${formatDate(e['at'])}', amount: money(e['amount'])),
                  ),
                ],
              ),
        ),
      ],
    );
    return widget.reports ? PremiumGate(feature: 'advancedAnalytics', title: 'Advanced reports', base: '/supplier', child: page) : page;
  }
}

/// `/supplier/reviews` — what vendors say after wholesale orders.
class SupplierReviewsPage extends StatefulWidget {
  const SupplierReviewsPage({super.key});

  @override
  State<SupplierReviewsPage> createState() => _SupplierReviewsPageState();
}

class _SupplierReviewsPageState extends State<SupplierReviewsPage> {
  late final _data = Loader(() => jlist('/suppliers/me/reviews', 'reviews', {'limit': 100}));
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Supplier · reviews',
      title: 'Reviews',
      subtitle: 'Review supplier feedback and reliability indicators.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search reviews…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder:
              (rows) => Paged<Map<String, dynamic>>(
                items: rows.where((r) => matches(_q, [r['author'], r['orderNumber'], r['comment']])).toList(),
                empty: const EmptyState(icon: Icons.star_outline_rounded, title: 'No reviews yet'),
                itemBuilder:
                    (r) =>
                        RecordCard(title: strOf(r['author'], 'Vendor'), subtitle: 'Order ${r['orderNumber'] ?? '—'} · ${formatDate(r['createdAt'])}', lines: ['★ ${r['rating']}', strOf(r['comment'])]),
              ),
        ),
      ],
    );
  }
}

// ─── Team & settings ─────────────────────────────────────────────────────────

const _supplierRoles = [('OPERATIONS', 'Admin / Operations'), ('WAREHOUSE', 'Inventory Manager'), ('FULFILMENT', 'Fulfillment / Orders Manager'), ('VIEWER', 'Viewer')];

/// `/supplier/team` — supplier team members.
class SupplierTeamPage extends StatefulWidget {
  const SupplierTeamPage({super.key});

  @override
  State<SupplierTeamPage> createState() => _SupplierTeamPageState();
}

class _SupplierTeamPageState extends State<SupplierTeamPage> {
  late final _data = Loader(() => jlist('/suppliers/me/team', 'members'));

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? m) async {
    final editing = m != null;
    final ok = await showFormSheet<bool>(
      context,
      title: editing ? 'Edit team member' : 'Add team member',
      fields: [
        const FieldSpec('name', 'Full name', required: true),
        const FieldSpec('email', 'Email', type: FieldType.email),
        const FieldSpec('phone', 'Phone', type: FieldType.phone, required: true),
        FieldSpec('password', editing ? 'New password (optional)' : 'Password', type: FieldType.password, required: !editing),
        const FieldSpec('role', 'Role', type: FieldType.select, options: _supplierRoles),
        if (editing) const FieldSpec('status', 'Status', type: FieldType.select, options: [('ACTIVE', 'Active'), ('SUSPENDED', 'Suspended')]),
      ],
      initial: {
        'name': strOf(m?['name'] ?? m?['fullName']),
        'email': strOf(m?['email']),
        'phone': strOf(m?['phone']),
        'role': strOf(m?['role'], _supplierRoles.first.$1),
        'status': strOf(m?['status'], 'ACTIVE'),
      },
      submitLabel: editing ? 'Save' : 'Add member',
      onSubmit: (v) async {
        final payload = {'fullName': v['name'], 'phone': v['phone'], 'email': v['email'], if ('${v['password'] ?? ''}'.isNotEmpty) 'password': v['password'], 'role': v['role']};
        if (editing) {
          await jpatch('/suppliers/me/team/${idOf(m)}', {...payload, 'status': v['status']});
        } else {
          await jpost('/suppliers/me/team', payload);
        }
        return true;
      },
    );
    if (ok == true && mounted) {
      toast(context, editing ? 'Team member updated.' : 'Team member added.');
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Team / staff',
      title: 'Team & staff',
      subtitle: 'People who help run your supplier account.',
      onRefresh: _data.reload,
      action: GradientButton(label: 'Add team member', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null)),
      children: [
        LoadView(
          loader: _data,
          builder:
              (rows) => Column(
                children: [
                  if (rows.isEmpty) const EmptyState(icon: Icons.group_outlined, title: 'No team members yet'),
                  for (final m in rows)
                    RecordCard(
                      title: strOf(m['fullName'] ?? m['name']),
                      subtitle: '${_supplierRoles.where((r) => r.$1 == m['role']).map((r) => r.$2).firstOrNull ?? titleCase(m['role'])} · ${m['phone'] ?? ''}',
                      status: Pill(m['status']),
                      actions:
                          m['role'] == 'OWNER'
                              ? const []
                              : [
                                ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(m)),
                                ActionChipBtn(
                                  'Remove',
                                  danger: true,
                                  onPressed: () async {
                                    if (!await confirmDialog(context, 'Remove ${strOf(m['fullName'], 'this team member')}?', confirm: 'Remove', danger: true)) return;
                                    if (context.mounted && await runAction(context, () => jdelete('/suppliers/me/team/${idOf(m)}'), success: 'Team member removed.')) _data.reload();
                                  },
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

/// `/supplier/settings` — the supplier profile vendors see.
class SupplierSettingsPage extends ConsumerStatefulWidget {
  const SupplierSettingsPage({super.key});

  @override
  ConsumerState<SupplierSettingsPage> createState() => _SupplierSettingsPageState();
}

class _SupplierSettingsPageState extends ConsumerState<SupplierSettingsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([jget('/suppliers/me/profile'), jlist('/categories', 'categories').catchError((_) => <Map<String, dynamic>>[])]);
    final res = r[0] as Map<String, dynamic>;
    return (profile: res['supplier'] is Map ? asMap(res['supplier']) : res, categories: r[1] as List<Map<String, dynamic>>);
  });
  final _c = {
    for (final k in ['businessName', 'phone', 'email', 'location', 'description']) k: TextEditingController(),
  };
  String _category = '';
  String _logo = '';
  bool _filled = false;
  bool _saving = false;
  bool _uploading = false;
  Map<String, dynamic> _status = {};

  @override
  void dispose() {
    _data.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_c.values.any((c) => c.text.trim().isEmpty) || _category.isEmpty) {
      toast(context, 'Fill in every field so MVEC can verify you.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await jpatch('/suppliers/me/profile', {for (final e in _c.entries) e.key: e.value.text.trim(), 'category': _category, 'logoUrl': _logo});
      final sup = asMap(res['supplier']);
      setState(() => _status = {'verificationStatus': sup['verificationStatus'], 'verificationNote': sup['verificationNote']});
      if (mounted) toast(context, strOf(res['message'], 'Profile saved.'));
      ref.read(authProvider.notifier).refresh().ignore();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Settings',
      title: 'Supplier profile',
      subtitle: 'Vendors see this profile. Keep it complete so MVEC can verify you.',
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading profile…',
          builder: (d) {
            final p = d.profile;
            if (!_filled) {
              _filled = true;
              for (final k in ['businessName', 'phone', 'email', 'description']) {
                _c[k]!.text = strOf(p[k]);
              }
              final loc = p['location'];
              _c['location']!.text = loc is Map ? loc.values.where((x) => strOf(x).isNotEmpty).join(', ') : strOf(loc);
              _category = strOf(p['category']);
              _logo = strOf(p['logoUrl']);
              _status = {'verificationStatus': p['verificationStatus'], 'verificationNote': p['verificationNote']};
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_status['verificationStatus'] == 'REJECTED')
                  Notice(text: 'MVEC asked for changes: ${strOf(_status['verificationNote'], 'Check your details.')} Saving sends your profile back for review.'),
                DataCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ProductImage(src: _logo, size: 64, radius: 12),
                          const SizedBox(width: 12),
                          ActionChipBtn(
                            _logo.isEmpty ? 'Upload logo' : 'Change logo',
                            icon: Icons.upload_rounded,
                            busy: _uploading,
                            onPressed: () async {
                              setState(() => _uploading = true);
                              final url = await uploadOneImage(context);
                              if (mounted) {
                                setState(() {
                                  _uploading = false;
                                  if (url != null) _logo = url;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: _c['businessName'], decoration: const InputDecoration(labelText: 'Business name *')),
                      const SizedBox(height: 10),
                      FilterSelect(
                        label: 'What you supply *',
                        value: _category,
                        options: [
                          ('', 'Choose a category'),
                          for (final c in d.categories) (strOf(c['name']), strOf(c['name'])),
                          if (_category.isNotEmpty && !d.categories.any((c) => c['name'] == _category)) (_category, _category),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: _c['phone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone *')),
                      const SizedBox(height: 10),
                      TextField(controller: _c['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email *')),
                      const SizedBox(height: 10),
                      TextField(controller: _c['location'], decoration: const InputDecoration(labelText: 'Location (district, sector) *')),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _c['description'],
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(labelText: 'Description *', hintText: 'What you supply, minimum orders, delivery areas…'),
                      ),
                      const SizedBox(height: 12),
                      GradientButton(label: 'Save profile', loading: _saving, onPressed: _save),
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
