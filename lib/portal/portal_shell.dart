import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/icons.dart';
import '../core/nav_items.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../state/auth_state.dart';
import '../state/notifications_state.dart';
import '../widgets/common.dart';

/// Which dashboard a path belongs to ("/vendor/orders" -> "/vendor").
String? portalPrefix(String path) {
  for (final p in const ['/vendor', '/supplier', '/affiliate', '/delivery', '/admin']) {
    if (path == p || path.startsWith('$p/')) return p;
  }
  return null;
}

const _platformName = {'/admin': 'Admin', '/supplier': 'Supplier', '/affiliate': 'Affiliate', '/delivery': 'Delivery', '/vendor': 'Seller'};

String _accountLabel(AppUser? user, bool admin) {
  if (admin) return 'Super Administrator';
  return switch (user?.role) {
    'supplier' => 'Supplier account',
    'affiliate' => 'Affiliate account',
    'delivery' => 'Delivery partner',
    _ => user?.isStaff == true ? '${staffRoleLabel[user?.staffRole] ?? 'Staff'} · ${user?.staffStoreName ?? 'Store'}' : 'Vendor account',
  };
}

String _notificationsPath(String prefix) => switch (prefix) {
  '/admin' => '/admin/notifications',
  '/supplier' => '/supplier/notifications',
  '/affiliate' => '/affiliate/notifications',
  '/delivery' => '/delivery/notifications',
  _ => '/vendor/notifications',
};

String _profilePath(String prefix) => prefix == '/delivery' ? '/delivery/profile' : '$prefix/profile';

/// Groups for the dashboard [prefix]; an admin acting as a seller sees the
/// seller menu under /vendor.
List<NavGroup> _groupsFor(String prefix, AppUser? user) => switch (prefix) {
  '/admin' => adminNavGroups,
  '/supplier' => navGroupsFor('supplier', user),
  '/affiliate' => affiliateNavGroups,
  '/delivery' => deliveryNavGroups,
  _ => navGroupsFor('vendor', user),
};

/// Longest menu link matching the path, so /vendor/orders/123 highlights Orders.
String activeHref(List<NavGroup> groups, String path) {
  var best = '';
  for (final g in groups) {
    for (final i in g.items) {
      final isRoot = i.href.split('/').length <= 2;
      final hit = path == i.href || (!isRoot && path.startsWith('${i.href}/'));
      if (hit && i.href.length > best.length) best = i.href;
    }
  }
  return best;
}

/// Work waiting for an admin per page (`useAdminBadges`), refreshed every minute.
class AdminBadgesNotifier extends Notifier<Map<String, int>> {
  Timer? _timer;

  @override
  Map<String, int> build() {
    ref.onDispose(() => _timer?.cancel());
    final user = ref.watch(authProvider.select((a) => a.user));
    if (user?.role == 'super_admin') {
      Future.microtask(refresh);
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    }
    return const {};
  }

  Future<void> refresh() async {
    try {
      final r = asMap(await Api.instance.get('/admin/attention'));
      state = {for (final e in asMap(r['badges']).entries) e.key: numOf(e.value).toInt()};
    } catch (_) {
      // Keep the old counts.
    }
  }
}

final adminBadgesProvider = NotifierProvider<AdminBadgesNotifier, Map<String, int>>(AdminBadgesNotifier.new);

/// The frame around every dashboard page: top bar (menu, title, theme,
/// notifications, account), the grouped side menu and the bottom bar with the
/// role's four main pages plus "More" (`DashboardLayout` + `MobileBottomNav`).
class PortalShell extends ConsumerWidget {
  const PortalShell({super.key, required this.uri, required this.child});
  final Uri uri;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final user = ref.watch(authProvider.select((a) => a.user));
    final unread = ref.watch(unreadProvider);
    final path = uri.path;
    final prefix = portalPrefix(path) ?? '/vendor';
    final admin = prefix == '/admin';
    final groups = _groupsFor(prefix, user);
    final active = activeHref(groups, path);
    final flat = [for (final g in groups) ...g.items];
    final title = path.endsWith('/profile') ? 'Account settings' : flat.where((i) => i.href == active).map((i) => i.label).firstOrNull ?? (_platformName[prefix] ?? 'Dashboard');
    final role = admin ? 'super_admin' : prefix.substring(1);
    final primary = (mobilePrimaryByRole[role] ?? flat.take(4).map((i) => i.href).toList()).map((h) => flat.where((i) => i.href == h).firstOrNull).whereType<NavItem>().toList();
    final selected = primary.indexWhere((i) => i.href == active);

    return Scaffold(
      drawer: PortalDrawer(prefix: prefix, path: path),
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: mv.text)),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.go(_notificationsPath(prefix)),
            icon: Badge(isLabelVisible: unread > 0, label: Text(unread > 9 ? '9+' : '$unread'), child: const Icon(Icons.notifications_none_rounded)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 2),
            child: InkWell(customBorder: const CircleBorder(), onTap: () => context.go(_profilePath(prefix)), child: Avatar(name: user?.fullName ?? 'M', url: user?.avatarUrl, radius: 16)),
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: mv.border)),
      ),
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: Builder(builder: (context) => _PortalBottomBar(items: primary, selected: selected, onMore: () => Scaffold.of(context).openDrawer())),
    );
  }
}

