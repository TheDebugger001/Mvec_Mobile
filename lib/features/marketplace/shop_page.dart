import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/catalog_state.dart';
import '../../widgets/common.dart';
import 'product_card.dart';

const _perPage = 12;

/// `/shop` and `/shop?deal=true` — filters live in the URL like the web app
/// (`q`, `category`, `deal`, `stock`, `sort`, `min`, `max`, `page`).
class ShopPage extends ConsumerWidget {
  const ShopPage({super.key, required this.params});
  final Map<String, String> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final q = params['q'] ?? '';
    final cat = params['category'] ?? '';
    final dealsOnly = params['deal'] == 'true';
    final inStock = params['stock'] == '1';
    final sort = params['sort'] ?? 'newest';
    final minPrice = num.tryParse(params['min'] ?? '') ?? 0;
    final maxPrice = num.tryParse(params['max'] ?? '') ?? 0;
    final page = (int.tryParse(params['page'] ?? '') ?? 1).clamp(1, 9999);

    void update(Map<String, String?> changes) {
      final next = Map<String, String>.from(params);
      changes.forEach((k, v) {
        if (v == null || v.isEmpty) {
          next.remove(k);
        } else {
          next[k] = v;
        }
      });
      if (!changes.containsKey('page')) next.remove('page');
      final qs = next.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      context.go(qs.isEmpty ? '/shop' : '/shop?$qs');
    }

    final catalog = ref.watch(catalogProvider);
    return catalog.when(
      loading: () => const SingleChildScrollView(padding: EdgeInsets.all(16), child: ProductGridSkeleton(count: 6)),
      error:
          (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(catalogProvider),
          ),
      data: (c) {
        final needle = q.trim().toLowerCase();
        var list =
            c.products.where((p) {
              return (cat.isEmpty || p.category == cat) &&
                  (!dealsOnly || p.onSale) &&
                  (!inStock || p.stock > 0) &&
                  (needle.isEmpty ||
                      '${p.name} ${p.brand} ${p.vendor} ${p.sku} ${p.category} ${p.description}'
                          .toLowerCase()
                          .contains(needle)) &&
                  (minPrice == 0 || p.price >= minPrice) &&
                  (maxPrice == 0 || p.price <= maxPrice);
            }).toList();
        switch (sort) {
          case 'price-low':
            list.sort((a, b) => a.price.compareTo(b.price));
          case 'price-high':
            list.sort((a, b) => b.price.compareTo(a.price));
          case 'rating':
            list.sort((a, b) {
              final r = b.rating.compareTo(a.rating);
              return r != 0 ? r : b.reviews.compareTo(a.reviews);
            });
        }
        // Sold-out items go last.
        list = [
          ...list.where((p) => p.stock > 0),
          ...list.where((p) => p.stock <= 0),
        ];
        final pages = (list.length / _perPage).ceil().clamp(1, 9999);
        final current = page.clamp(1, pages);
        final shown =
            list.skip((current - 1) * _perPage).take(_perPage).toList();
        final hasFilters =
            q.isNotEmpty ||
            cat.isNotEmpty ||
            dealsOnly ||
            inStock ||
            minPrice > 0 ||
            maxPrice > 0;

        return RefreshIndicator(
          onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: PageTitle(
                    eyebrow: 'MVEC Marketplace',
                    title:
                        dealsOnly
                            ? 'Deals'
                            : (cat.isEmpty ? 'Shop products' : cat),
                    subtitle:
                        q.isNotEmpty
                            ? 'Results for “$q”'
                            : 'Search by name, SKU, brand, category or vendor.',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _Chip(
                        label: 'All',
                        selected: cat.isEmpty,
                        onTap: () => update({'category': null}),
                      ),
                      for (final name in c.categoryNames)
                        _Chip(
                          label: name,
                          selected: cat == name,
                          onTap: () => update({'category': name}),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${list.length} product${list.length == 1 ? "" : "s"}',
                              style: TextStyle(
                                color: mv.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Sort products',
                            icon: const Icon(Icons.sort_rounded),
                            initialValue: sort,
                            onSelected:
                                (v) =>
                                    update({'sort': v == 'newest' ? null : v}),
                            itemBuilder:
                                (_) => const [
                                  PopupMenuItem(
                                    value: 'newest',
                                    child: Text('Newest'),
                                  ),
                                  PopupMenuItem(
                                    value: 'rating',
                                    child: Text('Top rated'),
                                  ),
                                  PopupMenuItem(
                                    value: 'price-low',
                                    child: Text('Price: low to high'),
                                  ),
                                  PopupMenuItem(
                                    value: 'price-high',
                                    child: Text('Price: high to low'),
                                  ),
                                ],
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('On sale'),
                            selected: dealsOnly,
                            onSelected:
                                (v) => update({'deal': v ? 'true' : null}),
                          ),
                          FilterChip(
                            label: const Text('In stock'),
                            selected: inStock,
                            onSelected:
                                (v) => update({'stock': v ? '1' : null}),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (c.error)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Notice(
                      text:
                          'We could not load products right now. Pull down to refresh.',
                    ),
                  ),
                ),
              if (shown.isEmpty && !c.error)
                SliverToBoxAdapter(
                  child: EmptyState(
                    title: 'No products found',
                    message: 'Try another search or remove a filter.',
                    action:
                        hasFilters
                            ? OutlineBtn(
                              label: 'Clear filters',
                              compact: true,
                              onPressed: () => context.go('/shop'),
                            )
                            : null,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: ProductGridSliver(products: shown),
                ),
              SliverToBoxAdapter(
                child: PaginationBar(
                  page: current,
                  total: list.length,
                  perPage: _perPage,
                  onPage: (n) => update({'page': n > 1 ? '$n' : null}),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          color: selected ? Colors.white : mv.text,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        showCheckmark: false,
      ),
    );
  }
}

/// Used by tests and the For You page to show a plain product grid.
class ProductGridPage extends StatelessWidget {
  const ProductGridPage({super.key, required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(14),
        sliver: ProductGridSliver(products: products),
      ),
    ],
  );
}
