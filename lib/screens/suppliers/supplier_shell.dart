import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/nav_items.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/supplier.dart';
import '../../providers/auth_provider.dart';
import '../../providers/supplier_providers.dart';
import '../../widgets/mv_icon.dart';

/// Supplier-facing layout. Structurally the same shell as [AdminShell] —
/// topbar, accordion drawer, mobile bottom bar — but driven by [SupplierNav]
/// so a supplier only ever sees supplier routes.
class SupplierShell extends ConsumerStatefulWidget {
  const SupplierShell({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  ConsumerState<SupplierShell> createState() => _SupplierShellState();
}

class _SupplierShellState extends ConsumerState<SupplierShell> {
  final _drawerKey = GlobalKey<ScaffoldState>();
  String? _openGroup;

  @override
  void initState() {
    super.initState();
    _openGroup = SupplierNav.groupFor(widget.path) ?? SupplierNav.groups.first.label;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = SupplierNav.groupFor(widget.path);
    if (g != null && _openGroup != g) _openGroup = g;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final name = user?.display ?? 'Supplier';
    return Scaffold(
      key: _drawerKey,
      drawer: _buildDrawer(name, user?.email ?? ''),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTopbar(name),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
              child: widget.child,
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────────────────────
  Widget _buildTopbar(String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MvColors.darkText : MvColors.ink;
    final statusAsync = ref.watch(supplierProfileProvider);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isDark ? MvColors.darkSurface : Colors.white,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _drawerKey.currentState?.openDrawer(),
            icon: MvIcon('menu', color: ink),
            tooltip: 'Menu',
          ),
          const Text(
            'MVEC',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, fontFamily: 'Manrope', color: MvColors.primaryDeep),
          ),
          const SizedBox(width: 8),
          const Text(
            'SUPPLIER',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: MvColors.muted),
          ),
          const Spacer(),
          statusAsync.maybeWhen(
            // No profile yet — the onboarding prompt carries the message.
            data: (s) => s == null ? const SizedBox.shrink() : _VerificationBadge(detail: s),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => context.go('/supplier/profile'),
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(gradient: MvColors.gradient, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(initials(name), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── DRAWER ─────────────────────────────────────────────────────────────
  Widget _buildDrawer(String name, String email) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? MvColors.darkMuted : const Color(0xFF8A969C);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('MVEC', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, fontFamily: 'Manrope', color: MvColors.primaryDeep)),
                      const SizedBox(width: 10),
                      const Text('SUPPLIER PORTAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: MvColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(gradient: MvColors.gradient, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(initials(name), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(email.isEmpty ? 'Supplier' : email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 26),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  for (final group in SupplierNav.groups) _group(group, isDark),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(color: Theme.of(context).dividerColor, height: 1),
                  const SizedBox(height: 8),
                  _bottomLink('View marketplace', 'home', () {
                    Navigator.pop(context);
                    context.go('/home');
                  }),
                  _bottomLink('Sign out', 'logout', () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (mounted) context.go('/login');
                  }, danger: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(NavGroup group, bool isDark) {
    final open = _openGroup == group.label;
    final hasActive = group.items.any((i) => _isActive(i.path));
    final fg = hasActive ? MvColors.primaryDeep : (isDark ? const Color(0xFFB9CBD3) : const Color(0xFF4C5A62));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _openGroup = open ? null : group.label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(group.label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .4, color: fg)),
                  ),
                  MvIcon('arrow', size: 14, color: fg).rotate(open ? 90 : 0),
                ],
              ),
            ),
          ),
        ),
        if (open)
          for (final item in group.items) _item(item, isDark, indent: true),
      ],
    );
  }

  Widget _item(NavItem item, bool isDark, {bool indent = false}) {
    final active = _isActive(item.path);
    final fg = active ? MvColors.primaryDeep : (isDark ? MvColors.darkMuted : const Color(0xFF6B7780));
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 12 : 0, 0, 0, 1),
      child: Material(
        color: active ? (isDark ? MvColors.darkSurface2 : MvColors.metricIconBg) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.pop(context);
            context.go(item.path);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                MvIcon(item.icon, size: 16, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomLink(String label, String icon, VoidCallback onTap, {bool danger = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = danger ? MvColors.dangerIcon : (isDark ? MvColors.darkMuted : const Color(0xFF6B7780));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                MvIcon(icon, size: 16, color: fg),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── MOBILE BOTTOM NAV ──────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? MvColors.darkSurface : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in SupplierNav.bottomNav) Expanded(child: _bottomItem(item, isDark)),
            Expanded(child: _bottomMore(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem(NavItem item, bool isDark) {
    final active = _isActive(item.path);
    final fg = active ? MvColors.primaryDeep : (isDark ? MvColors.darkMuted : const Color(0xFF6B7780));
    return InkWell(
      onTap: () => context.go(item.path),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MvIcon(item.icon, size: 18, color: fg),
            const SizedBox(height: 3),
            Text(item.label, style: TextStyle(fontSize: 9.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _bottomMore(bool isDark) {
    final fg = isDark ? MvColors.darkMuted : const Color(0xFF6B7780);
    return InkWell(
      onTap: () => _drawerKey.currentState?.openDrawer(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MvIcon('menu', size: 18, color: fg),
            const SizedBox(height: 3),
            Text('More', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }

  bool _isActive(String path) => widget.path == path || (widget.path.startsWith(path) && path != '/supplier');
}

/// Compact verification badge shown in the topbar across all supplier pages.
class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.detail});

  final SupplierDetail detail;

  @override
  Widget build(BuildContext context) {
    final label = switch (detail.verificationStatus?.toUpperCase()) {
      'VERIFIED' => 'Verified',
      'PENDING' || 'UNDER_REVIEW' => 'In review',
      'REJECTED' => 'Rejected',
      _ => 'Unverified',
    };
    return Tooltip(
      message: 'Verification: ${detail.effectiveStatus}',
      child: StatusPill(status: detail.verificationStatus, label: label),
    );
  }
}

/// A small status pill with an explicit label (the shared `StatusChip`
/// title-cases the raw status, which reads badly for verification states).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, required this.label});

  final String? status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = statusColor(status ?? 'UNKNOWN');
    final bg = fg == MvColors.successText
        ? MvColors.successBg
        : fg == MvColors.warningText
            ? MvColors.warningBg
            : fg == MvColors.errorText
                ? MvColors.errorBg
                : MvColors.neutralBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg, letterSpacing: .3)),
    );
  }
}

extension _RotateX on Widget {
  Widget rotate(double deg) => Transform.rotate(angle: deg * 3.141592653589793 / 180, child: this);
}
