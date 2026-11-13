import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

const roleLabel = {'super_admin': 'Admin', 'delivery': 'Courier', 'vendor': 'Seller', 'supplier': 'Supplier', 'affiliate': 'Affiliate', 'buyer': 'Buyer', 'developer': 'Developer'};

/// One of the admin record lists: `users`, `products`, `categories`, `orders`.
class AdminRecordsPage extends ConsumerStatefulWidget {
  const AdminRecordsPage({super.key, required this.type});
  final String type;

  @override
  ConsumerState<AdminRecordsPage> createState() => _AdminRecordsPageState();
}

class _AdminRecordsPageState extends ConsumerState<AdminRecordsPage> {
  int _page = 1;
  String _role = '';
  String _q = '';
  String _busy = '';
  late Loader<({List<Map<String, dynamic>> list, int total})> _data = _load();

  Loader<({List<Map<String, dynamic>> list, int total})> _load() => Loader(() async {
    if (widget.type == 'categories') {
      final c = await jlist('/categories', 'categories');
      return (list: c, total: c.length);
    }
    final path = {'users': '/users', 'products': '/admin/products', 'orders': '/admin/orders'}[widget.type]!;
    final res = await jget(path, {'page': _page, 'pageSize': 20, 'limit': 20, if (widget.type == 'users' && _role.isNotEmpty) 'role': _role});
    final list = asMaps(res['data'] ?? asMap(res['users'])['data']);
    return (list: list, total: numOf(asMap(res['meta'])['total'], list.length).toInt());
  });

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

  String get _title => const {'users': 'Users', 'products': 'Products', 'categories': 'Categories', 'orders': 'Orders'}[widget.type]!;

  Future<void> _patchUser(Map<String, dynamic> u, Map<String, dynamic> body, String confirm) async {
    if (!await confirmDialog(context, confirm)) return;
    if (!mounted) return;
    setState(() => _busy = idOf(u));
    final ok = await runAction(context, () => jpatch('/users/${idOf(u)}', body), success: 'Updated.');
    if (mounted) setState(() => _busy = '');
    if (ok) _reload();
  }

  /// Adds a courier or an admin as a brand-new account. They choose their own
  /// password from the welcome email ("Forgot password"), so no admin knows it.
  Future<void> _addTeamAccount({required bool admin}) async {
    final message = await showFormSheet<String>(
      context,
      title: admin ? 'Add an admin' : 'Add a courier',
      subtitle: admin
          ? 'Admins can see and change everything on Ikiguzi. Only add Ikiguzi staff, with their work email. This creates a new account; they choose their password from the email we send.'
          : 'Couriers deliver paid orders and confirm them with the buyer\'s code. This creates a new account for the delivery partner; they choose their password from the email we send.',
      submitLabel: admin ? 'Add admin' : 'Add courier',
      fields: [
        const FieldSpec('fullName', 'Full name', required: true),
        const FieldSpec('email', 'Email', type: FieldType.email, required: true, hint: 'name@example.com'),
        const FieldSpec('phone', 'Phone number', type: FieldType.phone, required: true, hint: '0788 123 456'),
        if (admin) const FieldSpec('currentPassword', 'Your password (to confirm)', type: FieldType.password, required: true),
      ],
      onSubmit: (v) async {
        final res = await jpost(admin ? '/users/admins' : '/users/couriers', v);
        return strOf(res['message'], 'Added.');
      },
    );
    if (message == null || !mounted) return;
    toast(context, message);
    _reload();
  }

