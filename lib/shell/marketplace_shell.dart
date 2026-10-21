import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/icons.dart';
import '../core/nav_items.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../state/auth_state.dart';
import '../state/cart_state.dart';
import '../state/catalog_state.dart';
import '../state/compare_state.dart';
import '../state/notifications_state.dart';
import '../widgets/common.dart';
import '../widgets/mv_icon.dart';
import '../widgets/theme_switch.dart';

/// The five primary marketplace destinations, in the required order.
/// (The web storefront's `main-nav-links`: Home, Shop, For You, Deals, Orders.)
class _Dest {
  const _Dest(this.label, this.icon, this.location);
  final String label;
  final String icon;
  final String location;
}

const _destinations = <_Dest>[
  _Dest('Home', 'home', '/'),
  _Dest('Shop', 'shop', '/shop'),
  _Dest('For You', 'heart', '/buyer/recommendations'),
  _Dest('Deals', 'tag', '/shop?deal=true'),
  _Dest('Orders', 'box', '/orders'),
];

/// Which bottom-bar item the current location belongs to, or -1.
int _activeIndex(Uri uri) {
  final path = uri.path;
  if (path == '/') return 0;
  if (path == '/shop') return uri.queryParameters['deal'] == 'true' ? 3 : 1;
  if (path == '/buyer/recommendations') return 2;
  if (path == '/orders') return 4;
  return -1;
}

/// Row 1 (52) + search row (46 + 12 gap) + bottom border (1) + slack.
const double _kTopBarHeight = 52 + 58 + 2;

/// Storefront frame: top bar (menu, logo, search, theme, compare, wishlist,
/// cart, account), the blurred left sidebar, and the five-item floating
/// bottom navigation.
class MarketplaceShell extends ConsumerStatefulWidget {
  const MarketplaceShell({super.key, required this.child, required this.uri});
  final Widget child;
  final Uri uri;

  @override
  ConsumerState<MarketplaceShell> createState() => _MarketplaceShellState();
}

