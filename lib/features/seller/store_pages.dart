import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/locations.dart';
import '../../core/nav_items.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';

// ─── Stores ──────────────────────────────────────────────────────────────────

/// `/vendor/stores` — several storefronts under one seller account.
class SellerStoresPage extends StatefulWidget {
  const SellerStoresPage({super.key});

  @override
  State<SellerStoresPage> createState() => _SellerStoresPageState();
}

class _SellerStoresPageState extends State<SellerStoresPage> {
  late final _data = Loader(() => jget('/stores/mine'));
  List<Map<String, dynamic>> _categories = [];
  String _busy = '';

  @override
  void initState() {
    super.initState();
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? s) async {
    final saved = await showFormSheet<Map<String, dynamic>>(
      context,
      title: s == null ? 'Register a store' : 'Edit ${s['storeName']}',
      subtitle: s == null ? 'Each store gets its own name, logo and contact details on MVEC.' : 'Update how this storefront appears to buyers.',
      fields: [
        const FieldSpec('logo', 'Store logo', type: FieldType.image),
        const FieldSpec('storeName', 'Store name', required: true, hint: 'e.g. Kigali Tech Store'),
        FieldSpec(
          'businessCategory',
          'Business category',
          type: FieldType.select,
          placeholderOption: 'Select a category',
          options: [for (final c in _categories) (strOf(c['name']), strOf(c['name']))],
        ),
        const FieldSpec('city', 'City', hint: 'Kigali'),
        const FieldSpec('description', 'Description', type: FieldType.textarea, hint: 'Tell buyers what your store offers'),
        const FieldSpec('contactEmail', 'Contact email', type: FieldType.email, required: true),
        const FieldSpec('contactPhone', 'Contact phone', type: FieldType.phone, required: true, hint: '07xx xxx xxx'),
        const FieldSpec('businessAddress', 'Business address', hint: 'Street, building'),
      ],
      initial:
          s == null
              ? {}
              : {
                'storeName': strOf(s['storeName']),
                'businessCategory': strOf(s['businessCategory']),
                'description': strOf(s['description']),
                'contactEmail': strOf(s['contactEmail']),
                'contactPhone': strOf(s['contactPhone']),
                'city': strOf(asMap(s['address'])['city'], s['location'] is String ? s['location'] as String : ''),
                'businessAddress': strOf(s['businessAddress'] ?? asMap(s['address'])['street']),
                'logo': strOf(s['logo']),
              },
      submitLabel: s == null ? 'Register store' : 'Save changes',
      onSubmit: (v) => s == null ? jpost('/stores', v) : jput('/stores/mine/${idOf(s)}', v),
    );
    if (saved != null && mounted) {
      toast(context, s == null ? '${asMap(saved['store'])['storeName'] ?? 'Store'} has been registered.' : 'Store details saved.');
      _data.reload();
    }
  }

  Future<void> _act(Map<String, dynamic> s, Future<dynamic> Function() fn) async {
    setState(() => _busy = idOf(s));
    final ok = await runAction(context, fn);
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final stores = asMaps(d['stores']);
        final max = d['maxStores'];
        final atLimit = max != null && stores.length >= numOf(max);
        final register = GradientButton(label: 'Register store', icon: Icons.add_rounded, compact: true, onPressed: atLimit ? null : () => _edit(null));
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'My Stores',
          subtitle: 'Run several storefronts from one seller account. Your primary store is shown on your vendor profile.',
          onRefresh: _data.reload,
          action: register,
          children: [
            if (atLimit) Tiny('You can own up to $max stores.'),
            if (stores.isEmpty)
              EmptyState(icon: Icons.storefront_outlined, title: "You don't have a store yet", message: 'Register your first store to start listing products and receiving orders.', action: register)
            else ...[
              Tiny('${stores.length}${max != null ? ' of $max' : ''} stores'),
              for (final s in stores)
                RecordCard(
                  leading: ProductImage(src: strOf(s['logo']), size: 48, radius: 10),
                  title: strOf(s['storeName']),
                  badges: [if (s['isPrimary'] == true) const StatusChip('Primary', tone: StatusTone.good)],
                  subtitle: '/${s['slug'] ?? ''} · ${strOf(s['businessCategory'], '—')}',
                  lines: [
                    [
                      strOf(asMap(s['address'])['city'], s['location'] is String ? s['location'] as String : ''),
                      strOf(s['contactPhone']),
                      strOf(s['contactEmail']),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    '${numOf(s['productCount']).toInt()} products · since ${formatDate(s['createdAt'])}',
                  ],
                  status: Pill(s['status']),
                  actions: [
                    ActionChipBtn('Edit', icon: Icons.edit_outlined, busy: _busy == idOf(s), onPressed: () => _edit(s)),
                    if (s['isPrimary'] != true) ActionChipBtn('Make primary', busy: _busy == idOf(s), onPressed: () => _act(s, () => jpatch('/stores/mine/${idOf(s)}/primary'))),
                    if (s['isPrimary'] != true)
                      ActionChipBtn(
                        'Delete',
                        danger: true,
                        busy: _busy == idOf(s),
                        onPressed: () async {
                          if (await confirmDialog(context, 'Delete ${s['storeName']}? Its products, promotions and shipping zones move to your primary store.', confirm: 'Delete', danger: true)) {
                            await _act(s, () => jdelete('/stores/mine/${idOf(s)}'));
                          }
                        },
                      ),
                  ],
                ),
              const Tiny('Payouts, staff and your seller balance are shared across all your stores. Products without a store are listed under the primary store.'),
            ],
          ],
        );
      },
    );
  }
}

// ─── Settings ────────────────────────────────────────────────────────────────

const _shortcuts = [
  ('/vendor/stores', 'Storefront', 'Logo, description and store contact details', 'shop'),
  ('/vendor/shipping', 'Shipping zones', 'Delivery fees, regions and delivery times', 'box'),
  ('/vendor/payouts', 'Payouts', 'Balance and mobile money withdrawals', 'wallet'),
  ('/vendor/team', 'Team & permissions', 'Staff accounts and their access', 'users'),
  ('/vendor/notifications', 'Notifications', 'Order, stock and payout alerts', 'bell'),
  ('/vendor/profile', 'Account & security', 'Your personal profile and password', 'shield'),
];

/// `/vendor/settings` — business profile, account status and commission.
class SellerSettingsPage extends ConsumerStatefulWidget {
  const SellerSettingsPage({super.key});

  @override
  ConsumerState<SellerSettingsPage> createState() => _SellerSettingsPageState();
}