  /// Removes or restores an admin's access, confirmed with your own password.
  Future<void> _adminAccess(Map<String, dynamic> x, String name, {required bool restore}) async {
    final message = await showFormSheet<String>(
      context,
      title: restore ? 'Restore admin access' : 'Remove admin access',
      subtitle: restore ? '$name will be able to sign in and manage Ikiguzi again.' : '$name will no longer be able to sign in. Everything they did stays in the activity log.',
      submitLabel: restore ? 'Restore access' : 'Remove access',
      danger: !restore,
      fields: const [FieldSpec('currentPassword', 'Your password (to confirm)', type: FieldType.password, required: true)],
      onSubmit: (v) async {
        final res = await jpost('/users/${idOf(x)}/admin-access', {'active': restore, 'currentPassword': v['currentPassword']});
        return strOf(res['message'], 'Saved.');
      },
    );
    if (message == null || !mounted) return;
    toast(context, message);
    _reload();
  }

  void _view(Map<String, String> record) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (ctx) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${_title.substring(0, _title.length - 1)} record', style: ctx.mvH1.copyWith(fontSize: 18)),
                const SizedBox(height: 8),
                for (final e in record.entries) KV(e.key, e.value),
              ],
            ),
          ),
    );
  }

  Widget _row(Map<String, dynamic> x, String? me) {
    switch (widget.type) {
      case 'users':
        final raw = strOf(x['status'], 'ACTIVE').toUpperCase();
        final status =
            ['BLOCK', 'BLOCKED'].contains(raw)
                ? 'Blocked'
                : ['SUSPEND', 'SUSPENDED'].contains(raw)
                ? 'Suspended'
                : raw == 'INVESTIGATE'
                ? 'Investigate'
                : 'Active';
        final name = strOf(x['name'] ?? x['fullName'] ?? x['Fullname'], 'Unnamed user');
        final role = strOf(x['role']);
        final busy = _busy == idOf(x);
        return RecordCard(
          title: name,
          subtitle: '${strOf(x['email'], '—')} · ${roleLabel[role] ?? titleCase(role)}',
          status: StatusChip(status, tone: status == 'Active' ? StatusTone.good : StatusTone.warn),
          actions: [
            if (role == 'super_admin' && idOf(x) != me)
              ActionChipBtn(
                status == 'Blocked' ? 'Restore admin access' : 'Remove admin access',
                danger: status != 'Blocked',
                busy: busy,
                onPressed: () => _adminAccess(x, name, restore: status == 'Blocked'),
              ),
            if (role != 'super_admin')
              ActionChipBtn(
                status == 'Active' ? 'Block' : 'Unblock',
                danger: status == 'Active',
                busy: busy,
                onPressed: () {
                  final next = status == 'Active' ? 'BLOCK' : 'ACTIVE';
                  _patchUser(x, {'status': next}, next == 'BLOCK' ? 'Block $name? They will not be able to log in.' : 'Unblock $name?');
                },
              ),
            ActionChipBtn(
              'View',
              icon: Icons.visibility_outlined,
              onPressed:
                  () =>
                      _view({'Name': name, 'Email': strOf(x['email'], '—'), 'Phone': strOf(x['phone'], '—'), 'Role': roleLabel[role] ?? role, 'Status': status, 'Joined': formatDate(x['createdAt'])}),
            ),
          ],
        );
      case 'products':
        final vendor = strOf(asMap(x['vendor'])['companyName'] ?? asMap(x['vendor'])['fullName'] ?? asMap(x['vendor'])['Fullname'], 'Unknown vendor');
        return RecordCard(
          leading: ProductImage(src: strOf(asMap(x['media'])['mainImage']), size: 46, radius: 8),
          title: strOf(x['name']),
          subtitle: vendor,
          lines: ['Stock ${numOf(x['stockQuantity']).toInt()}'],
          amount: money(x['price']),
          status: Pill(x['status']),
          onTap: () => context.push('/product/${idOf(x)}'),
        );
      case 'categories':
        final products = numOf(x['productCount'] ?? asMap(x['_count'])['products']).toInt();
        final active = x['active'] != false;
        return RecordCard(
          title: strOf(x['name']),
          subtitle: '$products product${products == 1 ? '' : 's'}',
          status: StatusChip(active ? 'Active' : 'Inactive', tone: active ? StatusTone.good : StatusTone.warn),
          actions: [
            if (active)
              ActionChipBtn(
                'Delete',
                danger: true,
                busy: _busy == idOf(x),
                onPressed: () async {
                  if (products > 0) {
                    toast(context, 'Cannot delete "${x['name']}": it has $products product(s). Reassign or remove them first.', error: true);
                    return;
                  }
                  if (!await confirmDialog(context, 'Delete category "${x['name']}"? It is set as inactive.', confirm: 'Delete', danger: true)) return;
                  if (!mounted) return;
                  setState(() => _busy = idOf(x));
                  final ok = await runAction(context, () => jdelete('/categories/${idOf(x)}'));
                  if (mounted) setState(() => _busy = '');
                  if (ok) _reload();
                },
              ),
          ],
        );
      default:
        final items = asMaps(x['items']);
        final vendor =
            items.isEmpty
                ? 'Multiple vendors'
                : strOf(asMap(items.first['vendor'])['companyName'] ?? asMap(items.first['vendor'])['fullName'] ?? asMap(items.first['vendor'])['Fullname'], 'Multiple vendors');
        return RecordCard(
          title: strOf(x['orderNumber']),
          subtitle: '${personName(x['user'], 'Unknown buyer')} · $vendor',
          lines: ['Payment: ${titleCase(x['paymentStatus'])} · ${formatDate(x['createdAt'])}'],
          amount: money(x['totalAmount']),
          status: Pill(x['orderStatus']),
          onTap: () => context.push('/admin/orders/${idOf(x)}'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider.select((a) => a.user?.id));
    return PortalPage(
      eyebrow: 'Super admin',
      title: _title,
      subtitle: 'Manage marketplace records and platform operations.',
      onRefresh: () async => _reload(),
      children: [
        if (widget.type == 'users')
          InfoBox(
            title: 'Who gets which role',
            text: 'Buyers sign up or check out as guests. Sellers, suppliers and affiliates choose their role when they sign up, and Ikiguzi verifies sellers and suppliers on their own pages. Couriers and admins are added here as new accounts — a shopper\'s account is never turned into one, and roles are never switched.',
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GradientButton(label: 'Add courier', icon: Icons.delivery_dining_outlined, compact: true, onPressed: () => _addTeamAccount(admin: false)),
                  OutlineBtn(label: 'Add admin', icon: Icons.admin_panel_settings_outlined, compact: true, onPressed: () => _addTeamAccount(admin: true)),
                ],
              ),
            ),
          )
        else
          const InfoBox(title: 'Live marketplace data', text: 'This list is read directly from the Ikiguzi database. User actions update the account record and take effect across the marketplace.'),
        if (widget.type == 'users')
          FilterSelect(
            label: 'Filter by role',
            value: _role,
            options: const [
              ('', 'All roles'),
              ('buyer', 'Buyers'),
              ('vendor', 'Vendors'),
              ('affiliate', 'Affiliates'),
              ('supplier', 'Suppliers'),
              ('super_admin', 'Administrators'),
              ('delivery', 'Couriers'),
              ('developer', 'Developers'),
            ],
            onChanged: (v) {
              _role = v;
              _page = 1;
              _reload();
            },
          ),
        const SizedBox(height: 12),
        SearchBox(hint: 'Search ${_title.toLowerCase()} on this page…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder: (d) {
            final shown = d.list.where((x) => matches(_q, [x['name'], x['fullName'], x['Fullname'], x['email'], x['orderNumber'], x['phone']])).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tiny('${d.total} record${d.total == 1 ? '' : 's'}'),
                if (shown.isEmpty) EmptyState(title: 'No ${_title.toLowerCase()} here'),
                for (final x in shown) _row(x, me),
                if (widget.type != 'categories' && d.total > 20)
                  PaginationBar(
                    page: _page,
                    total: d.total,
                    perPage: 20,
                    onPage: (p) {
                      _page = p;
                      _reload();
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

// ─── Verification (sellers and suppliers) ───────────────────────────────────
