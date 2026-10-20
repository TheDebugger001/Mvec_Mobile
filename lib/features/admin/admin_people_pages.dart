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
import '../wholesale/wholesale_pages.dart' show partyName;

// Admin: overview, people, catalog and supplier work (web: AdminDashboard.jsx
// and the first half of AdminOps.jsx).

const roleLabel = {'super_admin': 'Admin', 'delivery': 'Courier', 'vendor': 'Seller', 'supplier': 'Supplier', 'affiliate': 'Affiliate', 'buyer': 'Buyer', 'developer': 'Developer'};

String _greeting() {
  final h = DateTime.now().toUtc().add(const Duration(hours: 2)).hour; // Kigali time
  return h < 12
      ? 'Good morning'
      : h < 18
      ? 'Good afternoon'
      : 'Good evening';
}

/// "Needs your attention" queue, refreshed every minute (`AttentionQueue`).
class AttentionQueue extends StatefulWidget {
  const AttentionQueue({super.key});

  @override
  State<AttentionQueue> createState() => _AttentionQueueState();
}

class _AttentionQueueState extends State<AttentionQueue> {
  late final _data = Loader(() => jget('/admin/attention'));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _data.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _data,
      builder: (context, _) {
        final d = _data.data;
        final items = asMaps(d?['items']).where((i) => numOf(i['count']) > 0).toList();
        final total = numOf(d?['total']).toInt();
        return Section(
          title: 'Needs your attention',
          subtitle:
              d == null
                  ? 'Checking…'
                  : items.isNotEmpty
                  ? '$total thing${total == 1 ? '' : 's'} waiting · updates every minute'
                  : 'Updates every minute',
          trailing: IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _data.reload),
          children: [
            if (_data.error != null) Notice(text: errorText(_data.error!)),
            if (d != null && items.isEmpty) const EmptyState(icon: Icons.task_alt_rounded, title: 'All clear', message: 'Nothing is waiting for an administrator right now.'),
            for (final it in items)
              RecordCard(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: it['urgent'] == true ? (context.isDarkMode ? const Color(0xFF3A1414) : MvColors.errorBg) : context.mv.soft,
                  child: Text('${numOf(it['count']).toInt()}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: it['urgent'] == true ? MvColors.errorText : context.mv.accentDeep)),
                ),
                title: strOf(it['label']),
                subtitle: strOf(it['hint']),
                onTap: strOf(it['link']).startsWith('/') ? () => context.go(strOf(it['link'])) : null,
              ),
          ],
        );
      },
    );
  }
}

/// `/admin` — what needs doing, then how the marketplace is doing today.
class AdminOverviewPage extends ConsumerStatefulWidget {
  const AdminOverviewPage({super.key});

