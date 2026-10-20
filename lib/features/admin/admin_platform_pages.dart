import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../portal/shared_pages.dart' show openTicketAsStaff, supportChip;
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import '../seller/seller_common.dart' show categoryOptions;

// Admin platform, money-out and growth pages (web: the rest of AdminOps.jsx,
// AdminTransfers, VendorPayoutsAdmin, AdvertisingAdmin, PlatformOperations,
// BecomeSeller).

// ─── Subscriptions ──────────────────────────────────────────────────────────

/// `/admin/subscriptions` — the dormant subscription program and plans.
class AdminSubscriptionsPage extends StatefulWidget {
  const AdminSubscriptionsPage({super.key});

  @override
  State<AdminSubscriptionsPage> createState() => _AdminSubscriptionsPageState();
}

class _AdminSubscriptionsPageState extends State<AdminSubscriptionsPage> {
  late final _program = Loader(() async {
    final r = await Future.wait([jget('/admin/operations-settings'), jget('/plans/me')]);
    return (settings: asMap(r[0]['settings']), info: r[1]);
  });
  late final _subs = Loader(() async {
    final r = await Future.wait([
      jlist('/admin/subscriptions', 'data', {'limit': 200}),
      jlist('/admin/buyer-subscriptions', 'data', {'limit': 200}),
    ]);
    return (vendors: r[0], buyers: r[1]);
  });
  final _c = {
    for (final k in ['sellerPremiumPrice', 'buyerPremiumPrice', 'freeProductLimit']) k: TextEditingController(),
  };
  bool _filled = false;
  bool _busy = false;

  @override
  void dispose() {
    _program.dispose();
    _subs.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> patch, [String? confirm]) async {
    if (confirm != null && !await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () => jput('/admin/operations-settings', patch));
    if (mounted) setState(() => _busy = false);
    if (ok) {
      _filled = false;
      _program.reload();
    }
  }

