import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/app_theme.dart';
import '../../data/models/category_model.dart';
import '../providers/commerce_provider.dart';
import 'categories_screen.dart';
import 'deals_screen.dart';
import 'for_you_screen.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'product_navigation.dart';
import 'search_screen.dart';
import 'shop_screen.dart';
import 'vendors_screen.dart';

/// The eight destinations exposed by the top menu bar.
enum TopMenuItem {
  search('Search', Icons.search_outlined),
  categories('All Categories', Icons.grid_view_outlined),
  home('Home', Icons.home_outlined),
  shop('Shop', Icons.storefront_outlined),
  forYou('For You', Icons.recommend_outlined),
  deals('Deals', Icons.local_fire_department_outlined),
  vendors('Vendors', Icons.store_mall_directory_outlined),
  orders('Orders', Icons.receipt_long_outlined);

  const TopMenuItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Root navigation container.
///
/// Renders a horizontal scrollable top menu bar with the marketplace tabs
/// (Search, All Categories, Home, Shop, For You, Deals, Vendors, Orders)
/// and swaps the body underneath. Home is the default active tab.
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  TopMenuItem _selected = TopMenuItem.home;
  Category? _selectedCategory;

  void _select(TopMenuItem item) => setState(() => _selected = item);

  void _openCategory(Category category) {
    setState(() {
      _selectedCategory = category;
      _selected = TopMenuItem.shop;
    });
  }

  void _openAllProducts() {
    setState(() {
      _selectedCategory = null;
      _selected = TopMenuItem.shop;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopMenuBar(selected: _selected, onSelected: _select),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: _selected.index,
                children: [
                  const SearchScreen(),
                  CategoriesScreen(onCategoryTap: _openCategory),
                  HomeScreen(
                    onSearchTap: () => _select(TopMenuItem.search),
                    onBrowseAll: _openAllProducts,
                    onCategoryTap: _openCategory,
                  ),
                  ShopScreen(
                    key: ValueKey<int?>(_selectedCategory?.id),
                    initialCategory: _selectedCategory,
                  ),
                  const ForYouScreen(),
                  const DealsScreen(),
                  const VendorsScreen(),
                  const OrdersScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal, scrollable top menu bar with pill-style tabs.
///
/// The wishlist and cart actions are pinned to the trailing edge so they
/// stay reachable from every tab instead of only the home feed.
class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar({required this.selected, required this.onSelected});

  final TopMenuItem selected;
  final ValueChanged<TopMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final commerce = context.watch<CommerceProvider>();

    return SizedBox(
      height: 58,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              scrollDirection: Axis.horizontal,
              itemCount: TopMenuItem.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = TopMenuItem.values[index];
                final isActive = item == selected;
                return _MenuPill(
                  item: item,
                  active: isActive,
                  onTap: () => onSelected(item),
                );
              },
            ),
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppColors.border,
          ),
          _TopBarAction(
            icon: Icons.favorite_border,
            tooltip: 'Wishlist',
            count: commerce.wishlistItems.length,
            countKey: 'home-wishlist-count',
            onPressed: () => openWishlist(context, commerce),
          ),
          _TopBarAction(
            icon: Icons.shopping_cart_outlined,
            tooltip: 'Cart',
            count: commerce.cartItemCount,
            countKey: 'home-cart-count',
            onPressed: () => openCart(context, commerce),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// Wishlist/cart icon button with a count badge, shown in the top menu bar.
class _TopBarAction extends StatelessWidget {
  const _TopBarAction({
    required this.icon,
    required this.tooltip,
    required this.count,
    required this.countKey,
    required this.onPressed,
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
      onPressed: onPressed,
      icon: Badge(
        key: ValueKey<String>(countKey),
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(icon),
      ),
    );
  }
}

class _MenuPill extends StatelessWidget {
  const _MenuPill({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final TopMenuItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: active ? Colors.transparent : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: active
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.brandGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
