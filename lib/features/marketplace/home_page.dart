import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/auth_state.dart';
import '../../state/catalog_state.dart';
import '../../state/hero_state.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import 'product_card.dart';

/// `/` — greeting, category pills, banner, deals, popular products and top stores
/// (`pages/Home.jsx`, laid out for a phone).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final user = ref.watch(authProvider.select((a) => a.user));
    final categories = catalog.valueOrNull?.categories ?? const <CategoryInfo>[];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(heroAdsProvider);
        await ref.read(catalogProvider.notifier).refresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _Greeting(name: user?.firstName ?? '')),
          SliverToBoxAdapter(child: _CategoryPills(categories: categories)),
          const SliverPadding(padding: EdgeInsets.fromLTRB(16, 14, 16, 0), sliver: SliverToBoxAdapter(child: _HeroCarousel())),
          ...catalog.when(
            loading: () => [
              _heading('Popular products', onAll: () => context.go('/shop')),
              const SliverPadding(padding: EdgeInsets.symmetric(horizontal: 16), sliver: SliverToBoxAdapter(child: ProductGridSkeleton())),
            ],
            error: (e, _) => [SliverToBoxAdapter(child: ErrorState(error: e, onRetry: () => ref.invalidate(catalogProvider)))],
            data: (c) => [
              if (c.error)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Notice(text: 'We could not load the marketplace right now. Check your connection and try again.', onClose: () => ref.read(catalogProvider.notifier).refresh()),
                  ),
                ),
              if (c.deals.isNotEmpty) ...[
                _heading('Deals of the day', onAll: () => context.go('/shop?deal=true')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: ProductCard.heightFor(_kCarouselCard) + 16,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      // Room for the card shadows; the next card peeks in to show there is more.
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                      itemCount: c.deals.length.clamp(0, 10),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => ProductCard(product: c.deals[i], width: _kCarouselCard),
                    ),
                  ),
                ),
              ],
              _heading('Popular products', onAll: () => context.go('/shop')),
              if (c.products.isEmpty && !c.error)
                const SliverToBoxAdapter(child: EmptyState(title: 'No products yet', message: 'Sellers are setting up their stores. Check back soon.'))
              else
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: ProductGridSliver(products: c.popular.take(8).toList())),
              if (c.stores.isNotEmpty) ...[
                _heading('Trusted vendors', onAll: () => context.push('/vendors')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: c.stores.take(4).length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => StoreTile(store: c.stores[i]),
                  ),
                ),
              ],
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _heading(String title, {required VoidCallback onAll}) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 0),
          child: SectionHeading(title: title, actionLabel: 'See all', onAction: onAll),
        ),
      );
}

const double _kCarouselCard = 164;

/// "Hi, Aline" and a one-line prompt above the category pills.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.isEmpty ? 'Welcome to MVEC' : 'Hi, $name', style: TextStyle(color: mv.textMuted, fontSize: 13.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text('What are you shopping for today?', style: context.mvH1.copyWith(fontSize: 21, height: 1.2)),
        ],
      ),
    );
  }
}

/// "All" plus the marketplace's real categories, as tappable pills.
class _CategoryPills extends StatelessWidget {
  const _CategoryPills({required this.categories});
  final List<CategoryInfo> categories;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final dark = context.isDarkMode;
    Widget pill(String label, VoidCallback onTap, {bool first = false, String image = ''}) => Pressable(
          scale: .94,
          child: Material(
            color: first ? (dark ? MvColors.accentLight : MvColors.navy) : mv.surface,
            shape: StadiumBorder(side: first ? BorderSide.none : BorderSide(color: mv.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(image.isEmpty ? 16 : 5, 5, 16, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (image.isNotEmpty) ...[
                      ClipOval(child: SizedBox(width: 26, height: 26, child: ProductImage(src: image))),
                      const SizedBox(width: 8),
                    ],
                    Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: first ? (dark ? MvColors.darkPage : Colors.white) : mv.text)),
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            pill('All', () => context.go('/shop'), first: true),
            for (final c in categories.take(10)) ...[
              const SizedBox(width: 8),
              pill(c.name, () => context.go('/shop?category=${Uri.encodeQueryComponent(c.name)}'), image: c.imageUrl),
            ],
          ],
        ),
      ),
    );
  }
}

/// Store row used on Home and the stores list.
class StoreTile extends StatelessWidget {
  const StoreTile({super.key, required this.store});
  final StoreSummary store;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final s = store;
    return Pressable(
      scale: .98,
      child: Material(
      color: mv.surface,
      borderRadius: BorderRadius.circular(MvRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(MvRadius.card),
        onTap: () => context.push('/vendors/${s.id}'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(MvRadius.card)),
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
  int _index = 0;

  @override
  void dispose() {
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
    // Swiped by hand only: an auto-advancing banner moves things out from under a finger.
    return Column(
      children: [
        Container(
          height: 196,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark ? const [Color(0xFF14313D), Color(0xFF1B4252)] : const [Color(0xFFE6F7FE), Color(0xFFBDE9FA)],
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
                      padding: const EdgeInsets.fromLTRB(18, 16, 4, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mvEyebrow.copyWith(fontSize: 9.5)),
                          const SizedBox(height: 6),
                          Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.mvH1.copyWith(fontSize: 19, height: 1.12)),
                          const SizedBox(height: 4),
                          Text(s.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 12),
                          SolidButton(label: s.cta, compact: true, onPressed: s.onTap),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 9,
                    child: GestureDetector(
                      onTap: s.onTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
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
        if (slides.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: Motion.base,
                  curve: Motion.out,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == _index ? MvColors.primaryDark : mv.border, borderRadius: BorderRadius.circular(3)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

