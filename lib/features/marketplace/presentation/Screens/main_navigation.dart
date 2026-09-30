import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme.dart';
import '../../../../core/utils/app_theme.dart';
import '../../../../models/user.dart';
import '../../../../providers/auth_provider.dart';
import '../../data/models/category_model.dart';
import '../providers/commerce_provider.dart';
import '../providers/home_provider.dart';
import 'categories_screen.dart';
import 'deals_screen.dart';
import 'for_you_screen.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'product_navigation.dart';
import 'search_screen.dart';
import 'shop_screen.dart';
import 'vendors_screen.dart';

/// Root marketplace navigation container.
///
/// Floating bottom bar for the four primary tabs (Home, Shop, For You, Deals)
/// plus a top bar carrying search, wishlist, notifications, cart, the dark-mode
/// toggle and account actions, and an expandable category bar. The destinations
/// that do not fit in the bottom bar — All Categories, Vendors and Orders —
/// stay reachable from the category bar so nothing from the storefront top-menu
/// design is lost.
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

/// The four primary destinations, in bar order. The active tab and the sliding
/// indicator both read their accent from the shared sky-blue token.
const List<_NavTab> _tabs = <_NavTab>[
  _NavTab('Home', Icons.home_rounded),
  _NavTab('Shop', Icons.grid_view_rounded),
  _NavTab('For You', Icons.pie_chart_rounded),
  _NavTab('Deals', Icons.favorite_rounded),
];

@immutable
class _NavTab {
  const _NavTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;
  Category? _selectedCategory;
  bool _categoriesExpanded = true;

  void _select(int index) => setState(() => _currentIndex = index);

  void _toggleTheme() => ref.read(themeModeProvider.notifier).toggle();

  void _selectCategory(Category? category) {
    setState(() {
      _selectedCategory = category;
      // Jump to the Shop tab so the filtered catalog shows instantly.
      _currentIndex = 1;
    });
  }

  void _openAllProducts() {
    setState(() {
      _selectedCategory = null;
      _currentIndex = 1;
    });
  }

  // ---------------------------------------------------------------------------
  // Full-page destinations.
  // ---------------------------------------------------------------------------

