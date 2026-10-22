import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/catalog_state.dart';
import '../../state/hero_state.dart';
import '../../widgets/common.dart';
import '../../widgets/mv_icon.dart';
import 'product_card.dart';

/// Width of a product card in the horizontal "Deals of the Day" strip.
const double _kDealCardWidth = 158;

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
          const SliverPadding(padding: EdgeInsets.fromLTRB(16, 14, 16, 0), sliver: SliverToBoxAdapter(child: _HeroCarousel())),
          ...catalog.when(
            loading: () => [const SliverPadding(padding: EdgeInsets.fromLTRB(16, 18, 16, 0), sliver: SliverToBoxAdapter(child: ProductGridSkeleton()))],
            error: (e, _) => [SliverToBoxAdapter(child: ErrorState(error: e, onRetry: () => ref.invalidate(catalogProvider)))],
            data: (c) => [
              if (c.error)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Notice(text: 'We could not load the marketplace right now. Check your connection and try again.', onClose: () => ref.read(catalogProvider.notifier).refresh()),
                  ),
                ),
              if (c.categories.isNotEmpty) SliverToBoxAdapter(child: _Categories(categories: c.categories)),
              if (c.deals.isNotEmpty) ...[
                _heading('Deals of the Day', onAll: () => context.go('/shop?deal=true')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: _kDealCardWidth + kProductCardInfoHeight + 8,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: c.deals.length.clamp(0, 10),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => ProductCard(product: c.deals[i], width: _kDealCardWidth),
                    ),
                  ),
                ),
              ],
              _heading('Popular Products', onAll: () => context.go('/shop')),
              if (c.products.isEmpty && !c.error)
                const SliverToBoxAdapter(child: EmptyState(title: 'No products yet', message: 'Sellers are setting up their stores. Check back soon.'))
              else
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: ProductGridSliver(products: c.popular.take(8).toList())),
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 22, 16, 0), child: _PromoBanner())),
              if (c.stores.isNotEmpty) ...[
                _heading('Trusted Vendors', onAll: () => context.push('/vendors')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: c.stores.take(4).length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => StoreTile(store: c.stores[i], width: 270),
                    ),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: SectionHeading(title: title, actionLabel: 'View All', onAction: onAll),
        ),
      );
}

/// Store row used on Home and the stores list. Pass [width] for the
/// horizontal strip on Home; without it the tile fills its row.
class StoreTile extends StatelessWidget {
  const StoreTile({super.key, required this.store, this.width});
  final StoreSummary store;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final s = store;
    return SizedBox(
      width: width,
      child: Material(
        color: mv.surface,
        borderRadius: BorderRadius.circular(MvRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(MvRadius.card),
          onTap: () => context.push('/vendors/${s.id}'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: mv.border),
              borderRadius: BorderRadius.circular(MvRadius.card),
              boxShadow: context.mvCardShadow,
            ),
            child: Row(
              children: [
                Avatar(name: s.name, url: s.logoUrl, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 14)),
                      Text(s.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                      const SizedBox(height: 2),
                      Text(
                        '${s.rating > 0 ? '★ ${ratingLabel(s.rating)} · ' : ''}${s.products} product${s.products == 1 ? "" : "s"}${s.verified ? ' · Verified' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: mv.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, color: mv.accentDeep, size: 18),
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
        eyebrow: 'MARKETPLACE',
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
    return Column(
      children: [
        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _HeroCard(slide: slides[i]),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(color: i == _index ? mv.accent : mv.border, borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      ],
    );
  }
}

/// One hero slide: a tinted card with the picture on its right, fading into
/// the background so the short text on the left always stays readable.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.slide});
  final _HeroSlide slide;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final dark = context.isDarkMode;
    final s = slide;
    final bg = dark ? MvColors.darkSoft : const Color(0xFFE3EFF3);
    return GestureDetector(
      onTap: s.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MvRadius.sheet),
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: bg),
              if (s.imageAsset != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: c.maxWidth * .66,
                    height: c.maxHeight,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => const LinearGradient(colors: [Color(0x00000000), Color(0xFF000000)], stops: [0, .42]).createShader(r),
                      child: Image.asset(s.imageAsset!, fit: BoxFit.cover, alignment: const Alignment(.35, 0)),
                    ),
                  ),
                )
              else
                Positioned(
                  right: 14,
                  top: 14,
                  bottom: 14,
                  width: c.maxWidth * .38,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(MvRadius.card + 4),
                    child: ColoredBox(color: mv.surface, child: ProductImage(src: s.imageUrl)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 0, 16),
                child: SizedBox(
                  width: c.maxWidth * .56,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mvEyebrow.copyWith(fontSize: 10.5, letterSpacing: 1.3)),
                      const SizedBox(height: 6),
                      Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.mvH1.copyWith(fontSize: 21, height: 1.15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(s.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 12)),
                      const SizedBox(height: 14),
                      _HeroButton(label: s.cta, onTap: s.onTap),
                    ],
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

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: context.mv.accent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(label, maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Category circles ────────────────────────────────────────────────────────

class _Categories extends StatelessWidget {
  const _Categories({required this.categories});
  final List<CategoryInfo> categories;

  /// Pastel backgrounds from the Landing page design.
  static const _tints = [
    Color(0xFFFFEEF2),
    Color(0xFFEAF3FF),
    Color(0xFFFFF6E8),
    Color(0xFFE7F7EE),
    Color(0xFFF1ECFF),
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
            width: 68,
            child: Column(
              children: [
                Container(width: 60, height: 60, decoration: BoxDecoration(color: dark ? bg.withValues(alpha: .16) : bg, shape: BoxShape.circle), alignment: Alignment.center, child: child),
                const SizedBox(height: 7),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: mv.text)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: circle(
                  shown[i].imageUrl.isNotEmpty
                      ? ClipOval(child: SizedBox(width: 60, height: 60, child: ProductImage(src: shown[i].imageUrl)))
                      : MvIcon('tag', size: 23, color: mv.accentDeep, strokeWidth: 1.5),
                  _tints[i % _tints.length],
                  shown[i].name,
                  () => context.go('/shop?category=${Uri.encodeQueryComponent(shown[i].name)}'),
                ),
              ),
            circle(MvIcon('grid', size: 23, color: mv.accentDeep, strokeWidth: 1.5), mv.soft, 'More', () => context.go('/shop')),
          ],
        ),
      ),
    );
  }
}

