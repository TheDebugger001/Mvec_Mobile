import 'package:flutter/material.dart';

import '../../../../core/utils/app_theme.dart';
import 'categories_screen.dart';
import 'deals_screen.dart';
import 'for_you_screen.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
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

  void _select(TopMenuItem item) => setState(() => _selected = item);

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
                  const CategoriesScreen(),
                  HomeScreen(
                    onSearchTap: () => _select(TopMenuItem.search),
                    onBrowseAll: () => _select(TopMenuItem.shop),
                  ),
                  const ShopScreen(),
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
class _TopMenuBar extends StatelessWidget {
  const _TopMenuBar({required this.selected, required this.onSelected});

  final TopMenuItem selected;
  final ValueChanged<TopMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        side: BorderSide(
          color: active ? Colors.transparent : AppColors.border,
        ),
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