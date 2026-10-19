import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/format.dart';
import '../core/icons.dart';
import '../core/nav_items.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../state/auth_state.dart';
import '../state/cart_state.dart';
import '../state/catalog_state.dart';
import '../state/notifications_state.dart';
import '../widgets/common.dart';

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

/// Storefront frame: top bar (menu, search, theme, wishlist, cart, account),
/// left sidebar, and the five-item bottom navigation.
class MarketplaceShell extends ConsumerWidget {
  const MarketplaceShell({super.key, required this.child, required this.uri});
  final Widget child;
  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final cartNotice = ref.watch(cartProvider.select((c) => c.notice));
    return Scaffold(
      appBar: const PreferredSize(preferredSize: Size.fromHeight(60), child: _TopBar()),
      drawer: MarketplaceDrawer(location: uri),
      body: Column(
        children: [
          if (cartNotice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Notice(text: cartNotice, onClose: () => ref.read(cartProvider.notifier).dismissNotice()),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: keyboard ? null : MarketBottomBar(activeIndex: _activeIndex(uri)),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final cartCount = ref.watch(cartProvider.select((c) => c.count));
    final wishCount = ref.watch(wishlistProvider.select((w) => w.length));
    final user = ref.watch(authProvider.select((a) => a.user));
    final dark = context.isDarkMode;

    return Material(
      color: dark ? MvColors.darkHeaderBg : mv.surface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: mv.border))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => _BarIcon(
                      icon: Icons.menu_rounded,
                      tooltip: 'Open menu',
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const Expanded(child: _SearchPill()),
                  const SizedBox(width: 2),
                  _BarIcon(
                    icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
                    onTap: () => ref.read(themeModeProvider.notifier).set(dark ? ThemeMode.light : ThemeMode.dark),
                  ),
                  _BarIcon(
                    icon: Icons.favorite_border_rounded,
                    tooltip: 'Wishlist, $wishCount items',
                    badge: wishCount,
                    onTap: () => context.go('/wishlist'),
                  ),
                  _BarIcon(
                    icon: Icons.shopping_cart_outlined,
                    tooltip: 'Cart, $cartCount items',
                    badge: cartCount,
                    onTap: () => context.go('/cart'),
                  ),
                  _AccountMenu(user: user),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});
  final IconData icon;
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
          width: 38,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 23, color: mv.text),
              if (badge > 0)
                Positioned(
                  right: 1,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: MvColors.skyBlue,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: mv.surface, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, height: 1),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: 'Search products',
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () async {
            final q = await showSearch<String?>(context: context, delegate: ProductSearchDelegate(ref));
            if (q != null && q.trim().isNotEmpty && context.mounted) {
              context.go('/shop?q=${Uri.encodeQueryComponent(q.trim())}');
            }
          },
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: mv.surfaceMuted,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: mv.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 19, color: mv.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Search products…', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 13.5)),
                ),
              ],
            ),
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
        icon: Icon(Icons.person_outline_rounded, size: 24, color: context.mv.text),
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
        PopupMenuItem(enabled: false, child: Text(u.fullName.isEmpty ? 'My account' : u.fullName, style: const TextStyle(fontWeight: FontWeight.w800))),
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

class MarketBottomBar extends StatelessWidget {
  const MarketBottomBar({super.key, required this.activeIndex});
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Container(
      decoration: BoxDecoration(
        color: mv.surface,
        border: Border(top: BorderSide(color: mv.border)),
        boxShadow: [BoxShadow(color: mv.shadow, blurRadius: 14, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: active ? mv.soft : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(mvIcon(dest.icon), size: 22, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              dest.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Left sidebar ────────────────────────────────────────────────────────────

class MarketplaceDrawer extends ConsumerStatefulWidget {
  const MarketplaceDrawer({super.key, required this.location});
  final Uri location;

  @override
  ConsumerState<MarketplaceDrawer> createState() => _MarketplaceDrawerState();
}

class _MarketplaceDrawerState extends ConsumerState<MarketplaceDrawer> {
  bool _categoriesOpen = false;

  void _go(String location) {
    Navigator.of(context).pop();
    context.go(location);
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
          selected: selected,
          badge: badge,
          onTap: () => _go(location),
        );

    return Drawer(
      width: 304,
      backgroundColor: mv.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
              child: Row(
                children: [
                  const MvLogo(size: 30),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('MARKETPLACE', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: mv.textMuted)),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded), tooltip: 'Close menu'),
                ],
              ),
            ),
            if (user != null)
              InkWell(
                onTap: () => _go('/profile'),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Avatar(name: user.fullName, url: user.avatarUrl, radius: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullName.isEmpty ? 'MVEC user' : user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: mv.text, fontSize: 14)),
                            Text(_roleLabel(user.role), style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: mv.textMuted),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(child: GradientButton(label: 'Sign in', compact: true, onPressed: () { Navigator.of(context).pop(); context.push('/login'); })),
                    const SizedBox(width: 8),
                    Expanded(child: OutlineBtn(label: 'Sign up', compact: true, onPressed: () { Navigator.of(context).pop(); context.push('/signup'); })),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
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
                      padding: const EdgeInsets.only(left: 18),
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
                  link('Compare', 'chart', '/buyer/compare', selected: path == '/buyer/compare'),
                  link('Help & Support', 'bell', '/buyer/support', selected: path == '/buyer/support'),
                  if (dashboard != null) ...[
                    const _DrawerHeading('Workspace'),
                    link('Dashboard', 'grid', dashboard),
                  ],
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: mv.border))),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: user == null
                  ? _DrawerLink(
                      label: 'Become a vendor',
                      icon: mvIcon('shop'),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/signup?role=vendor');
                      },
                    )
                  : _DrawerLink(
                      label: 'Sign out',
                      icon: mvIcon('logout'),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await ref.read(authProvider.notifier).logout();
                        if (context.mounted) context.go('/');
                      },
                    ),
            ),
          ],
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
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: context.mv.textMuted)),
      );
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
    this.trailing,
    this.dense = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final int badge;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final dark = context.isDarkMode;
    final color = selected ? (dark ? MvColors.accentLight : mv.accentDeep) : mv.text;
    return Material(
      color: selected ? (dark ? const Color(0xFF123C4C) : mv.soft) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 8 : 11),
          child: Row(
            children: [
              Icon(icon, size: dense ? 17 : 20, color: selected ? color : mv.textMuted),
              const SizedBox(width: 12),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: dense ? 13 : 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: color))),
              if (badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: MvColors.skyBlue, borderRadius: BorderRadius.circular(9)),
                  child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              if (trailing != null) trailing!,
            ],
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
          title: Text('View all results for “${query.trim()}”', style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w800)),
          onTap: () => close(context, query),
        ),
      ],
    );
  }
}