// ─── Promo banner ────────────────────────────────────────────────────────────

/// The teal "Shop here / Smoothness in buying" banner from the Landing page,
/// pointing at the Compare feature.
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MvRadius.sheet),
      child: Container(
        height: 204,
        color: dark ? const Color(0xFF0A4457) : MvColors.brand,
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            fit: StackFit.expand,
            children: [
              const CustomPaint(painter: _ArchPainter()),
              Positioned(right: 10, bottom: -34, child: _PhonePair(width: c.maxWidth * .3)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 0, 18),
                child: SizedBox(
                  width: c.maxWidth * .6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Shop here\nSmoothness in buying', maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.playfairDisplay(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
                      const SizedBox(height: 8),
                      Text('Compare products side by side before you buy.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 12, height: 1.35)),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => context.go('/buyer/compare'),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                              child: Text('Compare products', maxLines: 1, style: TextStyle(color: MvColors.brand, fontWeight: FontWeight.w800, fontSize: 12.5)),
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// Soft arches in the corners of the promo banner.
class _ArchPainter extends CustomPainter {
  const _ArchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.white.withValues(alpha: .10);
    // Bottom-left: a 3x2 grid of arches.
    const r = 14.0;
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 3; col++) {
        final cx = 22 + col * (r * 2 + 8);
        final base = size.height - 10 - row * (r + 8);
        canvas.drawArc(Rect.fromCircle(center: Offset(cx, base), radius: r), 3.14159, 3.14159, true, fill);
      }
    }
    // Top-right: a stack of half-discs facing left.
    for (var i = 0; i < 3; i++) {
      final cy = 18.0 + i * 30;
      canvas.drawArc(Rect.fromCircle(center: Offset(size.width - 6, cy), radius: 14), 1.5708, 3.14159, true, fill);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Two overlapping phones, drawn with plain boxes (no image asset needed).
class _PhonePair extends StatelessWidget {
  const _PhonePair({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width.clamp(80.0, 130.0);
    final h = w * 2.0;
    Widget phone(List<Color> screen) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0xFF0E1724),
            borderRadius: BorderRadius.circular(w * .2),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
          ),
          padding: EdgeInsets.all(w * .045),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * .16),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: screen),
            ),
            alignment: Alignment.topCenter,
            padding: EdgeInsets.only(top: w * .05),
            child: Container(width: w * .3, height: w * .08, decoration: BoxDecoration(color: const Color(0xFF0E1724), borderRadius: BorderRadius.circular(w))),
          ),
        );
    return SizedBox(
      width: w * 1.5,
      height: h,
      child: Stack(
        children: [
          Positioned(left: w * .5, top: -h * .02, child: Transform.rotate(angle: .12, child: phone(const [Color(0xFFBFE0FA), Color(0xFF6EA8E6)]))),
          Positioned(left: 0, top: h * .06, child: Transform.rotate(angle: -.08, child: phone(const [Color(0xFF8FC3F0), Color(0xFF3C7FCB)]))),
        ],
      ),
    );
  }
}
