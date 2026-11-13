import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/nav_items.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

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
