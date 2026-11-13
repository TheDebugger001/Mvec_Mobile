import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import '../seller/seller_common.dart' show categoryOptions;

const _ruleTypes = [('CATEGORY', 'Category rate'), ('VENDOR', 'Seller override'), ('GLOBAL', 'Default rate')];

String _typeLabel(String t, String scope) => t == 'VENDOR' && scope == 'WHOLESALE' ? 'Supplier override' : _ruleTypes.firstWhere((r) => r.$1 == t, orElse: () => (t, t)).$2;

/// `/admin/commission-rules` — Ikiguzi's commission per category and overrides.
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
            FieldSpec('rateValue', 'Ikiguzi commission (%)', type: FieldType.number, required: true, help: '0 to $maxRate%'),
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
          subtitle: "Ikiguzi's commission per category, with optional special rates for individual sellers (retail) or suppliers (wholesale). Changes apply to new orders; paid orders keep their rate.",
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
          options: const [('MVEC', 'Ikiguzi (out of the commission)'), ('SELLER', 'The seller (out of their share)')],
          onChanged: (v) => setState(() => _payer = v),
        ),
        const SizedBox(height: 10),
        TextField(controller: _affiliate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Affiliate share (% of the commission)'), onChanged: (_) => setState(() {})),
        Tiny(
          'Example, 100,000 RWF sale at the default rate: Ikiguzi commission ${money(example)} → affiliate ${money(example * numOf(_affiliate.text) / 100)} (only if the buyer came through an affiliate link), Ikiguzi keeps the rest${_payer == 'Ikiguzi' ? ' minus the payment provider fee' : ''}.',
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
          KV('Ikiguzi commission', money(d['totalPlatformFee'])),
          KV('  → Affiliate (paid by Ikiguzi)', money(d['platformAffiliateShare'])),
          KV('  → Ikiguzi keeps', money(numOf(d['adminShare']) + numOf(d['developerShare']))),
          KV('Payment provider fee', money(d['gatewayFee'])),
          Tiny('Provider fee paid by ${d['gatewayFeePayer'] == 'SELLER' ? 'the seller' : 'Ikiguzi'}.'),
        ],
      ],
    );
  }
}

// ─── Support inbox ──────────────────────────────────────────────────────────