  @override
  ConsumerState<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends ConsumerState<AdminOverviewPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jget('/admin/overview'),
      jget('/admin/orders', {'page': 1, 'pageSize': 5}).catchError((_) => <String, dynamic>{}),
    ]);
    return (overview: asMap(r[0]['overview']), orders: asMaps(r[1]['data']));
  });
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _data.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider.select((a) => a.user));
    return PortalPage(
      eyebrow: 'Super admin dashboard',
      title: '${_greeting()}, ${user?.firstName ?? 'Administrator'}',
      subtitle: 'What needs doing first, then how the marketplace is doing today.',
      onRefresh: _data.reload,
      children: [
        const AttentionQueue(),
        LoadView(
          loader: _data,
          builder: (d) {
            final o = d.overview;
            final cats = asMaps(o['topCategories']);
            final maxCat = cats.fold<num>(1, (m, c) => numOf(c['products']) > m ? numOf(c['products']) : m);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Gross sales today', value: money(o['gmvToday']), sub: 'Paid orders today', icon: 'chart'),
                    MetricCard(label: 'Orders today', value: '${numOf(o['ordersToday']).toInt()}', sub: 'Placed in the last 24h', icon: 'cart'),
                    MetricCard(label: 'Users', value: '${numOf(o['totalUsers']).toInt()}', sub: 'Total registered accounts', icon: 'users'),
                    MetricCard(label: 'Vendors', value: '${numOf(o['totalVendors']).toInt()}', sub: 'Marketplace vendor accounts', icon: 'shop'),
                    MetricCard(label: 'Suppliers', value: '${numOf(o['totalSuppliers']).toInt()}', sub: 'Supplier accounts', icon: 'shop'),
                    MetricCard(label: 'Affiliates', value: '${numOf(o['totalAffiliates']).toInt()}', sub: 'Affiliate accounts', icon: 'users'),
                    MetricCard(label: 'Buyers', value: '${numOf(o['totalBuyers']).toInt()}', sub: 'Buyer accounts', icon: 'users'),
                    MetricCard(label: 'Total products', value: '${numOf(o['totalProducts']).toInt()}', sub: 'All catalog statuses', icon: 'box'),
                  ],
                ),
                const SizedBox(height: 14),
                Section(
                  title: 'MVEC revenue',
                  subtitle: 'Platform commission earned across all vendors',
                  children: [
                    MetricGrid(
                      children: [
                        MetricCard(label: 'Commission earned', value: money(o['mvecRevenueToday']), sub: 'Today', icon: 'wallet'),
                        MetricCard(label: 'Orders total', value: '${numOf(o['totalOrders']).toInt()}', sub: 'All marketplace orders', icon: 'cart'),
                      ],
                    ),
                  ],
                ),
                Section(
                  title: 'Today',
                  subtitle: 'Live operational snapshot',
                  children: [
                    RecordCard(title: 'Orders on the way', amount: '${numOf(o['pendingDeliveries']).toInt()}', onTap: () => context.go('/admin/deliveries')),
                    RecordCard(title: 'Disputes under review', amount: '${numOf(o['pendingRefunds']).toInt()}', onTap: () => context.go('/admin/disputes')),
                    RecordCard(title: 'Full analytics', subtitle: 'Sales, top sellers and products, payment mix', onTap: () => context.go('/admin/analytics')),
                  ],
                ),
                Section(
                  title: 'Recent orders',
                  subtitle: 'Across all vendors',
                  trailing: TextButton(onPressed: () => context.go('/admin/orders'), child: const Text('View all')),
                  children: [
                    if (d.orders.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No orders yet', message: 'Orders will appear here once buyers start checking out.'),
                    for (final x in d.orders)
                      RecordCard(
                        title: strOf(x['orderNumber']),
                        subtitle: personName(x['user'], 'Unknown buyer'),
                        amount: money(x['totalAmount']),
                        status: Pill(x['orderStatus']),
                        onTap: () => context.push('/admin/orders/${idOf(x)}'),
                      ),
                  ],
                ),
                Section(
                  title: 'Category health',
                  subtitle: 'Products by category',
                  trailing: TextButton(onPressed: () => context.go('/admin/categories'), child: const Text('Manage')),
                  children: [
                    if (cats.isEmpty) const EmptyState(icon: Icons.sell_outlined, title: 'No categories yet', message: 'Create categories to organize the catalog.'),
                    for (final c in cats) _Bar(label: strOf(c['name']), fraction: numOf(c['products']) / maxCat, value: '${numOf(c['products']).toInt()}'),
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

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.fraction, required this.value});
  final String label;
  final num fraction;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: fraction.toDouble().clamp(0, 1), minHeight: 8))),
        const SizedBox(width: 8),
        SizedBox(width: 44, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
      ],
    ),
  );
}

