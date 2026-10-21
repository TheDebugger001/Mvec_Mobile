import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/cart_state.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/mv_icon.dart';

/// Heart in a white circle on a product image (saves to the wishlist). It pops
/// when the wishlist confirms the save and settles back when it is removed.
class WishHeart extends ConsumerWidget {
  const WishHeart({super.key, required this.product, this.size = 17});
  final Product product;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final wished = ref.watch(
      wishlistProvider.select((w) => w.any((x) => x.id == product.id)),
    );
    return Semantics(
      button: true,
      label: wished ? 'Remove from wishlist' : 'Save to wishlist',
      child: Pressable(
        scale: .86,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              final ok = await ref
                  .read(wishlistProvider.notifier)
                  .toggle(product);
              if (!ok && context.mounted) {
                context.push(
                  '/login?next=${Uri.encodeQueryComponent(GoRouterState.of(context).uri.toString())}',
                );
              }
            },
            child: AnimatedContainer(
              duration: Motion.quick,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: wished
                    ? (context.isDarkMode ? const Color(0xFF3A1424) : MvColors.pink)
                    : mv.surface.withValues(alpha: .96),
                boxShadow: [BoxShadow(color: mv.shadow.withValues(alpha: .08), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: HeartPop(
                active: wished,
                child: MvIcon(
                  'heart',
                  size: size,
                  strokeWidth: 1.6,
                  color: wished ? MvColors.rose : mv.textMuted,
                  fill: wished ? MvColors.rose : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small "-40%" pill on a product image.
class DiscountChip extends StatelessWidget {
  const DiscountChip(this.percent, {super.key});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A1424) : MvColors.pink,
        borderRadius: BorderRadius.circular(MvRadius.chip),
      ),
      child: Text(
        '-$percent%',
        semanticsLabel: '$percent% off',
        style: TextStyle(
          color: dark ? const Color(0xFFFF8DB0) : const Color(0xFFB3245C),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Height of everything under the image on a [ProductCard].
const double _kCardInfoHeight = 112;
const double _kCardInset = 6;

/// Storefront tile: image on a soft panel, heart, name, price and (only when
/// buyers have rated it) the rating.
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product, this.label, this.width});
  final Product product;
  final String? label;
  final double? width;

  /// Card height for a given width, so grids and carousels stay even.
  static double heightFor(double width) => (width - _kCardInset * 2) + _kCardInset + _kCardInfoHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final p = product;
    return Pressable(
      scale: .97,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: mv.surface,
          borderRadius: BorderRadius.circular(MvRadius.card),
          border: Border.all(color: mv.border.withValues(alpha: .7)),
          boxShadow: [BoxShadow(color: mv.shadow.withValues(alpha: context.isDarkMode ? .3 : .045), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push('/product/${p.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(_kCardInset, _kCardInset, _kCardInset, 0),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(MvRadius.image)),
                          child: ProductImage(src: p.image, radius: MvRadius.image),
                        ),
                        if (p.soldOut)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(color: MvColors.navy, borderRadius: BorderRadius.circular(MvRadius.chip)),
                              child: const Text('Sold out', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          )
                        else if (p.onSale)
                          Positioned(left: 8, top: 8, child: DiscountChip(p.percentOff)),
                        Positioned(right: 6, top: 6, child: WishHeart(product: p, size: 16)),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: _kCardInfoHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label ?? p.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: mv.textMuted, fontSize: 10.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: mv.text, fontWeight: FontWeight.w600, fontSize: 13, height: 1.25),
                        ),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // The price always shows in full; the old price gives way.
                            Flexible(
                              flex: 3,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(money(p.price), maxLines: 1, style: context.mvPrice.copyWith(fontSize: 14)),
                              ),
                            ),
                            if (p.onSale) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 1.5),
                                  child: Text(
                                    money(p.oldPrice),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: mv.textMuted, fontSize: 10.5, decoration: TextDecoration.lineThrough),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (p.reviews > 0) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF2B01E)),
                              const SizedBox(width: 2),
                              Text('${ratingLabel(p.rating)} (${p.reviews})', style: TextStyle(color: mv.textMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ],
                    ),
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

/// Two/three/four columns for a product grid of this width.
int _columnsFor(double width) => width >= 700 ? 4 : (width >= 480 ? 3 : 2);

/// Two/three/four-column product grid (sliver).
class ProductGridSliver extends StatelessWidget {
  const ProductGridSliver({
    super.key,
    required this.products,
    this.showVendor = false,
  });
  final List<Product> products;
  final bool showVendor;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        final cols = _columnsFor(c.crossAxisExtent);
        final w = (c.crossAxisExtent - (cols - 1) * 12) / cols;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: ProductCard.heightFor(w),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ProductCard(
              product: products[i],
              label: showVendor ? products[i].vendor : null,
            ),
            childCount: products.length,
          ),
        );
      },
    );
  }
}

/// Placeholder cards with the same shape as [ProductCard], shown while the
/// real products load.
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return LayoutBuilder(builder: (context, c) {
      final cols = _columnsFor(c.maxWidth);
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Semantics(
        label: 'Loading products',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: w,
                height: ProductCard.heightFor(w),
                padding: const EdgeInsets.all(_kCardInset),
                decoration: BoxDecoration(color: mv.surface, borderRadius: BorderRadius.circular(MvRadius.card), border: Border.all(color: mv.border.withValues(alpha: .7))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: w - _kCardInset * 2, height: w - _kCardInset * 2, radius: MvRadius.image),
                    const SizedBox(height: 12),
                    Skeleton(width: w * .4, height: 9, radius: 5),
                    const SizedBox(height: 8),
                    Skeleton(width: w * .8, height: 12, radius: 6),
                    const Spacer(),
                    Skeleton(width: w * .45, height: 14, radius: 6),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}