class _SellerSettingsPageState extends ConsumerState<SellerSettingsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([
      jget('/vendors/me/profile'),
      jget('/payouts/balance').catchError((_) => <String, dynamic>{}),
      jget('/vendors/me/fees').catchError((_) => <String, dynamic>{}),
      jlist('/categories', 'categories').catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (vendor: asMap((r[0] as Map)['vendor']), commissionRate: strOf((r[1] as Map)['commissionRate']), fees: r[2] as Map<String, dynamic>, categories: r[3] as List<Map<String, dynamic>>);
  });
  final _c = {
    for (final k in ['businessName', 'email', 'phone', 'location', 'description']) k: TextEditingController(),
  };
  String _category = '';
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _data.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_c['businessName']!.text.trim().isEmpty) {
      toast(context, 'Business name is required.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await jpatch('/vendors/me/profile', {for (final e in _c.entries) e.key: e.value.text.trim(), 'category': _category});
      if (mounted) toast(context, res['message'] == 'Vendor profile updated' ? 'Business profile saved.' : strOf(res['message'], 'Business profile saved.'));
      ref.read(authProvider.notifier).refresh().ignore();
      _data.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Settings',
      subtitle: 'Business profile, verification status and shortcuts to every store setting.',
      onRefresh: _data.reload,
      children: [
        ListenableBuilder(
          listenable: _data,
          builder: (context, _) {
            if (_data.data == null && _data.error != null) {
              return Notice(text: statusOf(_data.error!) == 404 ? 'No business profile yet. Create your store first from My Stores.' : errorText(_data.error!));
            }
            final d = _data.data;
            if (d == null) return const LoadingState();
            final v = d.vendor;
            if (!_filled) {
              _filled = true;
              for (final k in _c.keys) {
                _c[k]!.text = strOf(v[k]);
              }
              _category = strOf(v['category']);
            }
            final fees = d.fees;
            final cats = asMaps(fees['categories']);
            final defaultPercent = fees['defaultPercent'];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (v['verificationStatus'] == 'REJECTED')
                  Notice(text: 'MVEC asked for changes: ${strOf(v['verificationNote'], 'Check your business details.')} Save your profile to send it back for review.'),
                Section(
                  title: 'Business profile',
                  subtitle: 'Shown on your public vendor page',
                  children: [
                    TextField(controller: _c['businessName'], decoration: const InputDecoration(labelText: 'Business name *')),
                    const SizedBox(height: 10),
                    FilterSelect(
                      label: 'Business category',
                      value: _category,
                      options: [
                        ('', 'Select a category'),
                        for (final c in d.categories) (strOf(c['name']), strOf(c['name'])),
                        if (_category.isNotEmpty && !d.categories.any((c) => c['name'] == _category)) (_category, _category),
                      ],
                      onChanged: (x) => setState(() => _category = x),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: _c['email'], keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Business email')),
                    const SizedBox(height: 10),
                    TextField(controller: _c['phone'], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Business phone')),
                    const SizedBox(height: 10),
                    TextField(controller: _c['location'], decoration: const InputDecoration(labelText: 'Location', hintText: 'Kigali')),
                    const SizedBox(height: 10),
                    TextField(controller: _c['description'], minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'About the business')),
                    const SizedBox(height: 12),
                    GradientButton(label: 'Save profile', loading: _saving, onPressed: _save),
                  ],
                ),
                Section(
                  title: 'Account status',
                  subtitle: 'Managed by MVEC',
                  children: [
                    Row(children: [const Expanded(child: Text('Account')), Pill(strOf(v['status'], 'ACTIVE'))]),
                    const SizedBox(height: 8),
                    Row(children: [const Expanded(child: Text('Verification')), Pill(strOf(v['verificationStatus'], 'PENDING'))]),
                    KV('MVEC commission', defaultPercent != null ? '$defaultPercent% unless your category differs' : d.commissionRate),
                    KV('Rating', '${numOf(v['ratingAvg']).toStringAsFixed(1)} / 5'),
                  ],
                ),
                if (defaultPercent != null && cats.any((c) => c['percent'] != defaultPercent))
                  Section(
                    title: 'Your MVEC commission by category',
                    subtitle: 'Taken from each sale when the buyer pays. Payment provider fees are paid by ${fees['gatewayFeePayer'] == 'SELLER' ? 'you' : 'MVEC'}.',
                    children: [
                      for (final c in cats.where((c) => c['percent'] != defaultPercent)) KV('${c['category']} (${c['source']})', '${c['percent']}%'),
                      KV('Every other category', '$defaultPercent%'),
                    ],
                  ),
                DataCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final (to, title, sub, icon) in _shortcuts)
                        ListTile(
                          leading: Icon(_iconFor(icon), color: context.mv.accentDeep),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.go(to),
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

IconData _iconFor(String name) => switch (name) {
  'shop' => Icons.storefront_outlined,
  'box' => Icons.local_shipping_outlined,
  'wallet' => Icons.account_balance_wallet_outlined,
  'users' => Icons.group_outlined,
  'bell' => Icons.notifications_none_rounded,
  _ => Icons.shield_outlined,
};

// ─── Team ────────────────────────────────────────────────────────────────────

const _roleHelp = {
  'STORE_MANAGER': 'Runs the store day to day: products, orders, marketing, analytics, settings.',
  'ORDER_MANAGER': 'Handles orders, customers and disputes.',
  'CATALOG_MANAGER': 'Manages products, categories, inventory and stock purchases.',
  'MARKETING_MANAGER': 'Runs promotions, ads, reviews and affiliates; sees analytics.',
  'FINANCE_MANAGER': 'Handles payouts, the statement and the subscription; sees analytics.',
};

String _ago(dynamic d) {
  final t = parseDate(d);
  if (t == null) return 'Never';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 5) return 'Online now';
  if (m < 60) return '$m min ago';
  if (m < 1440) return '${(m / 60).round()} h ago';
  return m < 10080 ? '${(m / 1440).round()} days ago' : formatDate(d);
}

/// `/vendor/team` — staff logins with role-based access and their activity.
class SellerTeamPage extends StatefulWidget {
  const SellerTeamPage({super.key});

  @override
  State<SellerTeamPage> createState() => _SellerTeamPageState();
}

class _SellerTeamPageState extends State<SellerTeamPage> {
  late final _data = Loader(() => jget('/staff'));
  Loader<Map<String, dynamic>>? _activity;
  String _tab = 'MEMBERS';
  String _activityFor = '';
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    _activity?.dispose();
    super.dispose();
  }

  void _loadActivity() {
    final old = _activity;
    _activity = Loader(() => jget('/staff/activity', {'staffId': _activityFor.isEmpty ? null : _activityFor, 'limit': 100}));
    old?.dispose();
    setState(() {});
  }

  Future<void> _act(Map<String, dynamic> r, Future<dynamic> Function() fn, String message) async {
    setState(() => _busy = idOf(r));
    final ok = await runAction(context, fn, success: message);
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final members = asMaps(d['staff']);
        final staff = members.where((m) => m['role'] != 'OWNER').toList();
        final permissions = asMaps(d['permissions']);
        final roles = asMaps(d['roles']);
        final viewer = d['viewer'] == null ? {'owner': true} : asMap(d['viewer']);
        bool isSelf(Map<String, dynamic> r) => strOf(viewer['staffId']).isNotEmpty && '${viewer['staffId']}' == idOf(r);
        bool grantable(String key) => viewer['owner'] == true || asMap(viewer['permissionsMap'])[key] == true;
        final roleOptions = [
          for (final r in roles)
            if ((r['permissions'] is List ? r['permissions'] as List : const []).every((p) => grantable('$p'))) ('${r['key']}', staffRoleLabel[r['key']] ?? '${r['key']}'),
        ];
        List<String> presetOf(String key) => [for (final p in (roles.where((r) => r['key'] == key).map((r) => r['permissions']).firstOrNull as List? ?? const [])) '$p'];
        final accessOptions = [for (final p in permissions.where((p) => p['key'] != 'canViewDashboard' && grantable('${p['key']}'))) ('${p['key']}', strOf(p['label']))];
        Map<String, bool> toMap(dynamic list) => {for (final p in permissions) '${p['key']}': p['key'] == 'canViewDashboard' || (list is List && list.contains(p['key']))};
        final week = DateTime.now().subtract(const Duration(days: 7));

        Future<void> add() async {
          final first = roleOptions.where((o) => o.$1 == 'ORDER_MANAGER').map((o) => o.$1).firstOrNull ?? roleOptions.first.$1;
          final res = await showFormSheet<Map<String, dynamic>>(
            context,
            title: 'Add team member',
            subtitle: 'Creates a separate login for your store.',
            fields: [
              const FieldSpec('name', 'Full name', required: true),
              const FieldSpec('email', 'Email (used to sign in)', type: FieldType.email, required: true),
              const FieldSpec('phone', 'Phone', type: FieldType.phone, hint: '07xx xxx xxx'),
              FieldSpec('role', 'Role', type: FieldType.select, required: true, options: roleOptions),
              FieldSpec('access', 'Access', type: FieldType.checkboxes, options: accessOptions, help: 'Starts from the role; adjust if needed.'),
              const FieldSpec('password', 'Temporary password', type: FieldType.password, required: true, help: 'At least 8 characters. Share it securely; they can change it from their profile.'),
            ],
            initial: {'role': first, 'access': presetOf(first)},
            onFieldChange: (name, value, _) => name == 'role' ? {'access': presetOf('$value')} : null,
            submitLabel: 'Create login',
            onSubmit: (v) async {
              if ('${v['password']}'.length < 8) throw ApiException('The password must be at least 8 characters.');
              final r = await jpost('/staff', {'name': v['name'], 'email': v['email'], 'phone': v['phone'], 'role': v['role'], 'password': v['password'], 'permissions': toMap(v['access'])});
              return {...r, 'email': v['email']};
            },
          );
          if (res != null && context.mounted) {
            toast(context, '${strOf(res['message'], 'Team member added.')} ${res['email']} can now sign in.');
            _data.reload();
          }
        }

        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Team / Staff',
          subtitle: 'Give employees their own login to this store with only the access they need. Every change they make is logged.',
          onRefresh: _data.reload,
          action: GradientButton(label: 'Add member', icon: Icons.add_rounded, compact: true, onPressed: roleOptions.isEmpty ? null : add),
          children: [
            MetricGrid(
              children: [
                MetricCard(label: 'Team members', value: '${staff.length}', icon: 'users', sub: 'Not counting you'),
                MetricCard(label: 'Active', value: '${staff.where((m) => m['active'] == true).length}', icon: 'check', sub: 'Can sign in'),
                MetricCard(label: 'Suspended', value: '${staff.where((m) => m['active'] != true).length}', icon: 'shield', sub: 'Access paused'),
                MetricCard(
                  label: 'Active this week',
                  value: '${staff.where((m) => (parseDate(m['lastActiveAt']) ?? DateTime(2000)).isAfter(week)).length}',
                  icon: 'eye',
                  sub: 'Signed in during the last 7 days',
                ),
              ],
            ),
            const SizedBox(height: 14),
            TabChips(
              tabs: const [('MEMBERS', 'Members'), ('ACTIVITY', 'Activity')],
              value: _tab,
              counts: {'MEMBERS': members.length},
              onChanged: (v) {
                setState(() => _tab = v);
                if (v == 'ACTIVITY' && _activity == null) _loadActivity();
              },
            ),
            if (_tab == 'MEMBERS')
              for (final r in members)
                RecordCard(
                  title: '${r['name']}${isSelf(r) ? ' (you)' : ''}',
                  subtitle: [strOf(r['email']), strOf(r['phone'])].where((x) => x.isNotEmpty).join(' · '),
                  lines: [
                    r['role'] == 'OWNER'
                        ? 'Owner · Everything'
                        : '${staffRoleLabel[r['role']] ?? r['role']} · ${permissions.where((p) => asMap(r['permissionsMap'])[p['key']] == true && p['key'] != 'canViewDashboard').map((p) => strOf(p['label']).split(RegExp(r'[,&]')).first.trim()).join(', ')}${r['customized'] == true ? ' (custom)' : ''}',
                    if (r['role'] != 'OWNER') 'Last active: ${_ago(r['lastActiveAt'])}',
                  ],
                  status: Pill(r['role'] == 'OWNER' ? 'OWNER' : strOf(r['status'], r['active'] == true ? 'ACTIVE' : 'SUSPENDED')),
                  actions:
                      r['role'] == 'OWNER' || isSelf(r)
                          ? const []
                          : [
                            ActionChipBtn(
                              'Role',
                              busy: _busy == idOf(r),
                              onPressed: () async {
                                final res = await showFormSheet<bool>(
                                  context,
                                  title: 'Role for ${r['name']}',
                                  fields: [
                                    FieldSpec(
                                      'role',
                                      'Role',
                                      type: FieldType.select,
                                      options: roleOptions.any((o) => o.$1 == r['role']) ? roleOptions : [('${r['role']}', staffRoleLabel[r['role']] ?? '${r['role']}'), ...roleOptions],
                                    ),
                                  ],
                                  initial: {'role': r['role']},
                                  onSubmit: (v) async {
                                    await jput('/staff/${idOf(r)}', {'role': v['role']});
                                    return true;
                                  },
                                );
                                if (res == true && context.mounted) {
                                  toast(context, 'Role updated.');
                                  _data.reload();
                                }
                              },
                            ),
                            ActionChipBtn(
                              'Access',
                              icon: Icons.shield_outlined,
                              onPressed: () async {
                                final res = await showFormSheet<bool>(
                                  context,
                                  title: 'Access for ${r['name']}',
                                  subtitle: '${staffRoleLabel[r['role']] ?? r['role']}: ${_roleHelp[r['role']] ?? ''}',
                                  fields: [
                                    FieldSpec('access', 'Access', type: FieldType.checkboxes, options: accessOptions, help: "Changes apply to their next action; they don't need to sign in again."),
                                  ],
                                  initial: {
                                    'access': [
                                      for (final e in asMap(r['permissionsMap']).entries)
                                        if (e.value == true) e.key,
                                    ],
                                  },
                                  submitLabel: 'Save access',
                                  onSubmit: (v) async {
                                    await jput('/staff/${idOf(r)}', {'permissions': toMap(v['access'])});
                                    return true;
                                  },
                                );
                                if (res == true && context.mounted) {
                                  toast(context, 'Access updated.');
                                  _data.reload();
                                }
                              },
                            ),
                            ActionChipBtn(
                              'Details',
                              icon: Icons.edit_outlined,
                              onPressed: () async {
                                final res = await showFormSheet<bool>(
                                  context,
                                  title: 'Edit details',
                                  fields: const [FieldSpec('name', 'Full name', required: true), FieldSpec('phone', 'Phone', type: FieldType.phone)],
                                  initial: {'name': r['name'], 'phone': strOf(r['phone'])},
                                  onSubmit: (v) async {
                                    await jput('/staff/${idOf(r)}', {'name': v['name'], 'phone': v['phone']});
                                    return true;
                                  },
                                );
                                if (res == true && context.mounted) {
                                  toast(context, 'Details saved.');
                                  _data.reload();
                                }
                              },
                            ),
                            ActionChipBtn(
                              'Password',
                              onPressed: () async {
                                final res = await showFormSheet<Map<String, dynamic>>(
                                  context,
                                  title: 'New password for ${r['name']}',
                                  subtitle: 'Use this if they forgot their password. Share it with them securely.',
                                  fields: const [FieldSpec('password', 'New temporary password', type: FieldType.password, required: true)],
                                  submitLabel: 'Set password',
                                  onSubmit: (v) async {
                                    if ('${v['password']}'.length < 8) throw ApiException('The password must be at least 8 characters.');
                                    return jpost('/staff/${idOf(r)}/password', {'password': v['password']});
                                  },
                                );
                                if (res != null && context.mounted) toast(context, strOf(res['message'], 'Password updated.'));
                              },
                            ),
                            ActionChipBtn(
                              r['active'] == true ? 'Suspend' : 'Restore',
                              busy: _busy == idOf(r),
                              onPressed: () async {
                                if (r['active'] == true && !await confirmDialog(context, 'Suspend ${r['name']}? They are signed out of the store immediately.', confirm: 'Suspend', danger: true)) {
                                  return;
                                }
                                await _act(r, () => jput('/staff/${idOf(r)}', {'active': r['active'] != true}), r['active'] == true ? 'Access suspended.' : 'Access restored.');
                              },
                            ),
                            ActionChipBtn(
                              'Remove',
                              danger: true,
                              busy: _busy == idOf(r),
                              onPressed: () async {
                                if (!await confirmDialog(
                                  context,
                                  'Remove ${r['name']} from your team? Their login stops working; you can add them back later with the same email.',
                                  confirm: 'Remove',
                                  danger: true,
                                )) {
                                  return;
                                }
                                await _act(r, () => jdelete('/staff/${idOf(r)}'), 'Team member removed.');
                              },
                            ),
                          ],
                ),
            if (_tab == 'ACTIVITY') ...[
              FilterSelect(
                label: 'Team member',
                value: _activityFor,
                options: [('', 'All team members'), for (final m in staff) (idOf(m), strOf(m['name']))],
                onChanged: (v) {
                  _activityFor = v;
                  _loadActivity();
                },
              ),
              const SizedBox(height: 12),
              if (_activity != null)
                LoadView(
                  loader: _activity!,
                  builder: (a) {
                    final list = asMaps(a['activity']);
                    if (list.isEmpty) return const Tiny('No changes by team members yet. Changes to products, orders, promotions, payouts and settings show up here.');
                    return Column(
                      children: [
                        for (final x in list)
                          RecordCard(title: strOf(x['action']), subtitle: '${x['name']} · ${strOf(x['path']).replaceFirst(RegExp(r'^/api'), '')}', lines: [formatDateTime(x['at'])]),
                      ],
                    );
                  },
                ),
            ],
            const InfoBox(
              title: 'How staff access works',
              text:
                  "Team members sign in with their own email and password and work inside your store. Menus they can't use are hidden, and the server refuses anything outside their access. Suspending or removing someone takes effect immediately. Only you can manage payouts unless you grant it.",
            ),
          ],
        );
      },
    );
  }
}

// ─── Promotions ──────────────────────────────────────────────────────────────

const _promoTypes = [('PERCENT', 'Percentage off'), ('FIXED', 'Fixed amount off'), ('FREE_SHIPPING', 'Free shipping')];
const _promoStatuses = [('DRAFT', 'Draft'), ('SCHEDULED', 'Scheduled'), ('ACTIVE', 'Active'), ('PAUSED', 'Paused')];
const _liveLabel = {'ACTIVE': 'Live', 'SCHEDULED': 'Scheduled', 'EXPIRED': 'Expired', 'USED_UP': 'Used up', 'PAUSED': 'Paused', 'DRAFT': 'Draft', 'CANCELLED': 'Cancelled'};
const _promoTabs = [('ALL', 'All'), ('ACTIVE', 'Live'), ('SCHEDULED', 'Scheduled'), ('DRAFT', 'Drafts'), ('PAUSED', 'Paused'), ('ENDED', 'Ended')];
bool _inPromoTab(Map<String, dynamic> r, String tab) => tab == 'ALL' || (tab == 'ENDED' ? ['EXPIRED', 'USED_UP', 'CANCELLED'].contains(r['liveStatus']) : r['liveStatus'] == tab);

const _promoFields = [
  FieldSpec('name', 'Promotion name', required: true, hint: 'e.g. Back to School'),
  FieldSpec('code', 'Coupon code', required: true, hint: 'SCHOOL15'),
  FieldSpec('type', 'Discount type', type: FieldType.select, options: _promoTypes),
  FieldSpec('value', 'Discount value', type: FieldType.number, help: 'Percent (1–100) or RWF amount. Ignored for free shipping.'),
  FieldSpec('minOrderAmount', 'Minimum spend on your items (RWF)', type: FieldType.number),
  FieldSpec('startsAt', 'Starts', type: FieldType.date),
  FieldSpec('endsAt', 'Ends', type: FieldType.date),
  FieldSpec('usageLimit', 'Usage limit', type: FieldType.number, hint: 'Unlimited'),
  FieldSpec('status', 'Status', type: FieldType.select, options: _promoStatuses),
];

Map<String, dynamic> _promoPayload(Map<String, dynamic> f) => {
  'name': f['name'],
  'code': f['code'],
  'type': f['type'],
  'value': f['type'] == 'FREE_SHIPPING' ? 0 : numOf(f['value']),
  'minOrderAmount': numOf(f['minOrderAmount']),
  'usageLimit': '${f['usageLimit'] ?? ''}'.isEmpty ? null : numOf(f['usageLimit']),
  'startsAt': '${f['startsAt'] ?? ''}'.isEmpty ? null : f['startsAt'],
  'endsAt': '${f['endsAt'] ?? ''}'.isEmpty ? null : f['endsAt'],
  'status': f['status'],
};

String _inputDate(dynamic v) {
  final d = parseDate(v);
  return d == null ? '' : d.toIso8601String().substring(0, 10);
}

/// `/vendor/promotions` — coupon codes for the seller's items.
class SellerPromotionsPage extends StatefulWidget {
  const SellerPromotionsPage({super.key});

  @override
  State<SellerPromotionsPage> createState() => _SellerPromotionsPageState();
}

class _SellerPromotionsPageState extends State<SellerPromotionsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jlist('/promotions', 'data'),
      jlist('/stores/mine', 'stores').catchError((_) => <Map<String, dynamic>>[]),
      vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (promos: r[0], stores: r[1], products: r[2]);
  });
  String _tab = 'ALL';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? p, List<Map<String, dynamic>> stores, List<Map<String, dynamic>> products) async {
    final isNew = p == null;
    final res = await showFormSheet<bool>(
      context,
      title: isNew ? 'New promotion' : 'Edit promotion',
      fields: [
        if (isNew && stores.length > 1)
          FieldSpec('storeId', 'Store', type: FieldType.select, options: [for (final s in stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' (primary)' : ''}')]),
        if (isNew) FieldSpec('product', 'Applies to', type: FieldType.select, options: [('', 'All my products'), for (final x in products) (idOf(x), strOf(x['name']))]),
        ..._promoFields,
      ],
      initial:
          isNew
              ? {'type': 'PERCENT', 'status': 'DRAFT', 'value': '10', 'storeId': idOf(stores.where((s) => s['isPrimary'] == true).firstOrNull), 'product': ''}
              : {
                ...p,
                'startsAt': _inputDate(p['startsAt']),
                'endsAt': _inputDate(p['endsAt']),
                'usageLimit': p['usageLimit'] == null ? '' : '${p['usageLimit']}',
                'value': '${p['value'] ?? ''}',
                'minOrderAmount': '${p['minOrderAmount'] ?? ''}',
              },
      submitLabel: isNew ? 'Create promotion' : 'Save changes',
      onSubmit: (v) async {
        if (isNew) {
          await jpost('/promotions', {..._promoPayload(v), if ('${v['storeId'] ?? ''}'.isNotEmpty) 'storeId': v['storeId'], if ('${v['product'] ?? ''}'.isNotEmpty) 'product': v['product']});
        } else {
          await jpatch('/promotions/${p['id']}', _promoPayload(v));
        }
        return true;
      },
    );
    if (res == true && mounted) {
      toast(context, isNew ? 'Promotion created.' : 'Promotion saved.');
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final rows = d.promos;
        final shown = rows.where((r) => _inPromoTab(r, _tab)).toList();
        num orders = 0, sales = 0, discount = 0;
        for (final r in rows) {
          final s = asMap(r['stats']);
          orders += numOf(s['orders']);
          sales += numOf(s['sales']);
          discount += numOf(s['discountGiven']);
        }
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Promotions',
          subtitle: 'Coupon codes buyers enter at checkout. Discounts apply only to your items and come out of your earnings for that order.',
          onRefresh: _data.reload,
          action: GradientButton(label: 'New promotion', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null, d.stores, d.products)),
          children: [
            MetricGrid(
              children: [
                MetricCard(
                  label: 'Live codes',
                  value: '${rows.where((r) => r['liveStatus'] == 'ACTIVE').length}',
                  icon: 'tag',
                  sub: '${rows.where((r) => r['liveStatus'] == 'SCHEDULED').length} scheduled',
                ),
                MetricCard(label: 'Orders with a code', value: '$orders', icon: 'cart', sub: 'Excluding cancelled orders'),
                MetricCard(label: 'Sales from codes', value: money(sales), icon: 'chart', sub: 'Your items, after discount'),
                MetricCard(label: 'Discount given', value: money(discount), icon: 'wallet', sub: 'Paid from your earnings'),
              ],
            ),
            const SizedBox(height: 14),
            TabChips(tabs: _promoTabs, value: _tab, counts: {for (final t in _promoTabs) t.$1: rows.where((r) => _inPromoTab(r, t.$1)).length}, onChanged: (v) => setState(() => _tab = v)),
            Paged<Map<String, dynamic>>(
              items: shown,
              empty: const EmptyState(icon: Icons.local_offer_outlined, title: 'No promotions here', message: 'Create a code and share it with your buyers.'),
              itemBuilder: (r) {
                final s = asMap(r['stats']);
                final product = strOf(r['product']).isEmpty ? '' : strOf(d.products.where((p) => idOf(p) == '${r['product']}').map((p) => p['name']).firstOrNull, 'one product');
                return RecordCard(
                  title: strOf(r['name']),
                  subtitle: '${r['discount'] ?? ''} · ${numOf(r['minOrderAmount']) > 0 ? 'Min. ${money(r['minOrderAmount'])}' : 'No minimum'}${product.isEmpty ? '' : ' · $product'}',
                  lines: [
                    'Used ${numOf(r['usedCount']).toInt()}${r['usageLimit'] != null ? ' / ${r['usageLimit']}' : ''} · ${r['startsAt'] != null ? formatDate(r['startsAt']) : 'Now'} → ${r['endsAt'] != null ? formatDate(r['endsAt']) : 'no end'}',
                    numOf(s['orders']) > 0 ? '${money(s['sales'])} from ${s['orders']} order${numOf(s['orders']) == 1 ? '' : 's'} · ${money(s['discountGiven'])} discount' : 'No orders yet',
                    if (d.stores.length > 1) 'Store: ${strOf(d.stores.where((st) => idOf(st) == '${r['store']}').map((st) => st['storeName']).firstOrNull, '—')}',
                  ],
                  status: Pill(r['liveStatus'] ?? r['status'], label: _liveLabel[r['liveStatus']] ?? titleCase(r['liveStatus'] ?? r['status'])),
                  actions: [
                    ActionChipBtn(strOf(r['code']), icon: Icons.copy_rounded, onPressed: () => copyText(context, strOf(r['code']), '${r['code']} copied.')),
                    ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(r, d.stores, d.products)),
                    if (['ACTIVE', 'PAUSED'].contains(r['status']))
                      ActionChipBtn(
                        r['status'] == 'ACTIVE' ? 'Pause' : 'Activate',
                        onPressed: () async {
                          if (await runAction(context, () => jpatch('/promotions/${r['id']}', {'status': r['status'] == 'ACTIVE' ? 'PAUSED' : 'ACTIVE'}), success: 'Promotion updated.')) {
                            _data.reload();
                          }
                        },
                      ),
                    ActionChipBtn(
                      'Delete',
                      danger: true,
                      onPressed: () async {
                        if (!await confirmDialog(context, 'Delete promotion ${r['code']}?', confirm: 'Delete', danger: true)) return;
                        if (context.mounted && await runAction(context, () => jdelete('/promotions/${r['id']}'), success: 'Promotion deleted.')) _data.reload();
                      },
                    ),
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

// ─── Shipping ────────────────────────────────────────────────────────────────

int _coverageScore(Map<String, dynamic> z, String province, String district) {
  final ds = [for (final d in (z['districts'] is List ? z['districts'] as List : const [])) '$d'.toLowerCase()];
  final ps = [for (final p in (z['provinces'] is List ? z['provinces'] as List : const [])) '$p'.toLowerCase()];
  if (ds.isNotEmpty) return ds.contains(district.toLowerCase()) ? 3 : 0;
  if (ps.isNotEmpty) return ps.contains(province.toLowerCase()) ? 2 : 0;
  return 1;
}

Map<String, dynamic>? _zoneFor(List<Map<String, dynamic>> zones, String province, String district) {
  Map<String, dynamic>? best;
  var score = 0;
  for (final z in zones) {
    final s = _coverageScore(z, province, district);
    if (s > score || (s == score && s > 0 && best != null && numOf(z['fee']) < numOf(best['fee']))) {
      best = z;
      score = s;
    }
  }
  return best;
}

/// `/vendor/shipping` — delivery zones and fees per store, coverage map and
/// a test address.
class SellerShippingPage extends StatefulWidget {
  const SellerShippingPage({super.key});

  @override
  State<SellerShippingPage> createState() => _SellerShippingPageState();
}

class _SellerShippingPageState extends State<SellerShippingPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([jlist('/shipping/zones/mine', 'data'), jlist('/stores/mine', 'stores').catchError((_) => <Map<String, dynamic>>[])]);
    return (zones: r[0], stores: r[1]);
  });
  String _storeTab = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? z, String storeId) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ZoneEditor(zone: z, storeId: storeId)));
    if (saved != null && mounted) {
      toast(context, saved);
      _data.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final stores = d.stores;
        final primary = stores.where((s) => s['isPrimary'] == true).firstOrNull ?? stores.firstOrNull;
        final active = _storeTab.isNotEmpty ? _storeTab : idOf(primary);
        final storeZones = d.zones.where((z) => idOf(z['store']) == active).toList();
        final effective = (storeZones.isNotEmpty ? storeZones : d.zones).where((z) => z['status'] == 'ACTIVE').toList();
        final usingOther = storeZones.isEmpty && d.zones.isNotEmpty;
        var uncovered = 0;
        for (final p in rwandaLocations.keys) {
          for (final dist in rwandaLocations[p]!) {
            if (_zoneFor(effective, p, dist) == null) uncovered++;
          }
        }
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Shipping',
          subtitle: 'Delivery zones and fees per store. Checkout charges buyers these fees for their district, and the fees are paid to you in full.',
          onRefresh: _data.reload,
          action: stores.isEmpty ? null : GradientButton(label: 'Add zone', icon: Icons.add_rounded, compact: true, onPressed: () => _edit(null, active)),
          children: [
            if (stores.isEmpty) const EmptyState(icon: Icons.storefront_outlined, title: 'Register a store first', message: 'Shipping zones belong to a store.'),
            if (stores.isNotEmpty) ...[
              if (stores.length > 1)
                TabChips(
                  tabs: [for (final s in stores) (idOf(s), '${s['storeName']}${s['isPrimary'] == true ? ' ★' : ''}')],
                  value: active,
                  counts: {for (final s in stores) idOf(s): d.zones.where((z) => idOf(z['store']) == idOf(s)).length},
                  onChanged: (v) => setState(() => _storeTab = v),
                ),
              if (d.zones.isEmpty)
                const InfoBox(
                  title: 'Using MVEC standard rates',
                  text: 'Until you add a zone, buyers pay MVEC standard delivery: free in Kigali City and 5,000 RWF elsewhere (express 10,000 RWF). Add zones to set your own fees and coverage.',
                ),
              if (usingOther) const InfoBox(title: 'No zones for this store yet', text: "Checkout uses your other stores' zones for its items until you add zones here."),
              Section(
                title: 'Zones',
                subtitle: '${storeZones.length} zone${storeZones.length == 1 ? '' : 's'} for this store',
                children: [
                  if (storeZones.isEmpty) const Tiny('No zones yet. Add one for each area you deliver to, e.g. Kigali City and a nationwide fallback.'),
                  for (final z in storeZones)
                    RecordCard(
                      title: strOf(z['name']),
                      subtitle: strOf(z['coverage']),
                      lines: [
                        'Standard ${numOf(z['fee']) == 0 ? 'Free' : money(z['fee'])}'
                            '${(z['methods'] is List && (z['methods'] as List).contains('EXPRESS')) ? ' · Express ${money(z['expressFee'] ?? z['fee'])}' : ''}'
                            '${(z['methods'] is List && (z['methods'] as List).contains('PICKUP')) ? ' · Pickup ${numOf(z['pickupFee']) > 0 ? money(z['pickupFee']) : 'Free'}' : ''}',
                        '${numOf(z['freeOverAmount']) > 0 ? 'Free from ${money(z['freeOverAmount'])} · ' : ''}Time ${z['eta'] ?? ''}',
                      ],
                      status: Pill(z['status']),
                      actions: [
                        ActionChipBtn('Edit', icon: Icons.edit_outlined, onPressed: () => _edit(z, active)),
                        ActionChipBtn(
                          z['status'] == 'ACTIVE' ? 'Pause' : 'Activate',
                          onPressed: () async {
                            if (await runAction(context, () => jpatch('/shipping/zones/${z['id']}', {'status': z['status'] == 'ACTIVE' ? 'PAUSED' : 'ACTIVE'}), success: 'Zone updated.')) {
                              _data.reload();
                            }
                          },
                        ),
                        ActionChipBtn(
                          'Delete',
                          danger: true,
                          onPressed: () async {
                            if (!await confirmDialog(context, 'Delete zone ${z['name']}?', confirm: 'Delete', danger: true)) return;
                            if (context.mounted && await runAction(context, () => jdelete('/shipping/zones/${z['id']}'), success: 'Zone deleted.')) _data.reload();
                          },
                        ),
                      ],
                    ),
                ],
              ),
              Section(
                title: 'Coverage',
                subtitle: d.zones.isNotEmpty ? (uncovered > 0 ? '$uncovered of 30 districts not delivered' : 'All 30 districts delivered') : 'MVEC standard rates apply',
                children: [
                  for (final p in rwandaLocations.keys) ...[
                    Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(p, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final dist in rwandaLocations[p]!)
                          Builder(
                            builder: (_) {
                              final z = _zoneFor(effective, p, dist);
                              final tone =
                                  d.zones.isEmpty
                                      ? StatusTone.neutral
                                      : z != null
                                      ? StatusTone.good
                                      : StatusTone.bad;
                              final fee = z == null ? '' : (numOf(z['fee']) == 0 ? ' · Free' : ' · ${(numOf(z['fee']) / 1000 * 10).round() / 10}k');
                              return StatusChip('$dist$fee', tone: tone);
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              _PreviewCard(storeId: active),
            ],
          ],
        );
      },
    );
  }
}

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({required this.storeId});
  final String storeId;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  String _province = 'Kigali City';
  String _district = 'Gasabo';
  String _method = 'STANDARD';
  final _subtotal = TextEditingController(text: '20000');
  Map<String, dynamic>? _result;
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _subtotal.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await jpost('/shipping/preview', {
        'province': _province,
        'district': _district,
        'subtotal': numOf(_subtotal.text),
        'method': _method,
        if (widget.storeId.isNotEmpty) 'storeId': widget.storeId,
      });
      if (mounted) setState(() => _result = r);
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
    final r = _result;
    return Section(
      title: 'Test an address',
      subtitle: 'What a buyer pays for delivery from this store',
      children: [
        FilterSelect(
          label: 'Province',
          value: _province,
          options: [for (final p in rwandaLocations.keys) (p, p)],
          onChanged:
              (v) => setState(() {
                _province = v;
                _district = rwandaLocations[v]!.first;
              }),
        ),
        const SizedBox(height: 10),
        FilterSelect(label: 'District', value: _district, options: [for (final d in rwandaLocations[_province]!) (d, d)], onChanged: (v) => setState(() => _district = v)),
        const SizedBox(height: 10),
        TextField(controller: _subtotal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order subtotal (RWF)')),
        const SizedBox(height: 10),
        FilterSelect(label: 'Method', value: _method, options: const [('STANDARD', 'Standard'), ('EXPRESS', 'Express'), ('PICKUP', 'Pickup')], onChanged: (v) => setState(() => _method = v)),
        const SizedBox(height: 10),
        OutlineBtn(label: 'Check delivery', loading: _busy, onPressed: _test),
        const SizedBox(height: 10),
        if (_error.isNotEmpty) Notice(text: _error),
        if (r != null)
          r['deliverable'] == true
              ? Notice(
                ok: true,
                text: numOf(r['fee']) == 0 ? 'Free delivery' : money(r['fee']),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tiny('${r['method'] != _method ? '${titleCase(_method)} not offered, ${titleCase(r['method']).toLowerCase()} used · ' : ''}${r['zoneName'] ?? ''} · ${r['eta'] ?? ''}'),
                    if (r['source'] != 'seller') const Tiny('You have no zones yet, so MVEC standard rates apply.'),
                  ],
                ),
              )
              : Notice(text: 'Not delivered', child: Tiny("No active zone covers ${asMap(r['address'])['district'] ?? _district}. Buyers there can't order from this store.")),
      ],
    );
  }
}