// ─── Users, products, categories, orders (GenericAdminTable) ────────────────

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
            if (['buyer', 'delivery', 'super_admin'].contains(role) && idOf(x) != me)
              SizedBox(
                width: 150,
                child: FilterSelect(
                  label: 'Role',
                  value: role,
                  options: const [('buyer', 'Buyer'), ('delivery', 'Courier'), ('super_admin', 'Admin')],
                  onChanged: (v) {
                    if (v == role) return;
                    final label = const {'buyer': 'a buyer', 'delivery': 'a courier', 'super_admin': 'an admin'}[v];
                    _patchUser(x, {'role': v}, 'Make $name $label?${v == 'super_admin' ? ' Admins can see and change everything.' : ''}');
                  },
                ),
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
        const InfoBox(title: 'Live marketplace data', text: 'This list is read directly from the MVEC database. User actions update the account record and take effect across the marketplace.'),
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

const _quickReasons = [
  'The logo is missing or unclear.',
  'The phone number could not be reached.',
  'The business description is too short to understand what you sell.',
  'The location is incomplete: add your district and sector.',
  'The business name does not match the documents or products.',
];

List<(String, String)> _checklist(Map<String, dynamic> p) {
  final loc = p['location'] is Map ? asMap(p['location']).values.where((x) => strOf(x).isNotEmpty).join(', ') : strOf(p['location']);
  return [
    ('Business name', strOf(p['businessName'])),
    ('Phone', strOf(p['phone'])),
    ('Email', strOf(p['email'])),
    ('Description', strOf(p['description']).length >= 20 ? strOf(p['description']) : ''),
    ('Logo', strOf(p['logoUrl'])),
    ('Category', strOf(p['category'])),
    ('Location', loc),
  ];
}

/// Seller or supplier verification list with review sheet (`VerificationList`).
class VerificationList extends StatefulWidget {
  const VerificationList({super.key, required this.kind});
  final String kind; // seller | supplier

  @override
  State<VerificationList> createState() => _VerificationListState();
}

class _VerificationListState extends State<VerificationList> {
  String _tab = 'PENDING';
  int _page = 1;
  String get _path => widget.kind == 'seller' ? '/admin/vendors' : '/admin/suppliers';
  late Loader<Map<String, dynamic>> _list = _loadList();
  late final _counts = Loader(
    () async => [
      for (final s in ['PENDING', 'VERIFIED', 'REJECTED']) numOf(asMap((await jget(_path, {'verificationStatus': s, 'pageSize': 1}))['meta'])['total']).toInt(),
    ],
  );

  Loader<Map<String, dynamic>> _loadList() => Loader(() => jget(_path, {'page': _page, 'pageSize': 20, if (_tab != 'ALL') 'verificationStatus': _tab}));

  void _reload() {
    final old = _list;
    setState(() => _list = _loadList());
    old.dispose();
    _counts.reload();
  }

  @override
  void dispose() {
    _list.dispose();
    _counts.dispose();
    super.dispose();
  }

  Future<void> _review(Map<String, dynamic> p) async {
    final done = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(builder: (_) => _ReviewPage(kind: widget.kind, profile: p)));
    if (done != null && mounted) {
      toast(context, done);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Tiny('Review new and updated profiles. They are notified of your decision by message, SMS and email.'),
        ListenableBuilder(
          listenable: _counts,
          builder: (context, _) {
            final c = _counts.data ?? const [];
            return TabChips(
              tabs: const [('PENDING', 'Waiting'), ('VERIFIED', 'Verified'), ('REJECTED', 'Needs changes'), ('ALL', 'All')],
              value: _tab,
              counts: c.length == 3 ? {'PENDING': c[0], 'VERIFIED': c[1], 'REJECTED': c[2]} : null,
              onChanged: (v) {
                _tab = v;
                _page = 1;
                _reload();
              },
            );
          },
        ),
        LoadView(
          loader: _list,
          builder: (d) {
            final rows = asMaps(d['data']);
            final total = numOf(asMap(d['meta'])['total'], rows.length).toInt();
            if (rows.isEmpty) {
              return EmptyState(
                icon: Icons.verified_outlined,
                title: _tab == 'PENDING' ? 'Nobody is waiting' : 'No profiles here',
                message: _tab == 'PENDING' ? 'New profiles appear here, and you also get a notification.' : null,
              );
            }
            return Column(
              children: [
                for (final p in rows)
                  Builder(
                    builder: (_) {
                      final missing = _checklist(p).where((c) => c.$2.isEmpty).length;
                      return RecordCard(
                        leading: ProductImage(src: strOf(p['logoUrl']), size: 46, radius: 10),
                        title: strOf(p['businessName']),
                        subtitle: [personName(p['user'], ''), strOf(p['email']), strOf(p['phone'])].where((x) => x.isNotEmpty).join(' · '),
                        lines: [
                          '${strOf(p['category'], 'No category')}${widget.kind == 'seller' ? ' · ${numOf(p['productCount']).toInt()} products' : ''} · updated ${formatDate(p['updatedAt'])}',
                          if (strOf(p['verificationNote']).isNotEmpty) 'Asked to fix: ${p['verificationNote']}',
                          if (missing > 0) '$missing item${missing == 1 ? '' : 's'} missing',
                        ],
                        status: Pill(p['verificationStatus'], label: p['verificationStatus'] == 'PENDING' ? 'Waiting' : null),
                        badges: [if (p['status'] != 'ACTIVE' && p['status'] != null) Pill(p['status'])],
                        actions: [ActionChipBtn(p['verificationStatus'] == 'PENDING' ? 'Review' : 'Open', primary: p['verificationStatus'] == 'PENDING', onPressed: () => _review(p))],
                      );
                    },
                  ),
                if (total > 20)
                  PaginationBar(
                    page: _page,
                    total: total,
                    perPage: 20,
                    onPage: (n) {
                      _page = n;
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

class _ReviewPage extends StatefulWidget {
  const _ReviewPage({required this.kind, required this.profile});
  final String kind;
  final Map<String, dynamic> profile;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  late final _history = Loader(() => jlist('/admin/audit-logs', 'data', {'targetId': idOf(widget.profile), 'pageSize': 10}));
  final _reason = TextEditingController();
  String _busy = '';

  @override
  void dispose() {
    _history.dispose();
    _reason.dispose();
    super.dispose();
  }

  String get _base => widget.kind == 'seller' ? '/admin/vendors/${idOf(widget.profile)}' : '/admin/suppliers/${idOf(widget.profile)}';
  String get _name => strOf(widget.profile['businessName']);

  Future<void> _decide(String decision) async {
    if (decision == 'REJECTED' && _reason.text.trim().length < 5) {
      toast(context, 'Write what the ${widget.kind} must fix. They will see it.', error: true);
      return;
    }
    setState(() => _busy = decision);
    try {
      await jpatch('$_base/verify', {'decision': decision, 'reason': _reason.text.trim()});
      if (mounted) Navigator.of(context).pop(decision == 'VERIFIED' ? '$_name is verified and has been notified.' : '$_name was told what to fix.');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _busy = '');
      }
    }
  }

  Future<void> _status(String status) async {
    if (!await confirmDialog(
      context,
      status == 'ACTIVE' ? 'Reactivate $_name?' : 'Suspend $_name? They cannot sell${widget.kind == 'supplier' ? ' to vendors' : ''} while suspended.',
      danger: status != 'ACTIVE',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = status);
    try {
      await jpatch('$_base/status', {'status': status});
      if (mounted) Navigator.of(context).pop(status == 'ACTIVE' ? '$_name is active again.' : '$_name is suspended.');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _busy = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final items = _checklist(p);
    final missing = items.where((c) => c.$2.isEmpty).map((c) => c.$1).toList();
    final reasons = [if (missing.isNotEmpty) 'Please complete: ${missing.join(', ')}.', ..._quickReasons];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.kind == 'seller' ? 'Seller' : 'Supplier'} verification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                ProductImage(src: strOf(p['logoUrl']), size: 60, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_name, style: context.mvH1.copyWith(fontSize: 18)),
                      Tiny('${personName(p['user'], '')} · joined ${formatDate(p['createdAt'])}'),
                      Wrap(spacing: 6, children: [Pill(p['verificationStatus']), if (p['status'] != 'ACTIVE' && p['status'] != null) Pill(p['status'])]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            missing.isEmpty ? const Notice(ok: true, text: 'The profile is complete. Check the details look genuine before verifying.') : Notice(text: 'Missing or too short: ${missing.join(', ')}.'),
            DataCard(
              child: Column(
                children: [
                  for (final (k, v) in items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(v.isNotEmpty ? Icons.check_circle_rounded : Icons.cancel_rounded, color: v.isNotEmpty ? MvColors.successText : MvColors.errorText, size: 20),
                      title: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(v.isNotEmpty ? (v.length > 140 ? '${v.substring(0, 140)}…' : v) : 'Not provided'),
                    ),
                  if (widget.kind == 'seller')
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline_rounded, size: 20),
                      title: const Text('Products', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(numOf(p['productCount']) > 0 ? '${p['productCount']} listed' : 'None listed yet (not needed to verify)'),
                    ),
                ],
              ),
            ),
            if (widget.kind == 'seller' && strOf(p['slug']).isNotEmpty)
              OutlineBtn(label: 'Open the public store page', icon: Icons.open_in_new_rounded, compact: true, onPressed: () => context.push('/vendors/${p['slug']}')),
            if (strOf(p['verificationNote']).isNotEmpty) InfoBox(title: 'Last rejection reason', text: strOf(p['verificationNote'])),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(labelText: 'Reason if you reject (the ${widget.kind} sees this)', hintText: 'What should they fix?'),
            ),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final r in reasons) ActionChip(label: Text(r, style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => _reason.text = r))]),
            const SizedBox(height: 14),
            GradientButton(label: 'Verify', loading: _busy == 'VERIFIED', onPressed: _busy.isNotEmpty ? null : () => _decide('VERIFIED')),
            const SizedBox(height: 8),
            OutlineBtn(label: 'Reject with reason', loading: _busy == 'REJECTED', onPressed: _busy.isNotEmpty ? null : () => _decide('REJECTED')),
            const SizedBox(height: 8),
            p['status'] == 'ACTIVE'
                ? OutlineBtn(label: 'Suspend', danger: true, onPressed: _busy.isNotEmpty ? null : () => _status('SUSPENDED'))
                : OutlineBtn(label: 'Reactivate', onPressed: _busy.isNotEmpty ? null : () => _status('ACTIVE')),
            ListenableBuilder(
              listenable: _history,
              builder: (context, _) {
                final h = _history.data ?? const [];
                if (h.isEmpty) return const SizedBox.shrink();
                return Section(
                  title: 'History',
                  children: [
                    for (final x in h)
                      Tiny('${formatDateTime(x['at'])} · ${x['actor']}: ${x['action']}${strOf(asMap(x['detail'])['reason']).isNotEmpty ? ' (“${asMap(x['detail'])['reason']}”)' : ''}'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// `/admin/vendors` — seller verification.
class AdminSellersPage extends StatelessWidget {
  const AdminSellersPage({super.key});

  @override
  Widget build(BuildContext context) => const PortalPage(
    eyebrow: 'People & stores',
    title: 'Sellers',
    subtitle: 'Verify sellers, see what is missing from their profile, and suspend or reactivate stores.',
    children: [VerificationList(kind: 'seller')],
  );
}

// ─── Suppliers: verification, wholesale, quotes, bank payouts ──────────────

const _wholesaleLabel = {
  'PENDING_PAYMENT': 'Waiting for payment',
  'ESCROW_HELD': 'Paid · to ship',
  'SHIPPED': 'Shipped',
  'DELIVERED': 'Delivered',
  'CONFIRMED_RELEASED': 'Completed',
  'DISPUTED': 'Problem reported',
  'CANCELLED': 'Cancelled',
};

/// `/admin/suppliers` — tabs for supplier work (`AdminSuppliers`).
class AdminSuppliersPage extends StatefulWidget {
  const AdminSuppliersPage({super.key, this.tab});
  final String? tab;

  @override
  State<AdminSuppliersPage> createState() => _AdminSuppliersPageState();
}

class _AdminSuppliersPageState extends State<AdminSuppliersPage> {
  late String _tab = widget.tab ?? 'accounts';
  late final _attention = Loader(() async => {for (final i in asMaps((await jget('/admin/attention'))['items'])) '${i['key']}': numOf(i['count']).toInt()});

  @override
  void dispose() {
    _attention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'People & stores',
      title: 'Suppliers',
      subtitle: 'Verify suppliers, follow wholesale orders and quote requests, decide wholesale problems and send bank payouts.',
      children: [
        ListenableBuilder(
          listenable: _attention,
          builder: (context, _) {
            final c = _attention.data ?? const <String, int>{};
            return TabChips(
              tabs: const [('accounts', 'Verification'), ('wholesale', 'Wholesale orders'), ('quotes', 'Quote requests'), ('payouts', 'Bank payouts')],
              value: _tab,
              counts: {
                if (c['suppliers'] != null) 'accounts': c['suppliers']!,
                if (c['wholesaleDisputes'] != null) 'wholesale': c['wholesaleDisputes']!,
                if (c['supplierPayouts'] != null) 'payouts': c['supplierPayouts']!,
              },
              onChanged: (v) => setState(() => _tab = v),
            );
          },
        ),
        switch (_tab) {
          'wholesale' => _WholesaleOversight(onChanged: _attention.reload),
          'quotes' => const _QuoteOversight(),
          'payouts' => _SupplierPayouts(onChanged: _attention.reload),
          _ => const VerificationList(kind: 'supplier'),
        },
      ],
    );
  }
}

class _WholesaleOversight extends StatefulWidget {
  const _WholesaleOversight({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_WholesaleOversight> createState() => _WholesaleOversightState();
}

class _WholesaleOversightState extends State<_WholesaleOversight> {
  String _status = 'DISPUTED';
  late Loader<List<Map<String, dynamic>>> _data = _load();
  final _notes = <String, TextEditingController>{};
  String _busy = '';

  Loader<List<Map<String, dynamic>>> _load() => Loader(() => jlist('/wholesale/admin/orders', 'orders', {if (_status.isNotEmpty) 'status': _status}));

  @override
  void dispose() {
    _data.dispose();
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _decide(Map<String, dynamic> o, String decision) async {
    final ok = await confirmDialog(
      context,
      decision == 'RELEASE' ? 'Pay ${partyName(o['supplier'])} ${money(o['totalAmount'])} (minus commission)?' : 'Refund ${partyName(o['vendor'])} ${money(o['totalAmount'])}?',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = idOf(o));
    final done = await runAction(context, () => jpost('/wholesale/admin/orders/${idOf(o)}/resolve', {'decision': decision, 'note': _notes[idOf(o)]?.text ?? ''}));
    if (mounted) setState(() => _busy = '');
    if (done) {
      _data.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Wholesale orders',
      subtitle: 'Vendors buying stock from suppliers. MVEC holds the money until the vendor confirms receipt; problems are decided here.',
      children: [
        FilterSelect(
          label: 'Show',
          value: _status,
          options: const [('DISPUTED', 'Problem reported'), ('ESCROW_HELD', 'Paid, not shipped'), ('SHIPPED', 'Shipped'), ('PENDING_PAYMENT', 'Waiting for payment'), ('', 'All')],
          onChanged: (v) {
            final old = _data;
            setState(() {
              _status = v;
              _data = _load();
            });
            old.dispose();
          },
        ),
        const SizedBox(height: 10),
        LoadView(
          loader: _data,
          builder:
              (rows) => Column(
                children: [
                  if (rows.isEmpty) EmptyState(title: _status == 'DISPUTED' ? 'No reported problems' : 'No orders here'),
                  for (final o in rows)
                    RecordCard(
                      title: '${o['orderNumber']} · ${partyName(o['vendor'])} ← ${partyName(o['supplier'])}',
                      lines: [
                        for (final i in asMaps(o['items'])) '${i['quantity']} ${i['unit'] ?? ''} × ${i['productName']} at ${money(i['unitPrice'])}',
                        if (strOf(o['disputeReason']).isNotEmpty) 'Problem: ${o['disputeReason']}',
                        if (strOf(o['cancelReason']).isNotEmpty) 'Cancelled: ${o['cancelReason']}',
                        'Placed ${formatDate(o['createdAt'])}${o['paidAt'] != null ? ' · paid ${formatDate(o['paidAt'])}' : ''}${o['shippedAt'] != null ? ' · shipped ${formatDate(o['shippedAt'])}' : ''}',
                      ],
                      amount: money(o['totalAmount']),
                      status: StatusChip(
                        _wholesaleLabel[o['status']] ?? titleCase(o['status']),
                        tone:
                            o['status'] == 'CONFIRMED_RELEASED'
                                ? StatusTone.good
                                : ['DISPUTED', 'CANCELLED'].contains(o['status'])
                                ? StatusTone.bad
                                : StatusTone.warn,
                      ),
                      actions:
                          o['status'] != 'DISPUTED'
                              ? const []
                              : [
                                SizedBox(
                                  width: 260,
                                  child: TextField(
                                    controller: _notes.putIfAbsent(idOf(o), TextEditingController.new),
                                    decoration: const InputDecoration(isDense: true, hintText: 'Decision note (both sides see it)'),
                                  ),
                                ),
                                ActionChipBtn('Pay supplier', primary: true, busy: _busy == idOf(o), onPressed: () => _decide(o, 'RELEASE')),
                                ActionChipBtn('Refund vendor', busy: _busy == idOf(o), onPressed: () => _decide(o, 'REFUND')),
                              ],
                    ),
                ],
              ),
        ),
      ],
    );
  }
}

class _QuoteOversight extends StatefulWidget {
  const _QuoteOversight();

  @override
  State<_QuoteOversight> createState() => _QuoteOversightState();
}

class _QuoteOversightState extends State<_QuoteOversight> {
  late final _data = Loader(() => jlist('/quotes/admin/requests', 'requests'));
  String _q = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Quote requests',
      subtitle: 'Vendors ask for goods; verified suppliers quote; accepted quotes become wholesale orders. Nothing to approve here.',
      children: [
        SearchBox(hint: 'Search requests…', onChanged: (v) => setState(() => _q = v)),
        LoadView(
          loader: _data,
          builder:
              (rows) => Paged<Map<String, dynamic>>(
                items: rows.where((r) => matches(_q, [r['reference'], r['category'], partyName(r['vendor'])])).toList(),
                empty: const Tiny('No quote requests yet.'),
                itemBuilder:
                    (r) => RecordCard(
                      title: '${r['reference']} · ${r['category'] ?? ''}',
                      subtitle: '${partyName(r['vendor'])} · needed by ${formatDate(r['neededBy'])}',
                      lines: [asMaps(r['lines']).map((l) => '${l['units']} ${l['unit']} ${l['product']}').join(', '), '${numOf(r['quoteCount']).toInt()} quotes'],
                      status: StatusChip(
                        const {'OPEN': 'Open', 'AWARDED': 'Quote accepted', 'CANCELLED': 'Cancelled', 'EXPIRED': 'Expired'}[r['status']] ?? '${r['status']}',
                        tone:
                            r['status'] == 'AWARDED'
                                ? StatusTone.good
                                : r['status'] == 'OPEN'
                                ? StatusTone.warn
                                : StatusTone.bad,
                      ),
                    ),
              ),
        ),
      ],
    );
  }
}

class _SupplierPayouts extends StatefulWidget {
  const _SupplierPayouts({required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<_SupplierPayouts> createState() => _SupplierPayoutsState();
}

class _SupplierPayoutsState extends State<_SupplierPayouts> {
  late final _data = Loader(() => jlist('/admin/suppliers/payouts', 'payouts'));
  String _busy = '';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _act(Map<String, dynamic> p, String status) async {
    var reason = '';
    if (status == 'REJECTED') {
      reason = await promptDialog(context, "Why is this payout declined? The amount goes back to the supplier's balance.", confirm: 'Decline') ?? '';
      if (reason.trim().isEmpty) return;
    }
    if (!mounted) return;
    if (status == 'PAID' && !await confirmDialog(context, 'Confirm you sent ${money(p['amount'])} to ${strOf(p['destination'], 'the supplier')}?')) return;
    if (!mounted) return;
    setState(() => _busy = idOf(p));
    final ok = await runAction(
      context,
      () => jpatch('/admin/suppliers/payouts/${idOf(p)}', {'status': status, 'reason': reason}),
      success:
          status == 'PAID'
              ? 'Marked as paid. The supplier was notified.'
              : status == 'PROCESSING'
              ? 'Marked as being sent.'
              : "Declined; the money is back in the supplier's balance.",
    );
    if (mounted) setState(() => _busy = '');
    if (ok) {
      _data.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Supplier bank payouts',
      subtitle: "Mobile money payouts are sent automatically. Bank transfers: send from MVEC's account, then mark paid. The supplier is notified.",
      trailing: IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _data.reload),
      children: [
        LoadView(
          loader: _data,
          builder:
              (rows) => Column(
                children: [
                  if (rows.isEmpty) const EmptyState(icon: Icons.account_balance_outlined, title: 'No payouts waiting'),
                  for (final p in rows)
                    RecordCard(
                      title: strOf(p['supplierName'] ?? p['accountName'], 'Supplier'),
                      subtitle: '${p['bankName'] ?? ''} · ${p['destination'] ?? ''}${strOf(p['accountName']).isNotEmpty ? ' · ${p['accountName']}' : ''}',
                      lines: ['${p['payoutNumber'] ?? ''} · requested ${formatDate(p['requestedAt'])}${strOf(p['note']).isNotEmpty ? ' · “${p['note']}”' : ''}'],
                      amount: money(p['amount']),
                      status: StatusChip(p['status'] == 'PROCESSING' ? 'Being sent' : 'Waiting', tone: StatusTone.warn),
                      actions: [
                        if (p['status'] == 'PENDING') ActionChipBtn('Sending now', busy: _busy == idOf(p), onPressed: () => _act(p, 'PROCESSING')),
                        ActionChipBtn('Mark paid', primary: true, busy: _busy == idOf(p), onPressed: () => _act(p, 'PAID')),
                        ActionChipBtn('Decline', danger: true, busy: _busy == idOf(p), onPressed: () => _act(p, 'REJECTED')),
                      ],
                    ),
                ],
              ),
        ),
      ],
    );
  }
}