  void _pushPage(Widget child, {String? title}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (routeContext) => Scaffold(
              backgroundColor: routeContext.mv.page,
              appBar: AppBar(title: Text(title ?? '')),
              body: SafeArea(child: child),
            ),
      ),
    );
  }

  void _openSearch() => _pushPage(const SearchScreen(), title: 'Search');

  void _openVendors() => _pushPage(const VendorsScreen(), title: 'Vendors');

  void _openOrders() => _pushPage(const OrdersScreen(), title: 'My Orders');

  void _openCategories() {
    _pushPage(
      CategoriesScreen(
        onCategoryTap: (category) {
          _selectCategory(category);
          Navigator.of(context).pop();
        },
      ),
      title: 'All Categories',
    );
  }

  void _openWishlist(BuildContext context) =>
      openWishlist(context, context.read<CommerceProvider>());

  void _openCart(BuildContext context) =>
      openCart(context, context.read<CommerceProvider>());

  // ---------------------------------------------------------------------------
  // Account sheet: identity, a shortcut to the dashboard for admins and sign out.
  // ---------------------------------------------------------------------------

  Future<void> _openProfile() async {
    final user = ref.read(currentUserProvider);
    final isDark = context.isDarkMode;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.mv.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetContext.mv.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _AccountHeader(user: user),
                const Divider(height: 26),
                if (user != null && user.userType == 'super_admin')
                  _SheetAction(
                    icon: Icons.dashboard_outlined,
                    label: 'Go to dashboard',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).pop();
                    },
                  ),
                _SheetAction(
                  icon: Icons.shopping_bag_outlined,
                  label: 'My orders',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openOrders();
                  },
                ),
                _SheetAction(
                  icon: Icons.favorite_border,
                  label: 'My wishlist',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openWishlist(context);
                  },
                ),
                _SheetAction(
                  icon: isDark ? Icons.light_mode : Icons.dark_mode,
                  label: isDark ? 'Light mode' : 'Dark mode',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _toggleTheme();
                  },
                ),
                _SheetAction(
                  icon: Icons.logout,
                  label: 'Sign out',
                  destructive: true,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await ref.read(authControllerProvider.notifier).logout();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();

    return Scaffold(
      backgroundColor: context.mv.page,

      body: SafeArea(
        child: Column(
          children: [
            _buildTopNavigation(context, provider.categories),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: <Widget>[
                  HomeScreen(
                    onBrowseAll: _openAllProducts,
                    onViewDeals: () => _select(3),
                    onCategoryTap: _selectCategory,
                  ),
                  ShopScreen(
                    key: ValueKey<int?>(_selectedCategory?.id),
                    initialCategory: _selectedCategory,
                  ),
                  const ForYouScreen(),
                  const DealsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildFloatingBottomNav(),
    );
  }

  // ---------------------------------------------------------------------------
  // Top navigation: back, search context, wishlist/notifications/cart badges,
  // the dark-mode toggle and the account menu.
  // ---------------------------------------------------------------------------

  Widget _buildTopNavigation(BuildContext context, List<Category> categories) {
    final commerce = context.watch<CommerceProvider>();
    final cartCount = commerce.cartItems.fold<int>(
      0,
      (count, item) => count + item.quantity,
    );

    return Container(
      color: context.mv.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 2, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed:
                      Navigator.of(context).canPop()
                          ? () => Navigator.maybePop(context)
                          : null,
                ),
                Expanded(child: _SearchTrigger(onTap: _openSearch)),
                _TopBarAction(
                  icon: Icons.favorite_border,
                  tooltip: 'Wishlist',
                  count: commerce.wishlistItems.length,
                  countKey: 'home-wishlist-count',
                  onPressed: () => _openWishlist(context),
                ),
                _TopBarAction(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notifications',
                  countKey: 'home-notifications-count',
                  onPressed: _openNotifications,
                ),
                _TopBarAction(
                  icon: Icons.shopping_bag_outlined,
                  tooltip: 'Cart',
                  count: cartCount,
                  countKey: 'home-cart-count',
                  onPressed: () => _openCart(context),
                ),
                _ThemeToggleButton(
                  isDark: context.isDarkMode,
                  onTap: _toggleTheme,
                ),
                IconButton(
                  tooltip: 'Account',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.person_outline),
                  onPressed: _openProfile,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _CategoriesBar(
            categories: categories,
            selected: _selectedCategory,
            expanded: _categoriesExpanded,
            onToggleExpanded:
                () =>
                    setState(() => _categoriesExpanded = !_categoriesExpanded),
            onSelected: _selectCategory,
            onOpenAllCategories: _openCategories,
            onOpenVendors: _openVendors,
            onOpenOrders: _openOrders,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  void _openNotifications() =>
      _pushPage(const _NotificationsPage(), title: 'Notifications');

  // ---------------------------------------------------------------------------
  // Floating bottom navigation bar: a rounded pill card that hovers above the
  // screen edge. Only the active tab's icon and label take the sky-blue accent,
  // and a small sky-blue pill slides underneath the active tab.
  // ---------------------------------------------------------------------------

  Widget _buildFloatingBottomNav() {
    final mv = context.mv;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          key: const ValueKey<String>('bottom-nav-bar'),
          height: 64,
          decoration: BoxDecoration(
            color: mv.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: mv.border),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: mv.shadow,
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / _tabs.length;
              const indicatorWidth = 20.0;
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      for (var i = 0; i < _tabs.length; i++)
                        _buildNavItem(i, _tabs[i]),
                    ],
                  ),
                  // The indicator rides beneath the active tab.
                  AnimatedPositioned(
                    key: const ValueKey<String>('bottom-nav-indicator'),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left:
                        tabWidth * _currentIndex +
                        (tabWidth - indicatorWidth) / 2,
                    bottom: 6,
                    width: indicatorWidth,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, _NavTab tab) {
    final selected = _currentIndex == index;
    final color = selected ? AppColors.primary : context.mv.textMuted;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: () => _select(index),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  scale: selected ? 1.1 : 1,
                  child: Icon(tab.icon, size: 22, color: color),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ---------------------------------------------------------------------------
// Search trigger shown in the top bar.
// ---------------------------------------------------------------------------

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 42,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: mv.surfaceMuted,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: mv.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.search, color: mv.textMuted, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Search products, brands & more',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mv.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wishlist/notification/cart icon button with a count badge, pinned to the
/// top bar. The badge uses the sky-blue accent rather than the M3 error red.
class _TopBarAction extends StatelessWidget {
  const _TopBarAction({
    required this.icon,
    required this.tooltip,
    required this.countKey,
    required this.onPressed,
    this.count = 0,
  });

  final IconData icon;
  final String tooltip;
  final int count;
  final String countKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Badge(
        key: ValueKey<String>(countKey),
        isLabelVisible: count > 0,
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(icon),
      ),
    );
  }
}

/// Dark-mode switch in the top bar. Rendered as a distinct circular control so
/// it reads as a mode switch rather than another top-bar shortcut.
class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder:
                (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
            child: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              key: ValueKey<bool>(isDark),
              size: 18,
              color: context.mv.accentDeep,
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder inbox: the storefront has no notification feed yet, but the
/// top-bar bell needs a destination so the action is never dead.
class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: context.mv.accentDeep,
            ),
            const SizedBox(height: 12),
            Text('No new notifications', style: AppTextStyles.title(context)),
            const SizedBox(height: 4),
            Text(
              'Order updates and vendor offers will show up here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expandable category bar with the storefront quick destinations.
// ---------------------------------------------------------------------------

class _CategoriesBar extends StatelessWidget {
  const _CategoriesBar({
    required this.categories,
    required this.selected,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelected,
    required this.onOpenAllCategories,
    required this.onOpenVendors,
    required this.onOpenOrders,
  });

  final List<Category> categories;
  final Category? selected;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Category?> onSelected;
  final VoidCallback onOpenAllCategories;
  final VoidCallback onOpenVendors;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Icon(Icons.category_outlined, size: 16, color: mv.accentDeep),
              const SizedBox(width: 6),
              Text(
                'Categories',
                style: AppTextStyles.caption(
                  context,
                ).copyWith(color: mv.text, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _QuickLink(
                icon: Icons.grid_view_outlined,
                tooltip: 'All Categories',
                onPressed: onOpenAllCategories,
              ),
              _QuickLink(
                icon: Icons.store_mall_directory_outlined,
                tooltip: 'Vendors',
                onPressed: onOpenVendors,
              ),
              _QuickLink(
                icon: Icons.receipt_long_outlined,
                tooltip: 'Orders',
                onPressed: onOpenOrders,
              ),
              IconButton(
                tooltip: expanded ? 'Collapse categories' : 'Expand categories',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: mv.textMuted,
                ),
                onPressed: onToggleExpanded,
              ),
            ],
          ),
        ),
        if (expanded)
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = index == 0 ? null : categories[index - 1];
                final active =
                    category == null
                        ? selected == null
                        : selected?.id == category.id;
                return _CategoryPill(
                  label: category?.name ?? 'All',
                  active: active,
                  onTap: () => onSelected(category),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Compact icon shortcut to a storefront section.
class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      icon: Icon(icon, color: context.mv.accentDeep),
    );
  }
}

/// Pill-style category chip; the active one fills with the sky-blue accent.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: active ? AppColors.primary : mv.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: AppColors.brandGradient),
            color: active ? null : mv.surface,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : mv.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account sheet widgets.
// ---------------------------------------------------------------------------

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({this.user});

  final UserRecord? user;

  @override
  Widget build(BuildContext context) {
    final name = user?.display ?? 'Guest';
    final detail = user?.email ?? user?.phone ?? 'Not signed in';
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              gradient: MvColors.gradient,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: mv.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: mv.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : context.mv.text;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: TextStyle(fontSize: 14, color: color)),
      onTap: onTap,
    );
  }
}
