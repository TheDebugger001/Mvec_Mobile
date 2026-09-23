import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/nav_items.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/mv_icon.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  final _drawerKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      key: _drawerKey,
      drawer: _buildDrawer(user?.display ?? 'Administrator'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopbar(user?.display ?? 'Administrator'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20).copyWith(bottom: 40),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopbar(String name) {
    final notifierDot = true;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? MvColors.darkSurface : Colors.white,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _drawerKey.currentState?.openDrawer(),
            icon: const MvIcon('menu'),
            tooltip: 'Menu',
          ),
          const SizedBox(width: 4),
          const Text(
            'MVEC',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 18, fontWeight: FontWeight.w800, color: MvColors.primaryDeep),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: MvColors.metricIconBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('ADMIN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: MvColors.primaryDeep)),
          ),
          const Spacer(),
          Consumer(builder: (context, ref, _) {
            return IconButton(
              onPressed: () {
                final t = ref.read(themeModeProvider);
                ref.read(themeModeProvider.notifier).state = t == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
              },
              icon: MvIcon(
                Theme.of(context).brightness == Brightness.dark ? 'sun' : 'moon',
                color: Theme.of(context).brightness == Brightness.dark ? MvColors.darkText : MvColors.ink,
              ),
              tooltip: 'Toggle theme',
            );
          }),
          IconButton(
            onPressed: () => context.push('/admin/notifications'),
            tooltip: 'Notifications',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                MvIcon('bell', color: Theme.of(context).brightness == Brightness.dark ? MvColors.darkText : MvColors.ink),
                if (notifierDot)
                  Positioned(
                    top: -2,
                    right: -3,
                    child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: MvColors.badgeRed, shape: BoxShape.circle)),
                  ),
              ],
            ),
          ),
          InkWell(
            onTap: () => context.push('/admin/messages'),
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(gradient: MvColors.gradient, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(initials(name), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(gradient: MvColors.gradient, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(initials(name), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            const Text('Super Administrator', style: TextStyle(fontSize: 11, color: MvColors.primaryDeep, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, size: 20, color: isDark ? MvColors.darkMuted : MvColors.ink),
                      ),
                    ],
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 24),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final (section, items) in AdminNav.groups) ...[
                    for (final item in items) _item(item),
                    if (section != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          section.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: Theme.of(context).hintColor),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Divider(color: Theme.of(context).dividerColor, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: [
                  _bottomItem('View marketplace', '/', 'home'),
                  _bottomItem('Sign out', '/login', 'logout', danger: true, onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (mounted) context.go('/login');
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(NavItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.path == item.path || (widget.path.startsWith(item.path) && item.path != '/admin');
    return _navLink(item.label, item.icon, active, isDark, onTap: () {
      Navigator.pop(context);
      context.go(item.path);
    });
  }

  Widget _bottomItem(String label, String path, String icon, {bool danger = false, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _navLink(
      label,
      icon,
      false,
      isDark,
      danger: danger,
      onTap: () {
        Navigator.pop(context);
        onTap ?? context.go(path);
      },
    );
  }

  Widget _navLink(String label, String icon, bool active, bool isDark, {bool danger = false, VoidCallback? onTap}) {
    final fg = danger
        ? MvColors.dangerIcon
        : (active
            ? MvColors.primaryDeep
            : (isDark ? MvColors.darkMuted : const Color(0xFF6B7780)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: active ? (isDark ? MvColors.darkSurface2 : MvColors.metricIconBg) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                MvIcon(icon, size: 17, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}