import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/app_theme.dart';
import '../../data/models/category_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/vendor_model.dart';
import '../providers/home_provider.dart';
import '../Widgets/banner_carousel.dart';
import '../Widgets/category_grid.dart';
import '../Widgets/product_card.dart';
import '../Widgets/vendor_card.dart';

/// Marketplace home feed.
///
/// Renders the banner carousel, category grid, featured products,
/// recommended products, and featured vendors from [HomeProvider].
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onSearchTap, this.onBrowseAll});

  /// Switches the top navigation to the Search tab.
  final VoidCallback? onSearchTap;

  /// Switches the top navigation to the Shop tab (All Categories).
  final VoidCallback? onBrowseAll;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();

    if (provider.isLoading && provider.feed.banners.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final categories = provider.categories;
    final visibleCategories =
        categories.length > 8 ? categories.sublist(0, 8) : categories;

    return RefreshIndicator(
      onRefresh: provider.loadHomeFeed,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SearchBar(onTap: onSearchTap),
          const SizedBox(height: 12),
          if (provider.isDemo) const _DemoNotice(),
          const SizedBox(height: 12),
          BannerCarousel(banners: provider.banners),
          const SizedBox(height: 20),
          if (visibleCategories.isNotEmpty) ...<Widget>[
            _SectionHeader(
              title: 'All Categories',
              actionLabel: 'See all',
              onAction: onBrowseAll,
            ),
            const SizedBox(height: 12),
            CategoryGrid(
              categories: visibleCategories,
              onCategoryTap: (category) => _onCategoryTap(context, category),
            ),
            const SizedBox(height: 20),
          ],
          if (provider.featuredProducts.isNotEmpty) ...<Widget>[
            _SectionHeader(title: 'Featured Products'),
            const SizedBox(height: 12),
            _ProductRow(products: provider.featuredProducts),
            const SizedBox(height: 20),
          ],
          if (provider.recommendedProducts.isNotEmpty) ...<Widget>[
            _SectionHeader(title: 'Recommended For You'),
            const SizedBox(height: 12),
            _ProductRow(products: provider.recommendedProducts),
            const SizedBox(height: 20),
          ],
          if (provider.vendors.isNotEmpty) ...<Widget>[
            _SectionHeader(title: 'Trusted Vendors'),
            const SizedBox(height: 12),
            _VendorRow(vendors: provider.vendors),
          ],
        ],
      ),
    );
  }

  void _onCategoryTap(BuildContext context, Category category) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Showing ${category.name} (${category.productCount} items)'),
      ),
    );
  }
}

/// Small notice shown when the feed is served from the mock service.
class _DemoNotice extends StatelessWidget {
  const _DemoNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.warning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are previewing demo data. Live products will appear when '
              'the marketplace API is connected.',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fake search field that routes to the Search tab.
class _SearchBar extends StatelessWidget {
  const _SearchBar({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Search products, brands & more',
                style: AppTextStyles.bodySecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section title row with an optional trailing action.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTextStyles.sectionTitle(context)),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                color: AppColors.primaryDeep,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

/// Horizontal scrolling list of products.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<HomeProvider>();
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(
            product: product,
            onTap: () {
              provider.addRecentlyViewed(product);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${product.name} added to your For You')),
              );
            },
          );
        },
      ),
    );
  }
}

/// Horizontal scrolling list of featured vendors.
class _VendorRow extends StatelessWidget {
  const _VendorRow({required this.vendors});

  final List<Vendor> vendors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vendors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final vendor = vendors[index];
          return VendorCard(
            vendor: vendor,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Opening ${vendor.name} store')),
              );
            },
          );
        },
      ),
    );
  }
}