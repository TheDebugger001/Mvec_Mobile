import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/catalog_state.dart';
import '../../state/hero_state.dart';
import '../../widgets/common.dart';
import '../../widgets/mv_icon.dart';
import 'product_card.dart';

/// `/` — hero, categories, deals, popular products and top stores
/// (`pages/Home.jsx`, laid out for a phone).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(heroAdsProvider);
        await ref.read(catalogProvider.notifier).refresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverPadding(padding: EdgeInsets.fromLTRB(14, 14, 14, 0), sliver: SliverToBoxAdapter(child: _HeroCarousel())),
          ...catalog.when(
            loading: () => [const SliverToBoxAdapter(child: LoadingState(label: 'Loading the marketplace…'))],
            error: (e, _) => [SliverToBoxAdapter(child: ErrorState(error: e, onRetry: () => ref.invalidate(catalogProvider)))],
            data: (c) => [
              if (c.error)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Notice(text: 'We could not load the marketplace right now. Check your connection and try again.', onClose: () => ref.read(catalogProvider.notifier).refresh()),
                  ),
                ),
              if (c.categories.isNotEmpty) SliverToBoxAdapter(child: _Categories(categories: c.categories)),
              if (c.deals.isNotEmpty) ...[
                _heading('Deals of the Day', onAll: () => context.go('/shop?deal=true')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 252,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: c.deals.length.clamp(0, 10),
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => ProductCard(product: c.deals[i], width: 158),
                    ),
                  ),
                ),
              ],
              _heading('Popular Products', onAll: () => context.go('/shop')),
              if (c.products.isEmpty && !c.error)
                const SliverToBoxAdapter(child: EmptyState(title: 'No products yet', message: 'Sellers are setting up their stores. Check back soon.'))
              else
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 14), sliver: ProductGridSliver(products: c.popular.take(8).toList())),
              if (c.stores.isNotEmpty) ...[
                _heading('Trusted Vendors', onAll: () => context.push('/vendors')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverList.separated(
                    itemCount: c.stores.take(4).length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => StoreTile(store: c.stores[i]),
                  ),
                ),
              ],
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _heading(String title, {required VoidCallback onAll}) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SectionHeading(title: title, actionLabel: 'View All  →', onAction: onAll),
        ),
      );
}

/// Store row used on Home and the stores list.
class StoreTile extends StatelessWidget {
  const StoreTile({super.key, required this.store});
  final StoreSummary store;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final s = store;
    return Material(
      color: mv.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/vendors/${s.id}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Avatar(name: s.name, url: s.logoUrl, radius: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: mv.text, fontSize: 13.5)),
                    Text(s.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                    Text('${s.rating > 0 ? '★ ${ratingLabel(s.rating)} · ' : ''}${s.products} product${s.products == 1 ? "" : "s"}${s.verified ? ' · Verified' : ''}',
                        style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: mv.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class _HeroSlide {
  const _HeroSlide({required this.eyebrow, required this.title, required this.line, required this.cta, required this.onTap, this.imageAsset, this.imageUrl});
  final String eyebrow;
  final String title;
  final String line;
  final String cta;
  final VoidCallback onTap;
  final String? imageAsset;
  final String? imageUrl;
}

class _HeroCarousel extends ConsumerStatefulWidget {
  const _HeroCarousel();

  @override
  ConsumerState<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<_HeroCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final count = _slides().length;
      if (!mounted || count < 2 || !_controller.hasClients) return;
      _controller.animateToPage((_index + 1) % count, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<_HeroSlide> _slides() {
    final ads = ref.read(heroAdsProvider).valueOrNull ?? const <Product>[];
    final slides = <_HeroSlide>[
      _HeroSlide(
        eyebrow: 'MVEC MARKETPLACE',
        title: 'Shop. Sell.\nGrow together.',
        line: 'Local sellers · Mobile money',
        cta: 'Shop now',
        imageAsset: 'assets/images/hero-standin.jpg',
        onTap: () => context.go('/shop'),
      ),
    ];
    for (final p in ads.take(5)) {
      slides.add(_HeroSlide(
        eyebrow: 'SPONSORED',
        title: p.name,
        line: money(p.price),
        cta: 'View',
        imageUrl: p.image,
        onTap: () => context.push('/product/${p.id}'),
      ));
    }
    return slides;
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    ref.watch(heroAdsProvider);
    final slides = _slides();
    final dark = context.isDarkMode;
    return Column(
      children: [
        Container(
          height: 184,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark ? const [Color(0xFF14313D), Color(0xFF1B4252)] : const [Color(0xFFEAF9FE), Color(0xFFCDEEFA)],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final s = slides[i];
              return Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mvEyebrow.copyWith(fontSize: 9.5)),
                          const SizedBox(height: 6),
                          Text(s.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.mvH1.copyWith(fontSize: 18, height: 1.15)),
                          const SizedBox(height: 6),
                          Text(s.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 12)),
                          const SizedBox(height: 12),
                          GradientButton(label: s.cta, compact: true, onPressed: s.onTap),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 9,
                    child: GestureDetector(
                      onTap: s.onTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox.expand(
                            child: s.imageAsset != null
                                ? Image.asset(s.imageAsset!, fit: BoxFit.cover)
                                : ProductImage(src: s.imageUrl),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _index ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(color: i == _index ? mv.accentDeep : mv.border, borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Category circles ────────────────────────────────────────────────────────

class _Categories extends StatelessWidget {
  const _Categories({required this.categories});
  final List<CategoryInfo> categories;

  static const _tints = [
    (Color(0xFFFFE8EF), Color(0xFFD81B60)),
    (Color(0xFFE3F1FF), Color(0xFF1E88E5)),
    (Color(0xFFFFF3DC), Color(0xFFB8860B)),
    (Color(0xFFE2F7EA), Color(0xFF2E9E5B)),
    (Color(0xFFEFE7FF), Color(0xFF6B46C1)),
  ];

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final dark = context.isDarkMode;
    final shown = categories.take(5).toList();
    Widget circle(Widget child, Color bg, String label, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: SizedBox(
            width: 64,
            child: Column(
              children: [
                Container(width: 56, height: 56, decoration: BoxDecoration(color: dark ? bg.withValues(alpha: .18) : bg, shape: BoxShape.circle), alignment: Alignment.center, child: child),
                const SizedBox(height: 6),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: mv.text)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: circle(
                  shown[i].imageUrl.isNotEmpty
                      ? ClipOval(child: SizedBox(width: 56, height: 56, child: ProductImage(src: shown[i].imageUrl)))
                      : MvIcon('tag', size: 22, color: _tints[i % 5].$2, strokeWidth: 1.5),
                  _tints[i % 5].$1,
                  shown[i].name,
                  () => context.go('/shop?category=${Uri.encodeQueryComponent(shown[i].name)}'),
                ),
              ),
            circle(MvIcon('grid', size: 22, color: mv.accentDeep, strokeWidth: 1.5), mv.soft, 'More', () => context.go('/shop')),
          ],
        ),
      ),
    );
  }
}