class _ZoneEditor extends StatefulWidget {
  const _ZoneEditor({this.zone, required this.storeId});
  final Map<String, dynamic>? zone;
  final String storeId;

  @override
  State<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<_ZoneEditor> {
  late final _z = widget.zone ?? const <String, dynamic>{};
  late final _name = TextEditingController(text: strOf(_z['name']));
  late final _fee = TextEditingController(text: _z['fee'] == null ? '' : '${numOf(_z['fee'])}');
  late final _eta = TextEditingController(text: strOf(_z['eta'], widget.zone == null ? '1–3 days' : ''));
  late final _free = TextEditingController(text: numOf(_z['freeOverAmount']) > 0 ? '${numOf(_z['freeOverAmount'])}' : '');
  late final _expressFee = TextEditingController(text: _z['expressFee'] == null ? '' : '${numOf(_z['expressFee'])}');
  late final _pickupFee = TextEditingController(text: '${numOf(_z['pickupFee'])}');
  late String _scope =
      (_z['districts'] is List && (_z['districts'] as List).isNotEmpty)
          ? 'DISTRICTS'
          : (_z['provinces'] is List && (_z['provinces'] as List).isNotEmpty) || widget.zone == null
          ? 'PROVINCES'
          : 'ALL';
  late final Set<String> _provinces = {for (final p in (_z['provinces'] is List ? _z['provinces'] as List : const [])) '$p'};
  late final Set<String> _districts = {for (final d in (_z['districts'] is List ? _z['districts'] as List : const [])) '$d'};
  late bool _express = _z['methods'] is List && (_z['methods'] as List).contains('EXPRESS');
  late bool _pickup = _z['methods'] is List && (_z['methods'] as List).contains('PICKUP');
  late String _status = strOf(_z['status'], 'ACTIVE');
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_name, _fee, _eta, _free, _expressFee, _pickupFee]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = '');
    if (_name.text.trim().isEmpty || _fee.text.trim().isEmpty) return setState(() => _error = 'Enter the zone name and the standard fee.');
    if (_scope == 'PROVINCES' && _provinces.isEmpty) return setState(() => _error = 'Select at least one province.');
    if (_scope == 'DISTRICTS' && _districts.isEmpty) return setState(() => _error = 'Select at least one district.');
    if (_express && _expressFee.text.isNotEmpty && numOf(_expressFee.text) < numOf(_fee.text)) return setState(() => _error = 'Express delivery should not cost less than standard.');
    final payload = {
      'name': _name.text.trim(),
      'provinces': _scope == 'PROVINCES' ? _provinces.toList() : <String>[],
      'districts': _scope == 'DISTRICTS' ? _districts.toList() : <String>[],
      'fee': numOf(_fee.text),
      'expressFee': _express && _expressFee.text.isNotEmpty ? numOf(_expressFee.text) : null,
      'pickupFee': _pickup ? numOf(_pickupFee.text) : 0,
      'methods': ['STANDARD', if (_express) 'EXPRESS', if (_pickup) 'PICKUP'],
      'freeOverAmount': numOf(_free.text),
      'eta': _eta.text.trim().isEmpty ? '1–3 days' : _eta.text.trim(),
      'status': _status,
      if (widget.zone == null && widget.storeId.isNotEmpty) 'storeId': widget.storeId,
    };
    setState(() => _busy = true);
    try {
      if (widget.zone == null) {
        await jpost('/shipping/zones', payload);
      } else {
        await jpatch('/shipping/zones/${widget.zone!['id']}', payload);
      }
      if (mounted) Navigator.of(context).pop(widget.zone == null ? 'Shipping zone added.' : 'Shipping zone saved.');
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
    Widget check(String label, bool on, VoidCallback tap) =>
        CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: on, title: Text(label), onChanged: (_) => tap());
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        title: Text(widget.zone == null ? 'Add shipping zone' : 'Edit shipping zone'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const Tiny('Buyers in these areas pay these fees for items from this store.'),
            if (_error.isNotEmpty) Notice(text: _error),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Zone name *', hintText: 'e.g. Kigali City')),
            const SizedBox(height: 14),
            const Text('Where you deliver', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ALL', label: Text('All Rwanda')),
                ButtonSegment(value: 'PROVINCES', label: Text('Provinces')),
                ButtonSegment(value: 'DISTRICTS', label: Text('Districts')),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            if (_scope == 'ALL') const Tiny('Used for any address not covered by a more specific province or district zone.'),
            if (_scope == 'PROVINCES')
              for (final p in rwandaLocations.keys) check(p, _provinces.contains(p), () => setState(() => _provinces.contains(p) ? _provinces.remove(p) : _provinces.add(p))),
            if (_scope == 'DISTRICTS')
              for (final p in rwandaLocations.keys)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('$p  ${rwandaLocations[p]!.where(_districts.contains).length}/${rwandaLocations[p]!.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  children: [
                    check(
                      'All of $p',
                      rwandaLocations[p]!.every(_districts.contains),
                      () => setState(() {
                        final all = rwandaLocations[p]!;
                        all.every(_districts.contains) ? _districts.removeAll(all) : _districts.addAll(all);
                      }),
                    ),
                    for (final dist in rwandaLocations[p]!) check(dist, _districts.contains(dist), () => setState(() => _districts.contains(dist) ? _districts.remove(dist) : _districts.add(dist))),
                  ],
                ),
            const SizedBox(height: 14),
            const Text('Fees', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(controller: _fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Standard fee (RWF) *')),
            const SizedBox(height: 10),
            TextField(controller: _eta, decoration: const InputDecoration(labelText: 'Delivery time', hintText: '1–3 days')),
            const SizedBox(height: 10),
            TextField(
              controller: _free,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Free standard delivery from (RWF)', hintText: 'No free delivery', helperText: 'Order subtotal from this store.'),
            ),
            const SizedBox(height: 10),
            FilterSelect(label: 'Status', value: _status, options: const [('ACTIVE', 'Active'), ('PAUSED', 'Paused')], onChanged: (v) => setState(() => _status = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Offer express delivery'), value: _express, onChanged: (v) => setState(() => _express = v)),
            if (_express) TextField(controller: _expressFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Express fee (RWF)', hintText: 'Same as standard')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Allow pickup'), value: _pickup, onChanged: (v) => setState(() => _pickup = v)),
            if (_pickup) TextField(controller: _pickupFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pickup fee (RWF)')),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10), child: GradientButton(label: widget.zone == null ? 'Add zone' : 'Save changes', loading: _busy, onPressed: _save)),
      ),
    );
  }
}

// ─── Reviews ─────────────────────────────────────────────────────────────────

String stars(num n) => '${'★' * n.clamp(0, 5).toInt()}${'☆' * (5 - n.clamp(0, 5).toInt())}';

/// `/vendor/reviews` (and the supplier's) — ratings and public replies.
class SellerReviewsPage extends StatefulWidget {
  const SellerReviewsPage({super.key, this.endpoint = '/reviews/vendor/mine', this.canReply = true, this.eyebrow = 'Seller platform'});
  final String endpoint;
  final bool canReply;
  final String eyebrow;

  @override
  State<SellerReviewsPage> createState() => _SellerReviewsPageState();
}

class _SellerReviewsPageState extends State<SellerReviewsPage> {
  late final _data = Loader(() => jlist(widget.endpoint, 'data'));
  String _tab = 'ALL';

  static final _tabs = <(String, String, bool Function(Map<String, dynamic>))>[
    ('ALL', 'All', (_) => true),
    ('AWAITING', 'Needs reply', (r) => strOf(r['vendorReply']).isEmpty),
    ('LOW', '1–2 stars', (r) => numOf(r['rating']) <= 2),
    ('MID', '3 stars', (r) => numOf(r['rating']) == 3),
    ('HIGH', '4–5 stars', (r) => numOf(r['rating']) >= 4),
  ];

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: widget.eyebrow,
      title: 'Reviews',
      subtitle: 'See what buyers say about your products and reply publicly. Your reply shows under the review on the product page and the buyer is notified. Moderation stays with MVEC.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (rows) {
            final total = rows.length;
            final avg = total == 0 ? 0 : rows.fold<num>(0, (s, r) => s + numOf(r['rating'])) / total;
            final dist = [
              for (final n in [5, 4, 3, 2, 1]) (n, rows.where((r) => numOf(r['rating']) == n).length),
            ];
            final replied = rows.where((r) => strOf(r['vendorReply']).isNotEmpty).length;
            final byProduct = <String, ({String name, int count, num sum, int low})>{};
            for (final r in rows) {
              final k = '${r['productId'] ?? r['product']}';
              final p = byProduct[k] ?? (name: strOf(r['product']), count: 0, sum: 0, low: 0);
              byProduct[k] = (name: p.name, count: p.count + 1, sum: p.sum + numOf(r['rating']), low: p.low + (numOf(r['rating']) <= 2 ? 1 : 0));
            }
            final products = byProduct.values.toList()..sort((a, b) => (a.sum / a.count).compareTo(b.sum / b.count));
            final filter = _tabs.firstWhere((t) => t.$1 == _tab).$3;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Average rating', value: total > 0 ? '${avg.toStringAsFixed(1)} / 5' : '—', icon: 'heart', sub: '$total reviews'),
                    MetricCard(label: 'Awaiting reply', value: '${total - replied}', icon: 'bell', sub: 'Reviews without your response'),
                    MetricCard(label: 'Reply rate', value: '${total == 0 ? 0 : (replied / total * 100).round()}%', icon: 'users', sub: 'Buyers see your replies on the product page'),
                    MetricCard(label: 'Low ratings', value: '${dist[3].$2 + dist[4].$2}', icon: 'shield', sub: '1–2 star reviews'),
                  ],
                ),
                const SizedBox(height: 14),
                if (total > 0) ...[
                  Section(title: 'Rating breakdown', subtitle: 'All your products', children: [for (final (n, c) in dist) ProgressRow(label: '$n ★', fraction: c / total, value: '$c')]),
                  Section(
                    title: 'By product',
                    subtitle: 'Lowest rated first',
                    children: [
                      for (final p in products.take(5))
                        RecordCard(title: p.name, subtitle: '${p.count} review${p.count == 1 ? '' : 's'}${p.low > 0 ? ' · ${p.low} low' : ''}', amount: '${(p.sum / p.count).toStringAsFixed(1)} ★'),
                    ],
                  ),
                ],
                TabChips(tabs: [for (final t in _tabs) (t.$1, t.$2)], value: _tab, counts: {for (final t in _tabs) t.$1: rows.where(t.$3).length}, onChanged: (v) => setState(() => _tab = v)),
                Paged<Map<String, dynamic>>(
                  items: rows.where(filter).toList(),
                  empty: const EmptyState(icon: Icons.star_outline_rounded, title: 'No reviews here', message: 'They appear once buyers rate your products.'),
                  itemBuilder:
                      (r) => RecordCard(
                        title: strOf(r['product']),
                        subtitle: '${strOf(r['reviewer'], 'Buyer')}${r['isVerifiedPurchase'] == true ? ' · Verified purchase' : ''} · ${formatDate(r['date'])}',
                        lines: [stars(numOf(r['rating'])), strOf(r['comment'], '—'), if (strOf(r['vendorReply']).isNotEmpty) 'Your reply: ${r['vendorReply']}'],
                        actions: [
                          if (widget.canReply)
                            ActionChipBtn(
                              strOf(r['vendorReply']).isEmpty ? 'Reply' : 'Edit reply',
                              onPressed: () async {
                                final ok = await showFormSheet<bool>(
                                  context,
                                  title: 'Reply to review',
                                  subtitle: '${strOf(r['reviewer'], 'Buyer')} on ${r['product']}: “${r['comment'] ?? ''}”',
                                  fields: const [FieldSpec('reply', 'Your public reply', type: FieldType.textarea, required: true, lines: 4)],
                                  initial: {'reply': strOf(r['vendorReply'])},
                                  submitLabel: 'Post reply',
                                  onSubmit: (v) async {
                                    await jpost('/reviews/${r['id']}/reply', {'reply': v['reply']});
                                    return true;
                                  },
                                );
                                if (ok == true && context.mounted) {
                                  toast(context, 'Reply posted.');
                                  _data.reload();
                                }
                              },
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

// ─── Analytics & Reports ─────────────────────────────────────────────────────

const _channels = [('AFFILIATE', 'Affiliate referral'), ('COUPON', 'Coupon code'), ('MANUAL', 'Manual order'), ('ONLINE', 'Direct online')];
String _channelOf(Map<String, dynamic> o) =>
    strOf(o['affiliateCode']).isNotEmpty
        ? 'AFFILIATE'
        : strOf(asMap(o['coupon'])['code']).isNotEmpty
        ? 'COUPON'
        : o['source'] == 'MANUAL'
        ? 'MANUAL'
        : 'ONLINE';

Future<({List<Map<String, dynamic>> orders, List<Map<String, dynamic>> products, double commission})> _vendorData() async {
  final r = await Future.wait<dynamic>([
    jlist('/orders/vendor/orders', 'orders'),
    vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
    jget('/payouts/balance').catchError((_) => <String, dynamic>{}),
  ]);
  return (orders: r[0] as List<Map<String, dynamic>>, products: r[1] as List<Map<String, dynamic>>, commission: parsePercent((r[2] as Map)['commissionRate']));
}

/// `/vendor/analytics` — sales, channels, growth spend and top products.
class SellerAnalyticsPage extends StatefulWidget {
  const SellerAnalyticsPage({super.key});

  @override
  State<SellerAnalyticsPage> createState() => _SellerAnalyticsPageState();
}

class _SellerAnalyticsPageState extends State<SellerAnalyticsPage> {
  late final _data = Loader(() async {
    final r = await Future.wait<dynamic>([_vendorData(), jlist('/vendor/advertisements', 'data').catchError((_) => <Map<String, dynamic>>[])]);
    return (vendor: r[0] as ({List<Map<String, dynamic>> orders, List<Map<String, dynamic>> products, double commission}), ads: r[1] as List<Map<String, dynamic>>);
  });

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      feature: 'advancedAnalytics',
      title: 'Advanced analytics',
      child: PortalPage(
        eyebrow: 'Seller platform',
        title: 'Analytics',
        subtitle: 'Sales performance across your orders and catalog.',
        onRefresh: _data.reload,
        children: [
          LoadView(
            loader: _data,
            builder: (d) {
              final v = d.vendor;
              final stats = summarizeOrders(v.orders, v.commission);
              final counted = v.orders.where(isRevenueOrder).toList();
              final totalSales = counted.fold<num>(0, (s, o) => s + numOf(o['vendorSubtotal']));
              final low = v.products.where((p) => numOf(p['stockQuantity']) <= numOf(p['lowStockThreshold'], 5)).length;
              final discount = counted.fold<num>(0, (s, o) => s + numOf(o['vendorDiscount']));
              final adSpend = d.ads.fold<num>(0, (s, a) => s + numOf(a['spent']));
              final adClicks = d.ads.fold<num>(0, (s, a) => s + numOf(a['clicks']));
              final liveAds = d.ads.where((a) => a['statusKey'] == 'ACTIVE').length;
              final byStatus = stats.byStatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      MetricCard(label: 'Gross sales', value: money(stats.gross), icon: 'chart', sub: '${stats.countedOrders} orders'),
                      MetricCard(label: 'Average order', value: money(stats.averageOrder), icon: 'cart', sub: 'Your items per order'),
                      MetricCard(label: 'Customers', value: '${stats.customers}', icon: 'users', sub: 'Unique buyers'),
                      MetricCard(label: 'Active products', value: '${v.products.where((p) => p['status'] == 'ACTIVE').length}', icon: 'box', sub: '$low low on stock'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Section(title: 'Revenue', subtitle: 'Last 6 months, excluding cancelled orders', children: [MiniBars(data: monthlyRevenue(v.orders))]),
                  Section(
                    title: 'Orders by status',
                    subtitle: '${stats.orders} total',
                    children: [
                      if (byStatus.isEmpty) const Tiny('No orders yet.'),
                      for (final e in byStatus) ProgressRow(label: titleCase(e.key), fraction: e.value / stats.orders, value: '${e.value}'),
                    ],
                  ),
                  Section(
                    title: 'Sales by channel',
                    subtitle: 'Where your orders come from',
                    children: [
                      for (final (k, label) in _channels)
                        Builder(
                          builder: (_) {
                            final list = counted.where((o) => _channelOf(o) == k).toList();
                            final sales = list.fold<num>(0, (s, o) => s + numOf(o['vendorSubtotal']));
                            final share = totalSales == 0 ? 0.0 : sales / totalSales;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [ProgressRow(label: label, fraction: share.toDouble(), value: '${(share * 100).round()}%'), Tiny('${money(sales)} · ${list.length} orders')],
                            );
                          },
                        ),
                    ],
                  ),
                  Section(
                    title: 'Growth spend',
                    subtitle: 'What marketing cost you',
                    trailing: TextButton(onPressed: () => context.go('/vendor/advertisements'), child: const Text('Ads')),
                    children: [
                      RecordCard(title: 'Coupon discounts', subtitle: 'Given on your items', amount: money(discount)),
                      RecordCard(title: 'Ad spend', subtitle: '${compact(adClicks)} clicks · $liveAds live campaign${liveAds == 1 ? '' : 's'}', amount: money(adSpend)),
                      RecordCard(title: 'Affiliate commission', subtitle: 'Paid by MVEC, not you', amount: money(0)),
                    ],
                  ),
                  Section(
                    title: 'Top products',
                    subtitle: 'By revenue',
                    trailing: TextButton(onPressed: () => context.go('/vendor/products'), child: const Text('Manage')),
                    children: [
                      if (stats.topProducts.isEmpty) const Tiny('Sales by product will appear after your first order.'),
                      for (final p in stats.topProducts.take(6)) RecordCard(title: p.name, subtitle: '${p.units} units sold', amount: money(p.revenue)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

const _reportRanges = [('7', 'Last 7 days'), ('30', 'Last 30 days'), ('90', 'Last 90 days'), ('365', 'Last 12 months'), ('all', 'All time')];

/// `/vendor/reports` — sales summary for a period with the order list.
class SellerReportsPage extends StatefulWidget {
  const SellerReportsPage({super.key});

  @override
  State<SellerReportsPage> createState() => _SellerReportsPageState();
}

class _SellerReportsPageState extends State<SellerReportsPage> {
  late final _data = Loader(_vendorData);
  String _range = '30';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      feature: 'advancedAnalytics',
      title: 'Advanced reports',
      child: PortalPage(
        eyebrow: 'Seller platform',
        title: 'Reports',
        subtitle: 'Sales summary for a chosen period, with every order in it.',
        onRefresh: _data.reload,
        action: FilterSelect(label: 'Report period', value: _range, options: _reportRanges, onChanged: (v) => setState(() => _range = v)),
        children: [
          LoadView(
            loader: _data,
            builder: (d) {
              final since = _range == 'all' ? null : DateTime.now().subtract(Duration(days: int.parse(_range)));
              final orders = since == null ? d.orders : d.orders.where((o) => (parseDate(o['createdAt']) ?? DateTime(2000)).isAfter(since)).toList();
              final s = summarizeOrders(orders, d.commission);
              final shown = orders.where((o) => matches(_q, [o['orderNumber'], personName(o['user'])])).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MetricGrid(
                    children: [
                      MetricCard(label: 'Gross sales', value: money(s.gross), icon: 'chart', sub: '${s.countedOrders} orders'),
                      MetricCard(label: 'Paid sales', value: money(s.paidGross), icon: 'wallet', sub: '${s.paidOrders} paid orders'),
                      MetricCard(label: 'Platform fee (${d.commission.toStringAsFixed(d.commission % 1 == 0 ? 0 : 1)}%)', value: money(s.commission), icon: 'tag', sub: 'On paid sales'),
                      MetricCard(label: 'Net earnings', value: money(s.net), icon: 'check', sub: 'Paid sales after fee'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SearchBox(hint: 'Search orders…', onChanged: (v) => setState(() => _q = v)),
                  Paged<Map<String, dynamic>>(
                    items: shown,
                    empty: const EmptyState(title: 'No orders in this period.'),
                    itemBuilder:
                        (o) => RecordCard(
                          title: strOf(o['orderNumber']),
                          subtitle: '${personName(o['user'])} · ${formatDate(o['createdAt'])}',
                          lines: ['Payment: ${titleCase(o['paymentStatus'])}'],
                          amount: money(o['vendorSubtotal']),
                          status: Pill(o['orderStatus']),
                          onTap: () => context.push('/vendor/orders/${idOf(o)}'),
                        ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Customers ───────────────────────────────────────────────────────────────

String? _waLink(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final intl =
      digits.startsWith('250')
          ? digits
          : digits.startsWith('0')
          ? '25$digits'
          : digits;
  return intl.isEmpty ? null : 'https://wa.me/$intl';
}

/// `/vendor/customers` — everyone who bought from the seller.
class SellerCustomersPage extends StatefulWidget {
  const SellerCustomersPage({super.key});

  @override
  State<SellerCustomersPage> createState() => _SellerCustomersPageState();
}

class _SellerCustomersPageState extends State<SellerCustomersPage> {
  late final _data = Loader(() => jlist('/users/vendor/customers', 'data'));
  String _type = '';
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _open(Map<String, dynamic> c) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, builder: (_) => _CustomerSheet(customerKey: strOf(c['key'] ?? c['id'])));
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'Seller platform',
      title: 'Customers',
      subtitle: 'Everyone who bought from you: MVEC buyers and the guest customers from your manual orders.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (all) {
            final repeat = all.where((c) => numOf(c['orders']) > 1).length;
            final orders = all.fold<num>(0, (s, c) => s + numOf(c['orders']));
            final spent = all.fold<num>(0, (s, c) => s + numOf(c['totalSpent']));
            final top = all.firstOrNull;
            final rows = all.where((c) => (_type.isEmpty || (_type == 'guest' ? c['guest'] == true : c['guest'] != true)) && matches(_q, [c['name'], c['phone'], c['email'], c['city']])).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Customers', value: '${all.length}', icon: 'users', sub: '${all.where((c) => c['guest'] == true).length} guests'),
                    MetricCard(label: 'Repeat customers', value: '$repeat', icon: 'heart', sub: all.isEmpty ? 'No customers yet' : '${(repeat / all.length * 100).round()}% bought again'),
                    MetricCard(label: 'Average order', value: money(orders == 0 ? 0 : spent / orders), icon: 'cart', sub: 'Your items per order'),
                    MetricCard(label: 'Top customer', value: top == null ? '—' : money(top['totalSpent']), icon: 'wallet', sub: strOf(top?['name'])),
                  ],
                ),
                const SizedBox(height: 14),
                if (all.isEmpty)
                  const EmptyState(icon: Icons.group_outlined, title: 'No customers yet', message: 'Customers appear here after their first order with you.')
                else ...[
                  SearchBox(hint: 'Search name, phone, email or city…', onChanged: (v) => setState(() => _q = v)),
                  FilterSelect(
                    label: 'Customer type',
                    value: _type,
                    options: const [('', 'All customers'), ('buyer', 'MVEC buyers'), ('guest', 'Guests')],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  const SizedBox(height: 12),
                  Paged<Map<String, dynamic>>(
                    items: rows,
                    empty: const Tiny('No customers match.'),
                    itemBuilder:
                        (c) => RecordCard(
                          title: strOf(c['name']),
                          subtitle: strOf(c['phone'] ?? c['email']),
                          lines: [
                            '${c['city'] ?? '—'} · ${numOf(c['orders']).toInt()} orders${numOf(c['cancelledOrders']) > 0 ? ' (${c['cancelledOrders']} cancelled)' : ''}',
                            'Last purchase ${formatDate(c['lastPurchase'])}',
                          ],
                          amount: money(c['totalSpent']),
                          status: StatusChip(c['guest'] == true ? 'Guest' : 'Buyer', tone: c['guest'] == true ? StatusTone.warn : StatusTone.good),
                          onTap: () => _open(c),
                        ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CustomerSheet extends StatefulWidget {
  const _CustomerSheet({required this.customerKey});
  final String customerKey;

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  late final _data = Loader(() => jget('/users/vendor/customers/${Uri.encodeComponent(widget.customerKey)}'));
  bool _messaging = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: LoadView(
        loader: _data,
        builder: (d) {
          final c = asMap(d['customer']);
          final phone = strOf(c['phone']);
          final email = strOf(c['email']);
          final wa = phone.isEmpty ? null : _waLink(phone);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Avatar(name: strOf(c['name'], '?'), radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(strOf(c['name']), style: context.mvH1.copyWith(fontSize: 18)),
                        Tiny('${c['guest'] == true ? 'Guest customer (no MVEC account)' : 'MVEC buyer'}${strOf(c['city']).isNotEmpty ? ' · ${c['city']}' : ''}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (phone.isNotEmpty) ActionChipBtn(phone, icon: Icons.call_outlined, onPressed: () => launchUrl(Uri.parse('tel:$phone'))),
                  if (email.isNotEmpty) ActionChipBtn(email, icon: Icons.mail_outline_rounded, onPressed: () => launchUrl(Uri.parse('mailto:$email'))),
                  if (wa != null) ActionChipBtn('WhatsApp', icon: Icons.chat_outlined, onPressed: () => launchUrl(Uri.parse(wa), mode: LaunchMode.externalApplication)),
                ],
              ),
              const SizedBox(height: 12),
              MetricGrid(
                children: [
                  MetricCard(label: 'Orders', value: '${numOf(c['orders']).toInt()}', icon: 'cart'),
                  MetricCard(label: 'Total spent', value: money(c['totalSpent']), icon: 'wallet'),
                  MetricCard(label: 'Average order', value: money(c['averageOrder']), icon: 'chart'),
                  MetricCard(label: 'Customer since', value: formatDate(c['firstPurchase']), icon: 'users'),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Order history', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final o in asMaps(d['orders']))
                RecordCard(
                  title: strOf(o['orderNumber']),
                  badges: [if (o['source'] == 'MANUAL') const StatusChip('Manual')],
                  subtitle: '${formatDate(o['createdAt'])} · ${asMaps(o['items']).map((i) => '${i['quantity']}× ${i['name']}').join(', ')}',
                  amount: money(numOf(o['subtotal']) + numOf(o['delivery'])),
                  status: Pill(o['orderStatus']),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/vendor/orders/${idOf(o)}');
                  },
                ),
              if (c['guest'] != true) ...[
                const SizedBox(height: 8),
                GradientButton(
                  label: 'Message customer',
                  icon: Icons.chat_bubble_outline_rounded,
                  loading: _messaging,
                  onPressed: () async {
                    setState(() => _messaging = true);
                    try {
                      await jpost('/conversations', {'recipientId': idOf(c)});
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        context.go('/vendor/messages');
                      }
                    } catch (e) {
                      if (context.mounted) toast(context, errorText(e), error: true);
                      if (mounted) setState(() => _messaging = false);
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Categories ──────────────────────────────────────────────────────────────

/// `/vendor/categories` — marketplace categories and how many of the
/// seller's products are in each.
class SellerCategoriesPage extends StatefulWidget {
  const SellerCategoriesPage({super.key});

  @override
  State<SellerCategoriesPage> createState() => _SellerCategoriesPageState();
}

class _SellerCategoriesPageState extends State<SellerCategoriesPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jlist('/categories', 'categories', {'withCounts': true}),
      vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (categories: r[0], products: r[1]);
  });
  String _q = '';
  final _open = <String>{};

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _add(String parentId, List<CategoryNode> tree) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: parentId.isEmpty ? 'Add category' : 'Add subcategory',
      subtitle: 'New categories are available to every seller right away. If it already exists, the existing one is used.',
      fields: [
        const FieldSpec('name', 'Category name', required: true, hint: 'e.g. Smartphones'),
        FieldSpec('parentId', 'Parent category', type: FieldType.select, placeholderOption: 'None (top-level category)', options: [for (final r in tree) (r.id, r.name)]),
        const FieldSpec('description', 'Description', type: FieldType.textarea, hint: 'Optional: what belongs in this category'),
      ],
      initial: {'parentId': parentId},
      submitLabel: 'Add category',
      onSubmit:
          (v) => jpost('/categories', {
            'name': v['name'],
            'parentId': '${v['parentId'] ?? ''}'.isEmpty ? null : v['parentId'],
            if ('${v['description'] ?? ''}'.isNotEmpty) 'description': v['description'],
          }),
    );
    if (res == null || !mounted) return;
    toast(context, res['alreadyExisted'] == true ? strOf(res['message']) : 'Category “${asMap(res['category'])['name']}” added.');
    _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final mine = <String, int>{};
        for (final p in d.products) {
          final k = idOf(p['category']);
          mine[k] = (mine[k] ?? 0) + 1;
        }
        final known = d.categories.map(idOf).toSet();
        final orphaned = d.products.where((p) => !known.contains(idOf(p['category']))).length;
        final tree = buildCategoryTree(d.categories);
        int mineOf(CategoryNode n) => (mine[n.id] ?? 0) + n.children.fold<int>(0, (s, c) => s + (mine[c.id] ?? 0));
        int marketOf(CategoryNode n) => numOf(n.data['productCount']).toInt() + n.children.fold<int>(0, (s, c) => s + numOf(c.data['productCount']).toInt());
        final shown = [
          for (final r in tree)
            if (matches(_q, [r.name]) || r.children.any((c) => matches(_q, [c.name]))) r,
        ];
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Categories',
          subtitle: 'Marketplace categories your products can be listed in. Categories are shared across MVEC; editing and removing them is handled by MVEC admins.',
          onRefresh: _data.reload,
          action: GradientButton(label: 'Add category', icon: Icons.add_rounded, compact: true, onPressed: () => _add('', tree)),
          children: [
            MetricGrid(
              children: [
                MetricCard(label: 'Marketplace categories', value: '${d.categories.length}', icon: 'tag', sub: '${tree.length} top-level'),
                MetricCard(label: 'You sell in', value: '${mine.keys.where(known.contains).length}', icon: 'shop', sub: 'of ${d.categories.length} categories'),
                MetricCard(label: 'Need a category', value: '$orphaned', icon: 'bell', sub: orphaned > 0 ? 'Products in a disabled category' : 'All products categorized'),
              ],
            ),
            const SizedBox(height: 14),
            SearchBox(hint: 'Search categories and subcategories', onChanged: (v) => setState(() => _q = v)),
            if (tree.isEmpty) const EmptyState(icon: Icons.sell_outlined, title: 'No categories yet', message: 'Add the first category for your products.'),
            if (tree.isNotEmpty && shown.isEmpty) Tiny('No categories match “$_q”.'),
            for (final r in shown)
              DataCard(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: r.children.isEmpty ? null : () => setState(() => _open.contains(r.id) ? _open.remove(r.id) : _open.add(r.id)),
                      leading: Icon(r.children.isEmpty ? Icons.sell_outlined : (_open.contains(r.id) || _q.isNotEmpty ? Icons.expand_less_rounded : Icons.expand_more_rounded)),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Yours ${mineOf(r)} · On MVEC ${marketOf(r)}${r.children.isNotEmpty ? ' · ${r.children.length} sub' : ''}', style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (mineOf(r) > 0)
                            IconButton(tooltip: 'View products', icon: const Icon(Icons.visibility_outlined, size: 20), onPressed: () => context.go('/vendor/products?category=${r.id}')),
                          IconButton(tooltip: 'Add a subcategory to ${r.name}', icon: const Icon(Icons.add_rounded, size: 20), onPressed: () => _add(r.id, tree)),
                        ],
                      ),
                    ),
                    if (_open.contains(r.id) || _q.isNotEmpty)
                      for (final c in r.children.where((c) => _q.isEmpty || matches(_q, [c.name]) || matches(_q, [r.name])))
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 40),
                          title: Text(c.name),
                          subtitle: Text('Yours ${mine[c.id] ?? 0} · On MVEC ${numOf(c.data['productCount']).toInt()}'),
                          trailing:
                              (mine[c.id] ?? 0) > 0
                                  ? IconButton(tooltip: 'View products', icon: const Icon(Icons.visibility_outlined, size: 20), onPressed: () => context.go('/vendor/products?category=${c.id}'))
                                  : null,
                        ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shown for a staff role that may not use the dashboard section.
class StaffGate extends ConsumerWidget {
  const StaffGate({super.key, required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((a) => a.user));
    if (staffCan(user, path)) return child;
    return EmptyState(
      icon: Icons.shield_outlined,
      title: "You don't have access to this page",
      message: "Your role (${staffRoleLabel[user?.staffRole] ?? 'Staff'}) doesn't include it. Ask the store owner if you need access.",
      action: OutlineBtn(label: 'Back to dashboard', compact: true, onPressed: () => context.go('/vendor')),
    );
  }
}

/// Small helper so pages can show the theme accent without importing theme.
Color accentOf(BuildContext context) => context.mv.accentDeep;
const kMvBlue = MvColors.skyBlue;