class _PortalBottomBar extends StatelessWidget {
  const _PortalBottomBar({required this.items, required this.selected, required this.onMore});
  final List<NavItem> items;
  final int selected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    Widget cell(String label, IconData icon, bool on, VoidCallback tap) => Expanded(
      child: InkWell(
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: on ? mv.accentDeep : mv.textMuted),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? mv.accentDeep : mv.textMuted)),
            ],
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: mv.surface, border: Border(top: BorderSide(color: mv.border))),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) cell(bottomLabel[items[i].href] ?? items[i].label, mvIcon(items[i].icon), i == selected, () => context.go(items[i].href)),
            cell('More', Icons.grid_view_rounded, false, onMore),
          ],
        ),
      ),
    );
  }
}

/// The dashboard side menu (`Sidebar` + `GroupedNav`): groups open one at a
/// time, the group holding the current page starts open.
class PortalDrawer extends ConsumerStatefulWidget {
  const PortalDrawer({super.key, required this.prefix, required this.path});
  final String prefix;
  final String path;

  @override
  ConsumerState<PortalDrawer> createState() => _PortalDrawerState();
}

class _PortalDrawerState extends ConsumerState<PortalDrawer> {
  String? _open;

  void _go(String location) {
    Navigator.of(context).pop();
    context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final user = ref.watch(authProvider.select((a) => a.user));
    final admin = widget.prefix == '/admin';
    final badges = admin ? ref.watch(adminBadgesProvider) : const <String, int>{};
    final groups = _groupsFor(widget.prefix, user);
    final active = activeHref(groups, widget.path);
    final activeGroup = groups.where((g) => g.items.any((i) => i.href == active)).map((g) => g.label).firstOrNull;
    _open ??= activeGroup ?? groups.where((g) => g.items.length > 1).map((g) => g.label).firstOrNull;

    Widget link(NavItem i, {double indent = 0}) {
      final on = i.href == active;
      final badge = badges[i.href] ?? 0;
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 2),
        child: Material(
          color: on ? mv.soft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: Icon(mvIcon(i.icon), size: 19, color: on ? mv.accentDeep : mv.textMuted),
            title: Text(i.label, style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? mv.accentDeep : mv.text)),
            trailing: badge > 0 ? Badge(label: Text(badge > 99 ? '99+' : '$badge')) : null,
            onTap: () => _go(i.href),
          ),
        ),
      );
    }

    return Drawer(
      width: 304,
      backgroundColor: mv.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
              child: Row(
                children: [
                  const MvLogo(size: 28),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(20)),
                    child: Text((_platformName[widget.prefix] ?? 'Seller').toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: mv.accentDeep)),
                  ),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded), tooltip: 'Close menu'),
                ],
              ),
            ),
            InkWell(
              onTap: () => _go(_profilePath(widget.prefix)),
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Avatar(name: user?.fullName ?? 'M', url: user?.avatarUrl, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName.isNotEmpty == true ? user!.fullName : 'MVEC User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 13.5),
                          ),
                          Text(_accountLabel(user, admin), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                children: [
                  for (final g in groups)
                    if (g.items.length == 1)
                      link(g.items.first)
                    else ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _open = _open == g.label ? '' : g.label),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  g.label.toUpperCase(),
                                  style: TextStyle(fontSize: 10.5, letterSpacing: 1.3, fontWeight: FontWeight.w800, color: g.label == activeGroup ? mv.accentDeep : mv.textMuted),
                                ),
                              ),
                              if (_open != g.label && g.items.fold<int>(0, (s, i) => s + (badges[i.href] ?? 0)) > 0) Badge(label: Text('${g.items.fold<int>(0, (s, i) => s + (badges[i.href] ?? 0))}')),
                              Icon(_open == g.label ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: mv.textMuted),
                            ],
                          ),
                        ),
                      ),
                      if (_open == g.label)
                        for (final i in g.items) link(i, indent: 4),
                    ],
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: mv.border))),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                children: [
                  link(NavItem(_profilePath(widget.prefix), 'Account settings', 'user')),
                  link(const NavItem('/', 'View marketplace', 'home')),
                  ListTile(
                    dense: true,
                    leading: Icon(mvIcon('logout'), size: 19, color: MvColors.errorText),
                    title: const Text('Sign out', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: MvColors.errorText)),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a staff member opens a page their role doesn't include.
class NoAccessPage extends ConsumerWidget {
  const NoAccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((a) => a.user));
    return EmptyState(
      icon: Icons.shield_outlined,
      title: "You don't have access to this page",
      message: "Your role (${staffRoleLabel[user?.staffRole] ?? 'Staff'}) doesn't include it. Ask the store owner if you need access.",
      action: OutlineBtn(label: 'Back to dashboard', compact: true, onPressed: () => context.go('/vendor')),
    );
  }
}

/// A dashboard address that doesn't exist (`Page not found` on the web).
class PortalNotFoundPage extends StatelessWidget {
  const PortalNotFoundPage({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final home = portalPrefix(path) ?? '/';
    return EmptyState(
      icon: Icons.explore_off_outlined,
      title: 'Page not found',
      message: 'There is no page at $path. It may have moved.',
      action: GradientButton(label: 'Back to the dashboard', compact: true, onPressed: () => context.go(home)),
    );
  }
}