  Widget _plans(List<Map<String, dynamic>> rows) => Column(
    children: [
      if (rows.isEmpty) const Tiny('No subscriptions yet.'),
      for (final r in rows)
        RecordCard(
          title: strOf(r['holder']),
          subtitle: '${r['plan'] ?? ''} · ${r['billing'] ?? ''} · renews ${r['renewal'] ?? '—'}',
          amount: numOf(r['price']) > 0 ? money(r['price']) : 'Free',
          status: Pill(r['status'] == 'Active' ? 'ACTIVE' : r['status'], label: strOf(r['status'])),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Growth',
      title: 'Subscriptions',
      subtitle: 'Paid seller Premium and buyer ad-free plans. Plans renew and expire automatically.',
      onRefresh: () async {
        await Future.wait([_program.reload(), _subs.reload()]);
      },
      children: [
        LoadView(
          loader: _program,
          loadingLabel: 'Loading the subscription program…',
          builder: (d) {
            final s = d.settings;
            final on = s['subscriptionsEnabled'] == true;
            if (!_filled) {
              _filled = true;
              for (final k in _c.keys) {
                _c[k]!.text = '${numOf(s[k]).toInt()}';
              }
            }
            final free = [for (final x in (d.info['freeIncludes'] is List ? d.info['freeIncludes'] as List : const [])) '$x'];
            final premium = [for (final x in asMap(d.info['premiumFeatures']).values) '$x'];
            return Section(
              title: 'Subscription program',
              subtitle:
                  on
                      ? 'On: sellers and suppliers on Free have the Free limits; Premium is paid monthly from their balance.'
                      : 'Off: nobody is charged and every seller and supplier has every tool for free.',
              trailing: StatusChip(on ? 'On' : 'Off', tone: on ? StatusTone.good : StatusTone.warn),
              children: [
                DataCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Free Seller · RWF 0', style: TextStyle(fontWeight: FontWeight.w800)),
                      const Tiny('For new and small sellers and suppliers'),
                      for (final x in free) Tiny('• $x${x.startsWith('List products') ? ' (${_c['freeProductLimit']!.text})' : ''}'),
                    ],
                  ),
                ),
                DataCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Seller Premium · ${money(_c['sellerPremiumPrice']!.text)}/month (recommended)', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Tiny("Paid from the seller's available balance"),
                      for (final x in premium) Tiny('• $x'),
                    ],
                  ),
                ),
                TextField(
                  controller: _c['sellerPremiumPrice'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seller Premium (RWF / month)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(controller: _c['buyerPremiumPrice'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Buyer ad-free (RWF / month)')),
                const SizedBox(height: 10),
                TextField(
                  controller: _c['freeProductLimit'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Free listing limit (products)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                OutlineBtn(label: 'Save prices and limit', loading: _busy, onPressed: () => _save({for (final e in _c.entries) e.key: numOf(e.value.text)})),
                const SizedBox(height: 8),
                on
                    ? OutlineBtn(
                      label: 'Switch program off',
                      onPressed:
                          _busy
                              ? null
                              : () => _save({
                                'subscriptionsEnabled': false,
                              }, 'Switch the subscription program off? Everyone gets every tool for free again and no renewals are charged. Active Premium plans keep their paid time.'),
                    )
                    : GradientButton(
                      label: 'Switch program on',
                      onPressed:
                          _busy
                              ? null
                              : () => _save(
                                {'subscriptionsEnabled': true},
                                'Switch the subscription program on? Free sellers and suppliers become limited to ${_c['freeProductLimit']!.text} products and Premium tools need a ${money(_c['sellerPremiumPrice']!.text)}/month plan. Tell your sellers before doing this.',
                              ),
                    ),
              ],
            );
          },
        ),
        LoadView(
          loader: _subs,
          loadingLabel: 'Loading subscriptions…',
          builder: (d) {
            bool paid(Map<String, dynamic> s) => s['planKey'] == 'PREMIUM' && s['status'] == 'Active';
            final monthly = [...d.vendors, ...d.buyers].where(paid).fold<num>(0, (sum, s) => sum + (s['billing'] == 'Yearly' ? numOf(s['price']) / 12 : numOf(s['price'])));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(icon: 'shop', label: 'Sellers on Premium', value: '${d.vendors.where(paid).length}'),
                    MetricCard(icon: 'users', label: 'Buyers ad-free', value: '${d.buyers.where(paid).length}'),
                    MetricCard(icon: 'wallet', label: 'Monthly value', value: money(monthly), sub: 'Active paid plans (yearly ÷ 12)'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(title: 'Sellers', subtitle: '${d.vendors.length} subscriptions', children: [_plans(d.vendors)]),
                Section(title: 'Buyers', subtitle: '${d.buyers.length} subscriptions', children: [_plans(d.buyers)]),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Platform settings ──────────────────────────────────────────────────────

/// `/admin/settings` — fees, rules, auto-release, providers and jobs.
class AdminPlatformPage extends StatefulWidget {
  const AdminPlatformPage({super.key});

  @override
  State<AdminPlatformPage> createState() => _AdminPlatformPageState();
}

class _AdminPlatformPageState extends State<AdminPlatformPage> {
  late final _data = Loader(() => jget('/admin/platform'));
  late final _ops = Loader(() async => asMap((await jget('/admin/operations-settings'))['settings']));
  final _days = TextEditingController();
  final _reply = TextEditingController();
  bool _filled = false;
  bool _busy = false;

  @override
  void dispose() {
    _data.dispose();
    _ops.dispose();
    _days.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_days.text.isEmpty || _reply.text.isEmpty) return;
    setState(() => _busy = true);
    final days = numOf(_days.text), reply = numOf(_reply.text);
    final ok = await runAction(
      context,
      () => jput('/admin/operations-settings', {'autoReleaseDays': days, 'disputeResponseDays': reply}),
      success:
          'Saved. ${days > 0 ? 'Sellers are paid automatically ${_days.text} day${days == 1 ? '' : 's'} after shipping if no problem is reported.' : 'Automatic release is off.'} Sellers have ${_reply.text} day${reply == 1 ? '' : 's'} to answer a problem report before MVEC steps in.',
    );
    if (mounted) setState(() => _busy = false);
    if (ok) _data.reload();
  }

  Widget _line(String label, String value, [String? detail]) => RecordCard(title: label, subtitle: detail, amount: value);

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Platform',
      title: 'Platform settings',
      subtitle: 'How MVEC is set up right now, read live from the server.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading settings…',
          builder:
              (d) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Section(title: 'Fees', children: [for (final f in asMaps(d['fees'])) _line(strOf(f['label']), strOf(f['value']), strOf(f['detail']))]),
                  Section(title: 'Rules', children: [for (final f in asMaps(d['rules'])) _line(strOf(f['label']), strOf(f['value']))]),
                  ListenableBuilder(
                    listenable: _ops,
                    builder: (context, _) {
                      final s = _ops.data;
                      if (s != null && !_filled) {
                        _filled = true;
                        _days.text = '${s['autoReleaseDays']}';
                        _reply.text = '${s['disputeResponseDays'] ?? 3}';
                      }
                      return Section(
                        title: 'Paying sellers and problem reports',
                        children: [
                          const Tiny(
                            'If a buyer neither gives the delivery code nor reports a problem, the seller is paid automatically this many days after the order ships. Buyers are told when their order ships. A reported problem freezes the payment. Pickup orders wait for collection. 0 turns it off.',
                          ),
                          if (s == null && _ops.error == null) const LoadingState(),
                          if (_ops.error != null) Notice(text: errorText(_ops.error!)),
                          if (s != null) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _days,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Pay sellers this many days after shipping', helperText: '0 to 30'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _reply,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Days a seller has to answer a problem report', helperText: '1 to 14'),
                            ),
                            const SizedBox(height: 10),
                            GradientButton(label: 'Save', loading: _busy, onPressed: _save),
                          ],
                        ],
                      );
                    },
                  ),
                  Section(
                    title: 'Payment providers & messages',
                    subtitle: "“Test mode” means payments succeed without real money. Add the keys to the server's .env to go live.",
                    children: [for (final i in asMaps(d['integrations'])) RecordCard(title: strOf(i['label']), subtitle: strOf(i['env']), status: Pill(i['status'], label: strOf(i['status'])))],
                  ),
                  Section(
                    title: 'Automatic jobs',
                    subtitle: 'Environment: ${d['environment'] ?? ''}',
                    children: [for (final j in asMaps(d['jobs'])) _line(strOf(j['label']), strOf(j['schedule']), strOf(j['detail']))],
                  ),
                  InfoBox(
                    title: 'Change rates and shares',
                    text: 'Commission per category, seller overrides, the affiliate share and who pays provider fees are all set on the Commission rules page.',
                    child: GradientButton(label: 'Open commission rules', compact: true, onPressed: () => context.go('/admin/commission-rules')),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

// ─── Audit log ──────────────────────────────────────────────────────────────

/// `/admin/audit-logs` — every admin change.
class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  final _q = TextEditingController();
  String _query = '';
  String _type = '';
  int _page = 1;
  late Loader<Map<String, dynamic>> _data = _load();

  Loader<Map<String, dynamic>> _load() => Loader(() => jget('/admin/audit-logs', {'page': _page, 'pageSize': 30, 'q': _query, 'targetType': _type}));

  void _reload(VoidCallback change) {
    final old = _data;
    setState(() {
      change();
      _data = _load();
    });
    old.dispose();
  }

  @override
  void dispose() {
    _data.dispose();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Platform',
      title: 'Audit log',
      subtitle: 'Every change an administrator makes is recorded here automatically: who, what and when. Entries cannot be edited or deleted.',
      onRefresh: _data.reload,
      children: [
        TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(labelText: 'Search action or admin', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          onSubmitted:
              (v) => _reload(() {
                _page = 1;
                _query = v.trim();
              }),
        ),
        const SizedBox(height: 10),
        LoadView(
          loader: _data,
          loadingLabel: 'Loading the audit log…',
          builder: (d) {
            final types = [for (final t in (d['targetTypes'] is List ? d['targetTypes'] as List : const [])) '$t'];
            final rows = asMaps(d['data']);
            final total = numOf(asMap(d['meta'])['total']).toInt();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilterSelect(
                  label: 'About',
                  value: _type,
                  options: [('', 'Everything'), for (final t in types) (t, t)],
                  onChanged:
                      (v) => _reload(() {
                        _type = v;
                        _page = 1;
                      }),
                ),
                const SizedBox(height: 10),
                Tiny('$total recorded'),
                if (rows.isEmpty) const EmptyState(icon: Icons.history_rounded, title: 'No admin actions recorded yet.'),
                for (final r in rows)
                  RecordCard(
                    title: strOf(r['action']),
                    subtitle: '${r['actor'] ?? ''} · ${formatDateTime(r['at'])}',
                    lines: [if (strOf(asMap(r['detail'])['reason']).isNotEmpty) '“${asMap(r['detail'])['reason']}”', 'About: ${strOf(r['targetType'], '—')}'],
                  ),
                if (total > 30) PaginationBar(page: _page, total: total, perPage: 30, onPage: (p) => _reload(() => _page = p)),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Commission rules ───────────────────────────────────────────────────────

const _ruleTypes = [('CATEGORY', 'Category rate'), ('VENDOR', 'Seller override'), ('GLOBAL', 'Default rate')];
String _typeLabel(String t, String scope) => t == 'VENDOR' && scope == 'WHOLESALE' ? 'Supplier override' : _ruleTypes.firstWhere((r) => r.$1 == t, orElse: () => (t, t)).$2;

/// `/admin/commission-rules` — MVEC's commission per category and overrides.
class AdminCommissionRulesPage extends StatefulWidget {
  const AdminCommissionRulesPage({super.key});

  @override
  State<AdminCommissionRulesPage> createState() => _AdminCommissionRulesPageState();
}

class _AdminCommissionRulesPageState extends State<AdminCommissionRulesPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([
      jget('/admin/commissions'),
      jlist('/admin/vendors', 'data', {'pageSize': 100}).catchError((_) => <Map<String, dynamic>>[]),
      jlist('/admin/suppliers', 'data', {'pageSize': 100, 'verificationStatus': 'VERIFIED'}).catchError((_) => <Map<String, dynamic>>[]),
      jlist('/categories', 'categories').catchError((_) => <Map<String, dynamic>>[]),
    ]);
    List<(String, String)> parties(List<Map<String, dynamic>> l) => [
      for (final v in l)
        if (idOf(v['user']).isNotEmpty || strOf(v['user']).isNotEmpty) (idOf(v['user']).isNotEmpty ? idOf(v['user']) : strOf(v['user']), strOf(v['businessName'])),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return (
      main: r[0] as Map<String, dynamic>,
      sellers: parties(r[1] as List<Map<String, dynamic>>),
      suppliers: parties(r[2] as List<Map<String, dynamic>>),
      categories: r[3] as List<Map<String, dynamic>>,
    );
  });
  String _scope = 'RETAIL';
  String _tab = 'CATEGORY';
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(
    Map<String, dynamic>? rule,
    ({Map<String, dynamic> main, List<(String, String)> sellers, List<(String, String)> suppliers, List<Map<String, dynamic>> categories}) d, {
    String? type,
  }) async {
    final scope = strOf(rule?['scope'], _scope);
    final parties = scope == 'WHOLESALE' ? d.suppliers : d.sellers;
    final maxRate = numOf(d.main['maxRate'], 50);
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: '${rule == null ? 'New' : 'Edit'} ${scope == 'WHOLESALE' ? 'wholesale' : 'retail'} rule',
      fields: const [],
      fieldsFor:
          (v) => [
            FieldSpec('ruleType', 'Applies to', type: FieldType.select, options: [for (final t in _ruleTypes) (t.$1, _typeLabel(t.$1, scope))]),
            if (v['ruleType'] == 'VENDOR')
              FieldSpec('targetVendor', scope == 'WHOLESALE' ? 'Supplier' : 'Seller', type: FieldType.select, required: true, placeholderOption: 'Choose one', options: parties),
            if (v['ruleType'] != 'GLOBAL')
              FieldSpec(
                'targetCategory',
                v['ruleType'] == 'VENDOR' ? 'Only in this category (optional)' : 'Category',
                type: FieldType.select,
                required: v['ruleType'] == 'CATEGORY',
                placeholderOption: v['ruleType'] == 'VENDOR' ? 'All categories' : 'Choose a category',
                options: categoryOptions(d.categories),
              ),
            FieldSpec('rateValue', 'MVEC commission (%)', type: FieldType.number, required: true, help: '0 to $maxRate%'),
            const FieldSpec(
              'priority',
              'Priority',
              type: FieldType.number,
              help:
                  'Most specific wins: a seller override for a category, then a seller override, then the category rate, then the default. When two rules are equally specific, the higher priority wins.',
            ),
            const FieldSpec('name', 'Name (optional)', hint: 'e.g. Phones launch rate'),
            const FieldSpec('isActive', 'Active', type: FieldType.toggle, help: 'Inactive rules are kept but not used.'),
          ],
      initial: {
        'ruleType': strOf(rule?['ruleType'], type ?? 'CATEGORY'),
        'targetVendor': idOf(rule?['targetVendor']),
        'targetCategory': idOf(rule?['targetCategory']),
        'rateValue': '${rule?['rateValue'] ?? 5}',
        'priority': '${rule?['priority'] ?? 0}',
        'name': strOf(rule?['name']),
        'isActive': rule?['isActive'] != false,
      },
      submitLabel: 'Save rule',
      onSubmit: (v) {
        final rate = numOf(v['rateValue']);
        if (rate < 0 || rate > maxRate) throw ApiException('Choose a commission between 0% and $maxRate%.');
        final payload = {
          'ruleType': v['ruleType'],
          'scope': scope,
          'rateValue': rate,
          'priority': numOf(v['priority']).toInt(),
          'name': v['name'],
          'targetCategory': '${v['targetCategory'] ?? ''}'.isEmpty || v['ruleType'] == 'GLOBAL' ? null : v['targetCategory'],
          'targetVendor': '${v['targetVendor'] ?? ''}'.isEmpty || v['ruleType'] != 'VENDOR' ? null : v['targetVendor'],
          'isActive': v['isActive'] != false,
        };
        return rule == null ? jpost('/admin/commissions', payload) : jput('/admin/commissions/${idOf(rule)}', payload);
      },
    );
    if (res != null && mounted) {
      toast(context, strOf(res['message'], 'Rule saved.'));
      _data.reload();
    }
  }

  Future<void> _act(String id, Future<dynamic> Function() fn, String ok) async {
    setState(() => _busy = id);
    final done = await runAction(context, fn, success: ok);
    if (mounted) setState(() => _busy = '');
    if (done) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      loadingLabel: 'Loading commission rules…',
      builder: (d) {
        final rules = asMaps(d.main['rules']);
        final settings = asMap(d.main['settings']);
        final inScope = rules.where((r) => strOf(r['scope'], 'RETAIL') == _scope).toList();
        final shown = inScope.where((r) => r['ruleType'] == _tab).toList();
        return PortalPage(
          eyebrow: 'Money',
          title: 'Commission rules',
          subtitle: "MVEC's commission per category, with optional special rates for individual sellers (retail) or suppliers (wholesale). Changes apply to new orders; paid orders keep their rate.",
          onRefresh: _data.reload,
          action: GradientButton(label: 'New rule', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null, d, type: _tab)),
          children: [
            TabChips(
              tabs: const [('RETAIL', 'Retail: buyers ← sellers'), ('WHOLESALE', 'Wholesale: vendors ← suppliers')],
              value: _scope,
              onChanged:
                  (v) => setState(() {
                    _scope = v;
                    _tab = 'CATEGORY';
                  }),
            ),
            _CommissionSettings(settings: settings, onSaved: _data.reload),
            TabChips(
              tabs: [for (final t in _ruleTypes) (t.$1, _typeLabel(t.$1, _scope))],
              value: _tab,
              counts: {for (final t in _ruleTypes) t.$1: inScope.where((r) => r['ruleType'] == t.$1 && r['isActive'] == true).length},
              onChanged: (v) => setState(() => _tab = v),
            ),
            if (shown.isEmpty)
              EmptyState(
                icon: Icons.percent_rounded,
                title: 'No ${_typeLabel(_tab, _scope).toLowerCase()}s yet',
                message:
                    _tab == 'GLOBAL'
                        ? 'Without a default rule, ${_scope == 'WHOLESALE' ? 'wholesale orders' : 'sales'} use the ${_scope == 'WHOLESALE' ? settings['defaultWholesaleCommissionPercent'] ?? 0 : settings['defaultCommissionPercent']}% default above.'
                        : _tab == 'CATEGORY'
                        ? 'Every category uses the default until you set a rate.'
                        : '${_scope == 'WHOLESALE' ? 'Suppliers' : 'Sellers'} pay their category rates unless you give them an override.',
                action: OutlineBtn(label: 'Add one', compact: true, onPressed: () => _edit(null, d, type: _tab)),
              ),
            for (final r in shown)
              RecordCard(
                title:
                    r['ruleType'] == 'VENDOR'
                        ? '${r['sellerName'] ?? ''}${strOf(r['categoryName']).isNotEmpty ? ' · ${r['categoryName']}' : ' · all categories'}'
                        : r['ruleType'] == 'CATEGORY'
                        ? strOf(r['categoryName'])
                        : 'All sales',
                subtitle: '${strOf(r['name'])} · priority ${r['priority'] ?? 0}',
                amount: '${numOf(r['rateValue'])}%',
                status: StatusChip(r['isActive'] == true ? 'Active' : 'Off', tone: r['isActive'] == true ? StatusTone.good : StatusTone.neutral),
                actions: [
                  ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(r, d)),
                  ActionChipBtn(
                    r['isActive'] == true ? 'Switch off' : 'Switch on',
                    busy: _busy == idOf(r),
                    onPressed:
                        () => _act(
                          idOf(r),
                          () => jpatch('/admin/commissions/${idOf(r)}/toggle', {'isActive': r['isActive'] != true}),
                          r['isActive'] == true ? 'Rule switched off.' : 'Rule switched on.',
                        ),
                  ),
                  ActionChipBtn(
                    'Delete',
                    danger: true,
                    busy: _busy == idOf(r),
                    onPressed: () async {
                      if (!await confirmDialog(context, 'Delete this rule? Paid orders are not affected.', confirm: 'Delete', danger: true)) return;
                      if (context.mounted) await _act(idOf(r), () => jdelete('/admin/commissions/${idOf(r)}'), 'Rule deleted.');
                    },
                  ),
                ],
              ),
            const SizedBox(height: 10),
            _SplitPreview(key: ValueKey(_scope), scope: _scope, parties: _scope == 'WHOLESALE' ? d.suppliers : d.sellers, categories: d.categories),
          ],
        );
      },
    );
  }
}

class _CommissionSettings extends StatefulWidget {
  const _CommissionSettings({required this.settings, required this.onSaved});
  final Map<String, dynamic> settings;
  final VoidCallback onSaved;

  @override
  State<_CommissionSettings> createState() => _CommissionSettingsState();
}

class _CommissionSettingsState extends State<_CommissionSettings> {
  late final _retail = TextEditingController(text: '${numOf(widget.settings['defaultCommissionPercent'])}');
  late final _wholesale = TextEditingController(text: '${numOf(widget.settings['defaultWholesaleCommissionPercent'])}');
  late final _affiliate = TextEditingController(text: '${numOf(widget.settings['affiliateSharePercent'])}');
  late String _payer = strOf(widget.settings['gatewayFeePayer'], 'MVEC');
  bool _busy = false;

  @override
  void dispose() {
    _retail.dispose();
    _wholesale.dispose();
    _affiliate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => jput('/admin/commission-settings', {
        ...widget.settings,
        'defaultCommissionPercent': numOf(_retail.text),
        'defaultWholesaleCommissionPercent': numOf(_wholesale.text),
        'developerSharePercent': 0,
        'affiliateSharePercent': numOf(_affiliate.text),
        'gatewayFeePayer': _payer,
      }),
    );
    if (mounted) setState(() => _busy = false);
    if (ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final example = 100000 * numOf(_retail.text) / 100;
    return Section(
      title: 'How the commission is shared',
      subtitle: 'Applies to orders paid from now on. Paid orders keep the split they had.',
      children: [
        TextField(
          controller: _retail,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Default retail commission (%)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(controller: _wholesale, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Default wholesale commission (%)')),
        const SizedBox(height: 10),
        FilterSelect(
          label: 'Payment provider fees paid by',
          value: _payer,
          options: const [('MVEC', 'MVEC (out of the commission)'), ('SELLER', 'The seller (out of their share)')],
          onChanged: (v) => setState(() => _payer = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: _affiliate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Affiliate share (% of the commission)'), onChanged: (_) => setState(() {})),
        Tiny(
          'Example, 100,000 RWF sale at the default rate: MVEC commission ${money(example)} → affiliate ${money(example * numOf(_affiliate.text) / 100)} (only if the buyer came through an affiliate link), MVEC keeps the rest${_payer == 'MVEC' ? ' minus the payment provider fee' : ''}.',
        ),
        const SizedBox(height: 8),
        GradientButton(label: 'Save settings', loading: _busy, onPressed: _save),
      ],
    );
  }
}

class _SplitPreview extends StatefulWidget {
  const _SplitPreview({super.key, required this.scope, required this.parties, required this.categories});
  final String scope;
  final List<(String, String)> parties;
  final List<Map<String, dynamic>> categories;

  @override
  State<_SplitPreview> createState() => _SplitPreviewState();
}

class _SplitPreviewState extends State<_SplitPreview> {
  String _vendor = '';
  String _category = '';
  final _amount = TextEditingController(text: '100000');
  final _fee = TextEditingController(text: '0');
  bool _affiliate = false;
  Map<String, dynamic>? _result;
  String _error = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amount.dispose();
    _fee.dispose();
    super.dispose();
  }

  void _run() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await jget('/admin/commissions/preview', {
          'vendorId': _vendor,
          'categoryId': _category,
          'amount': numOf(_amount.text),
          'gatewayFee': numOf(_fee.text),
          'affiliate': _affiliate && widget.scope == 'RETAIL' ? 1 : 0,
          'scope': widget.scope,
        });
        if (mounted) {
          setState(() {
            _result = r;
            _error = '';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _error = errorText(e));
          toast(context, errorText(e), error: true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _result;
    return Section(
      title: 'Try a sale',
      subtitle: 'See exactly how a sale would be split under the current rules.',
      children: [
        FilterSelect(
          label: widget.scope == 'WHOLESALE' ? 'Supplier' : 'Seller',
          value: _vendor,
          options: [('', widget.scope == 'WHOLESALE' ? 'Any supplier' : 'Any seller'), ...widget.parties],
          onChanged: (v) {
            setState(() => _vendor = v);
            _run();
          },
        ),
        const SizedBox(height: 10),
        FilterSelect(
          label: 'Category',
          value: _category,
          options: [('', 'Any category'), ...categoryOptions(widget.categories)],
          onChanged: (v) {
            setState(() => _category = v);
            _run();
          },
        ),
        const SizedBox(height: 10),
        TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sale amount (RWF)'), onChanged: (_) => _run()),
        const SizedBox(height: 10),
        TextField(controller: _fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Payment provider fee (RWF)'), onChanged: (_) => _run()),
        if (widget.scope == 'RETAIL')
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _affiliate,
            title: const Text('The buyer came through an affiliate link'),
            onChanged: (v) {
              setState(() => _affiliate = v == true);
              _run();
            },
          ),
        if (_error.isNotEmpty) Notice(text: _error),
        if (d != null) ...[
          Text(
            '${d['commissionPercent']}% commission · ${d['source'] ?? ''}${asMap(d['rule'])['name'] != null ? ' (“${asMap(d['rule'])['name']}”)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          KV(widget.scope == 'WHOLESALE' ? 'Supplier receives' : 'Seller receives', money(d['vendorNet'])),
          KV('MVEC commission', money(d['totalPlatformFee'])),
          KV('  → Affiliate (paid by MVEC)', money(d['platformAffiliateShare'])),
          KV('  → MVEC keeps', money(numOf(d['adminShare']) + numOf(d['developerShare']))),
          KV('Payment provider fee', money(d['gatewayFee'])),
          Tiny('Provider fee paid by ${d['gatewayFeePayer'] == 'SELLER' ? 'the seller' : 'MVEC'}.'),
        ],
      ],
    );
  }
}

// ─── Support inbox ──────────────────────────────────────────────────────────

const _supportRole = {'buyer': 'Buyer', 'vendor': 'Seller', 'supplier': 'Supplier', 'affiliate': 'Affiliate', 'delivery': 'Courier'};

/// `/admin/support` — requests from every kind of account.
class AdminSupportInboxPage extends StatefulWidget {
  const AdminSupportInboxPage({super.key, this.openCase});
  final String? openCase;

  @override
  State<AdminSupportInboxPage> createState() => _AdminSupportInboxPageState();
}

class _AdminSupportInboxPageState extends State<AdminSupportInboxPage> {
  late final _data = Loader(() => jlist('/support/cases', 'cases', {'pageSize': 100}));
  String _tab = 'ACTIVE';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _data.reload());
    final id = widget.openCase;
    if (id != null && id.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => openTicketAsStaff(context, id, onChanged: _data.reload));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  bool _active(Map<String, dynamic> c) => ['OPEN', 'IN_PROGRESS'].contains(c['status']);

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Communication',
      title: 'Support inbox',
      subtitle: 'Requests from buyers, sellers, suppliers, affiliates and couriers. Reply here; they are notified every time.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          loadingLabel: 'Loading requests…',
          builder: (cases) {
            final shown =
                cases.where((c) => _tab == 'ACTIVE' ? _active(c) : c['status'] == _tab).toList()..sort((a, b) {
                  final u = (b['priority'] == 'URGENT' ? 1 : 0) - (a['priority'] == 'URGENT' ? 1 : 0);
                  return u != 0 ? u : (parseDate(b['updatedAt']) ?? DateTime(2000)).compareTo(parseDate(a['updatedAt']) ?? DateTime(2000));
                });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabChips(
                  tabs: const [('ACTIVE', 'Needs an answer'), ('RESOLVED', 'Resolved'), ('CLOSED', 'Closed')],
                  value: _tab,
                  counts: {'ACTIVE': cases.where(_active).length, 'RESOLVED': cases.where((c) => c['status'] == 'RESOLVED').length, 'CLOSED': cases.where((c) => c['status'] == 'CLOSED').length},
                  onChanged: (v) => setState(() => _tab = v),
                ),
                if (shown.isEmpty)
                  EmptyState(
                    icon: Icons.inbox_outlined,
                    title: _tab == 'ACTIVE' ? 'Inbox zero' : 'Nothing here',
                    message: _tab == 'ACTIVE' ? 'New requests appear here and in your notifications.' : null,
                  ),
                for (final c in shown)
                  Builder(
                    builder: (_) {
                      final by = asMap(c['openedBy']);
                      final replies = c['comments'] is List ? (c['comments'] as List).length : 0;
                      return RecordCard(
                        title: strOf(c['subject']),
                        subtitle: '${personName(by, '')} · ${_supportRole[by['role']] ?? by['role'] ?? ''} · ${titleCase(c['category'])} · ${c['ticketNumber'] ?? ''}',
                        lines: ['$replies repl${replies == 1 ? 'y' : 'ies'} · updated ${formatDateTime(c['updatedAt'])}'],
                        badges: [if (c['priority'] == 'URGENT' || c['priority'] == 'HIGH') StatusChip(titleCase(c['priority']), tone: c['priority'] == 'URGENT' ? StatusTone.bad : StatusTone.warn)],
                        status: supportChip(c['status']),
                        onTap: () => openTicketAsStaff(context, idOf(c), onChanged: _data.reload),
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

// ─── Refunds & withdrawals ──────────────────────────────────────────────────

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
      () => jpost('/affiliates/payouts/${idOf(p)}/process', {'status': status, if (ref != null) 'transactionReference': ref.trim(), if (status == 'REJECTED') 'rejectionReason': 'Rejected by MVEC'}),
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

/// `/admin/affiliates` — affiliate accounts with block / unblock.
class AdminAffiliatesPage extends StatefulWidget {
  const AdminAffiliatesPage({super.key});

  @override
  State<AdminAffiliatesPage> createState() => _AdminAffiliatesPageState();
}

class _AdminAffiliatesPageState extends State<AdminAffiliatesPage> {
  late final _data = Loader(() => jlist('/affiliates', 'data'));
  String _busy = '';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'MVEC operations',
      title: 'Affiliates',
      subtitle: 'Manage affiliates using live marketplace account records.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search affiliates…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          loadingLabel: 'Loading affiliates…',
          builder: (rows) {
            final shown = rows.where((a) => matches(_q, [a['name'], a['Fullname'], a['email']])).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tiny('${rows.length} record${rows.length == 1 ? '' : 's'}'),
                if (shown.isEmpty) const EmptyState(icon: Icons.group_outlined, title: 'No affiliates here'),
                for (final a in shown)
                  Builder(
                    builder: (_) {
                      final status = strOf(a['status'], 'ACTIVE');
                      final blocked = status == 'BLOCK';
                      return RecordCard(
                        title: strOf(a['name'] ?? a['Fullname']),
                        subtitle: strOf(a['email']),
                        lines: ['${compact(a['clicks'])} clicks · ${numOf(a['conversions']).toInt()} conversions'],
                        amount: money(a['earnings']),
                        status: StatusChip(titleCase(status), tone: blocked ? StatusTone.bad : StatusTone.good),
                        actions: [
                          ActionChipBtn(
                            blocked ? 'Unblock' : 'Block',
                            danger: !blocked,
                            busy: _busy == idOf(a),
                            onPressed: () async {
                              if (!blocked && !await confirmDialog(context, 'Block ${strOf(a['name'] ?? a['Fullname'])}? They will not be able to log in.', confirm: 'Block', danger: true)) return;
                              if (!context.mounted) return;
                              setState(() => _busy = idOf(a));
                              final ok = await runAction(context, () => jpatch('/users/${idOf(a)}', {'status': blocked ? 'ACTIVE' : 'BLOCK'}), success: blocked ? 'Unblocked.' : 'Blocked.');
                              if (mounted) setState(() => _busy = '');
                              if (ok) _data.reload();
                            },
                          ),
                        ],
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

// ─── Become a seller ────────────────────────────────────────────────────────

/// `/admin/become-seller` — open a storefront while staying admin.
class AdminBecomeSellerPage extends ConsumerStatefulWidget {
  const AdminBecomeSellerPage({super.key});

  @override
  ConsumerState<AdminBecomeSellerPage> createState() => _AdminBecomeSellerPageState();
}

class _AdminBecomeSellerPageState extends ConsumerState<AdminBecomeSellerPage> {
  late final _user = ref.read(authProvider).user;
  late final _c = {
    'businessName': TextEditingController(),
    'phone': TextEditingController(text: _user?.telephone ?? ''),
    'email': TextEditingController(text: _user?.email ?? ''),
    'description': TextEditingController(),
  };
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await jpost('/vendors/become-seller', {for (final e in _c.entries) e.key: e.value.text.trim()});
      await ref.read(authProvider.notifier).refresh();
      if (mounted) context.go('/vendor');
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
    final already = ref.watch(authProvider.select((a) => a.user?.isSellerEnabled ?? false));
    return PortalPage(
      eyebrow: 'Seller mode',
      title: 'Become a Seller',
      subtitle: 'Open your own vendor storefront on MVEC while keeping full Super Administrator access. Your admin role and permissions never change.',
      children: [
        if (already)
          InfoBox(
            title: "You're already selling on MVEC",
            text: 'Your vendor storefront is active. Jump into your seller dashboard to manage products, orders and payouts.',
            child: GradientButton(label: 'Go to my Seller Dashboard', icon: Icons.grid_view_rounded, compact: true, onPressed: () => context.go('/vendor')),
          )
        else
          DataCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error.isNotEmpty) Notice(text: _error),
                TextField(controller: _c['businessName'], decoration: const InputDecoration(labelText: 'Business / store name', hintText: 'e.g. MVEC Official Store')),
                const SizedBox(height: 10),
                TextField(controller: _c['phone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Business phone', hintText: '0788123456')),
                const SizedBox(height: 10),
                TextField(controller: _c['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Business email', hintText: 'store@example.com')),
                const SizedBox(height: 10),
                TextField(
                  controller: _c['description'],
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Short description (optional)', hintText: 'What will you sell on MVEC?'),
                ),
                const SizedBox(height: 12),
                GradientButton(label: 'Activate Seller Mode', loading: _busy, onPressed: _submit),
              ],
            ),
          ),
      ],
    );
  }
}