class _MarketplaceShellState extends ConsumerState<MarketplaceShell> with SingleTickerProviderStateMixin {
  /// 0 = sidebar closed, 1 = fully open. Drives the slide and the blur together.
  late final AnimationController _drawer = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));

  @override
  void dispose() {
    _drawer.dispose();
    super.dispose();
  }

  void _open() => _drawer.fling(velocity: 2.2);
  void _close() => _drawer.fling(velocity: -2.2);

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final cartNotice = ref.watch(cartProvider.select((c) => c.notice));
    return AnimatedBuilder(
      animation: _drawer,
      // While the sidebar is open the system back gesture closes it first.
      builder: (context, shell) => PopScope(
        canPop: _drawer.value == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: shell!,
      ),
      child: Stack(
        children: [
          Scaffold(
            appBar: PreferredSize(
              // The status-bar inset is added on top: the bar draws under it.
              preferredSize: Size.fromHeight(_kTopBarHeight + MediaQuery.paddingOf(context).top),
              child: _TopBar(onMenu: _open),
            ),
            body: Column(
              children: [
                if (cartNotice.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Notice(text: cartNotice, onClose: () => ref.read(cartProvider.notifier).dismissNotice()),
                  ),
                Expanded(child: widget.child),
              ],
            ),
            bottomNavigationBar: keyboard ? null : MarketBottomBar(activeIndex: _activeIndex(widget.uri)),
          ),
          _SidebarLayer(controller: _drawer, location: widget.uri, onClose: _close),
        ],
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onMenu});
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final user = ref.watch(authProvider.select((a) => a.user));
    final dark = context.isDarkMode;

    return Material(
      color: dark ? MvColors.darkHeaderBg : mv.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: mv.border))),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: menu and logo on the left; theme, compare, wishlist, cart and account on the right.
              SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      _BarIcon(name: 'menu', tooltip: 'Open menu', onTap: onMenu),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: GestureDetector(onTap: () => context.go('/'), child: const MvLogo(size: 26))),
                        ),
                      ),
                      const ThemeSwitch(compact: true),
                      const ShopShortcuts(),
                      _AccountMenu(user: user),
                    ],
                  ),
                ),
              ),
              // Row 2: search.
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(height: 46, child: _SearchPill()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compare, wishlist and cart, with counts. On the storefront top bar and on
/// every full-screen shopping page, so they are always one tap away.
class ShopShortcuts extends ConsumerWidget {
  const ShopShortcuts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartProvider.select((c) => c.count));
    final wishCount = ref.watch(wishlistProvider.select((w) => w.length));
    final compareCount = ref.watch(compareProvider.select((c) => c.length));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BarIcon(name: 'compare', tooltip: 'Compare, $compareCount products', badge: compareCount, onTap: () => context.go('/buyer/compare')),
        _BarIcon(name: 'heart', tooltip: 'Wishlist, $wishCount items', badge: wishCount, onTap: () => context.go('/wishlist')),
        _BarIcon(name: 'cart', tooltip: 'Cart, $cartCount items', badge: cartCount, onTap: () => context.go('/cart')),
      ],
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.name, required this.tooltip, required this.onTap, this.badge = 0});
  final String name;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 40,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              MvIcon(name, size: 22, color: mv.text, strokeWidth: 1.5),
              if (badge > 0)
                Positioned(
                  right: 2,
                  top: 5,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: mv.accent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: mv.surface, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, height: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends ConsumerWidget {
  const _SearchPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    return Semantics(
      button: true,
      label: 'Search products',
      child: InkWell(
        borderRadius: BorderRadius.circular(MvRadius.card),
        onTap: () async {
          final q = await showSearch<String?>(context: context, delegate: ProductSearchDelegate(ref));
          if (q != null && q.trim().isNotEmpty && context.mounted) {
            context.go('/shop?q=${Uri.encodeQueryComponent(q.trim())}');
          }
        },
        child: Container(
          height: 46,
          padding: const EdgeInsets.fromLTRB(14, 0, 5, 0),
          decoration: BoxDecoration(
            color: mv.surfaceMuted,
            borderRadius: BorderRadius.circular(MvRadius.card),
            border: Border.all(color: mv.border),
          ),
          child: Row(
            children: [
              MvIcon('search', size: 19, color: mv.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Search for products, brands and more…', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 13)),
              ),
              // Filters live on the Shop page (on sale, in stock, sort, categories).
              Tooltip(
                message: 'Filters',
                child: Material(
                  color: mv.accent,
                  borderRadius: BorderRadius.circular(MvRadius.field),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(MvRadius.field),
                    onTap: () => context.go('/shop'),
                    child: const SizedBox(width: 38, height: 36, child: Icon(Icons.tune_rounded, size: 18, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed out: Sign in / Create account. Signed in: the person's account.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = user;
    if (u == null) {
      return PopupMenuButton<String>(
        tooltip: 'Sign in or create an account',
        icon: MvIcon('user', size: 22, color: context.mv.text, strokeWidth: 1.5),
        padding: EdgeInsets.zero,
        onSelected: (v) {
          if (v == 'login') {
            context.push('/login?next=${Uri.encodeQueryComponent(_here(context))}');
          } else {
            context.push('/signup');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'login', child: Text('Sign in')),
          PopupMenuItem(value: 'signup', child: Text('Create account')),
        ],
      );
    }
    final dashboard = roleHome[u.role];
    return PopupMenuButton<String>(
      tooltip: 'Account',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 46),
      icon: Avatar(name: u.fullName, url: u.avatarUrl, radius: 14),
      onSelected: (v) async {
        switch (v) {
          case 'profile':
            context.go('/profile');
          case 'orders':
            context.go('/orders');
          case 'dashboard':
            context.go(dashboard!);
          case 'notifications':
            context.go('/buyer/notifications');
          case 'logout':
            await ref.read(authProvider.notifier).logout();
            if (context.mounted) context.go('/');
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(u.fullName.isEmpty ? 'My account' : u.fullName, style: const TextStyle(fontWeight: FontWeight.w700))),
        const PopupMenuItem(value: 'profile', child: Text('My account')),
        const PopupMenuItem(value: 'orders', child: Text('My orders')),
        const PopupMenuItem(value: 'notifications', child: Text('Notifications')),
        if (dashboard != null) const PopupMenuItem(value: 'dashboard', child: Text('Dashboard')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Text('Sign out')),
      ],
    );
  }
}

String _here(BuildContext context) {
  final uri = GoRouterState.of(context).uri;
  return uri.toString();
}

// ─── Bottom navigation ───────────────────────────────────────────────────────

/// A floating rounded bar: the active destination gets a filled teal badge
/// behind its icon (the Furniture Store design), labels stay visible.
class MarketBottomBar extends StatelessWidget {
  const MarketBottomBar({super.key, required this.activeIndex});
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Container(
          height: 66,
          decoration: BoxDecoration(
            color: mv.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: mv.border),
            boxShadow: [BoxShadow(color: mv.shadow, blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              for (var i = 0; i < _destinations.length; i++)
                Expanded(
                  child: _BarItem(
                    dest: _destinations[i],
                    active: i == activeIndex,
                    onTap: () => context.go(_destinations[i].location),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.dest, required this.active, required this.onTap});
  final _Dest dest;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final color = active ? mv.accentDeep : mv.textMuted;
    return Semantics(
      button: true,
      selected: active,
      label: dest.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 46,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? mv.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: MvIcon(dest.icon, size: 20, color: active ? Colors.white : mv.textMuted, strokeWidth: active ? 1.7 : 1.5),
            ),
            const SizedBox(height: 3),
            Text(
              dest.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Left sidebar ────────────────────────────────────────────────────────────

/// The sidebar and the frosted backdrop behind it. One controller drives both:
/// the white panel slides in from the left while the page behind it blurs and
/// dims, and a drag from the left edge (or on the panel / backdrop) moves it.
class _SidebarLayer extends StatelessWidget {
  const _SidebarLayer({required this.controller, required this.location, required this.onClose});
  final AnimationController controller;
  final Uri location;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth = (size.width * .8).clamp(260.0, 330.0);
    final edge = 20.0 + MediaQuery.systemGestureInsetsOf(context).left;

    void drag(DragUpdateDetails d) => controller.value = (controller.value + d.delta.dx / panelWidth).clamp(0.0, 1.0);
    void settle(DragEndDetails d) {
      final v = d.velocity.pixelsPerSecond.dx;
      if (v.abs() > 500) {
        controller.fling(velocity: v > 0 ? 2.2 : -2.2);
      } else {
        controller.fling(velocity: controller.value > .5 ? 2.2 : -2.2);
      }
    }

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final v = Curves.easeOutCubic.transform(controller.value);
          if (controller.value == 0) {
            // Closed: only the thin strip on the left edge that pulls the sidebar out.
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: edge,
                  child: GestureDetector(behavior: HitTestBehavior.translucent, onHorizontalDragUpdate: drag, onHorizontalDragEnd: settle),
                ),
              ],
            );
          }
          return Stack(
            children: [
              // Frosted backdrop: blurs and dims the page; tapping it closes the sidebar.
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: 'Close menu',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    onHorizontalDragUpdate: drag,
                    onHorizontalDragEnd: settle,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 7 * v, sigmaY: 7 * v),
                        child: ColoredBox(color: Colors.black.withValues(alpha: .28 * v)),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: FractionalTranslation(
                  translation: Offset(-(1 - controller.value), 0),
                  child: GestureDetector(
                    onHorizontalDragUpdate: drag,
                    onHorizontalDragEnd: settle,
                    child: MarketplaceDrawer(location: location, onClose: onClose),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The sidebar panel: white, rounded on the right, with soft grey rows
/// (the Landing page sidebar design).
class MarketplaceDrawer extends ConsumerStatefulWidget {
  const MarketplaceDrawer({super.key, required this.location, required this.onClose});
  final Uri location;
  final VoidCallback onClose;

  @override
  ConsumerState<MarketplaceDrawer> createState() => _MarketplaceDrawerState();
}

class _MarketplaceDrawerState extends ConsumerState<MarketplaceDrawer> {
  bool _categoriesOpen = false;

  void _go(String location) {
    widget.onClose();
    context.go(location);
  }

  void _push(String location) {
    widget.onClose();
    context.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final user = ref.watch(authProvider.select((a) => a.user));
    final unread = ref.watch(unreadProvider);
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final dashboard = user == null ? null : roleHome[user.role];
    final active = _activeIndex(widget.location);
    final path = widget.location.path;

    Widget link(String label, String icon, String location, {bool selected = false, int badge = 0}) => _DrawerLink(
          label: label,
          icon: mvIcon(icon),
          svg: icon,
          selected: selected,
          badge: badge,
          onTap: () => _go(location),
        );

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: 'Menu',
      child: Material(
        color: mv.surface,
        elevation: 16,
        shadowColor: Colors.black54,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(MvRadius.sheet + 4)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 16, 4),
                child: Row(
                  children: [
                    Tooltip(
                      message: 'Close menu',
                      child: InkResponse(
                        onTap: widget.onClose,
                        radius: 24,
                        child: SizedBox(width: 44, height: 44, child: Center(child: MvIcon('menu', size: 22, color: mv.text, strokeWidth: 1.6))),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: MvLogo(size: 28)))),
                  ],
                ),
              ),
              if (user != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Material(
                    color: mv.surfaceMuted,
                    borderRadius: BorderRadius.circular(MvRadius.card),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(MvRadius.card),
                      onTap: () => _go('/profile'),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Avatar(name: user.fullName, url: user.avatarUrl, radius: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.fullName.isEmpty ? 'MVEC user' : user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 14)),
                                  Text(_roleLabel(user.role), style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: mv.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Row(
                    children: [
                      Expanded(child: GradientButton(label: 'Sign in', compact: true, onPressed: () => _push('/login'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlineBtn(label: 'Sign up', compact: true, onPressed: () => _push('/signup'))),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                  children: [
                    const _DrawerHeading('Shop'),
                    link('Home', 'home', '/', selected: active == 0),
                    link('Shop', 'shop', '/shop', selected: active == 1),
                    link('For You', 'heart', '/buyer/recommendations', selected: active == 2),
                    link('Deals', 'tag', '/shop?deal=true', selected: active == 3),
                    link('Stores', 'users', '/vendors', selected: path.startsWith('/vendors')),
                    _DrawerLink(
                      label: 'Categories',
                      icon: Icons.category_outlined,
                      selected: false,
                      trailing: Icon(_categoriesOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: mv.textMuted),
                      onTap: () => setState(() => _categoriesOpen = !_categoriesOpen),
                    ),
                    if (_categoriesOpen)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          children: [
                            if (catalog == null || catalog.categories.isEmpty)
                              Padding(padding: const EdgeInsets.all(10), child: Text('No categories yet', style: TextStyle(color: mv.textMuted, fontSize: 12.5)))
                            else
                              for (final c in catalog.categories)
                                _DrawerLink(
                                  label: c.name,
                                  icon: Icons.chevron_right_rounded,
                                  dense: true,
                                  onTap: () => _go('/shop?category=${Uri.encodeQueryComponent(c.name)}'),
                                ),
                          ],
                        ),
                      ),
                    const _DrawerHeading('My MVEC'),
                    link('Orders', 'box', '/orders', selected: active == 4),
                    link('Wishlist', 'heart', '/wishlist', selected: path == '/wishlist'),
                    link('Cart', 'cart', '/cart', selected: path == '/cart'),
                    if (user != null) ...[
                      link('Notifications', 'bell', '/buyer/notifications', selected: path == '/buyer/notifications', badge: unread),
                      link('Messages', 'users', '/buyer/messages', selected: path == '/buyer/messages'),
                      link('Refunds', 'wallet', '/buyer/refunds', selected: path == '/buyer/refunds'),
                      if (user.role == 'buyer') link('Subscription', 'wallet', '/buyer/subscription', selected: path == '/buyer/subscription'),
                      link('My account', 'user', '/profile', selected: path == '/profile'),
                    ],
                    link('Compare', 'compare', '/buyer/compare', selected: path == '/buyer/compare'),
                    link('Help & Support', 'bell', '/buyer/support', selected: path == '/buyer/support'),
                    if (dashboard != null) ...[
                      const _DrawerHeading('Workspace'),
                      link('Dashboard', 'grid', dashboard),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: user == null
                    ? _DrawerLink(
                        label: 'Become a vendor',
                        icon: mvIcon('shop'),
                        svg: 'shop',
                        onTap: () => _push('/signup?role=vendor'),
                      )
                    : _DrawerLink(
                        label: 'Sign out',
                        icon: mvIcon('logout'),
                        svg: 'logout',
                        onTap: () async {
                          widget.onClose();
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) context.go('/');
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _roleLabel(String role) => const {
      'buyer': 'Buyer',
      'vendor': 'Vendor',
      'supplier': 'Supplier',
      'affiliate': 'Affiliate',
      'super_admin': 'Super Admin',
      'delivery': 'Delivery',
    }[role] ??
    statusLabel(role);

class _DrawerHeading extends StatelessWidget {
  const _DrawerHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: context.mv.textMuted)),
      );
}

/// A soft grey pill row. The selected row turns teal-tinted.
class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
    this.trailing,
    this.dense = false,
    this.svg,
  });
  final String label;
  final IconData icon;
  final String? svg;
  final VoidCallback onTap;
  final bool selected;
  final int badge;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final color = selected ? mv.accentDeep : mv.text;
    final iconColor = selected ? mv.accentDeep : mv.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? mv.soft : (dense ? Colors.transparent : mv.surfaceMuted),
        borderRadius: BorderRadius.circular(MvRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(MvRadius.card),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 9 : 13),
            child: Row(
              children: [
                svg != null ? MvIcon(svg!, size: 19, color: iconColor, strokeWidth: 1.6) : Icon(icon, size: dense ? 17 : 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: dense ? 13 : 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: color))),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: mv.accent, borderRadius: BorderRadius.circular(9)),
                    child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ),
                if (selected && badge == 0 && trailing == null) Container(width: 7, height: 7, decoration: BoxDecoration(color: mv.accent, shape: BoxShape.circle)),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Search ──────────────────────────────────────────────────────────────────

/// Full-screen product / store search with live suggestions
/// (the header search + suggestions of the web storefront).
class ProductSearchDelegate extends SearchDelegate<String?> {
  ProductSearchDelegate(this.ref) : super(searchFieldLabel: 'Search products, brands, stores…');
  final WidgetRef ref;

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    final mv = context.mv;
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: mv.surface, elevation: 0),
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.close_rounded), tooltip: 'Clear'),
      ];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back');

  @override
  void showResults(BuildContext context) {
    if (query.trim().isEmpty) return;
    close(context, query);
  }

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final mv = context.mv;
    final catalog = ref.read(catalogProvider).valueOrNull;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return Center(child: Text('Search by name, SKU, brand, category or store.', style: TextStyle(color: mv.textMuted)));
    }
    final products = (catalog?.products ?? const [])
        .where((p) => '${p.name} ${p.brand} ${p.vendor} ${p.category}'.toLowerCase().contains(q))
        .take(6)
        .toList();
    final stores = (catalog?.stores ?? const [])
        .where((s) => '${s.name} ${s.category}'.toLowerCase().contains(q))
        .take(3)
        .toList();
    return ListView(
      children: [
        for (final p in products)
          ListTile(
            leading: SizedBox(width: 46, height: 46, child: ProductImage(src: p.image, radius: 8)),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${p.category} · ${money(p.price)}'),
            onTap: () {
              close(context, null);
              context.push('/product/${p.id}');
            },
          ),
        for (final s in stores)
          ListTile(
            leading: Avatar(name: s.name, url: s.logoUrl),
            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Store · ${s.category}'),
            onTap: () {
              close(context, null);
              context.push('/vendors/${s.id}');
            },
          ),
        if (products.isEmpty && stores.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No matching products or stores', style: TextStyle(color: mv.textMuted)))),
        ListTile(
          leading: Icon(Icons.search_rounded, color: mv.accentDeep),
          title: Text('View all results for “${query.trim()}”', style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w700)),
          onTap: () => close(context, query),
        ),
      ],
    );
  }
}
