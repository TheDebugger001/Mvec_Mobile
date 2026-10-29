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

/// Heart in a white circle on a product image (saves to the wishlist).
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
        color: mv.surface.withValues(alpha: .96),
        shape: const CircleBorder(),
        elevation: 1.5,
        shadowColor: mv.shadow,
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
          child: Padding(
            padding: const EdgeInsets.all(7),
            // Pops when the wishlist confirms the save, settles back on removal.
            child: HeartPop(
              active: wished,
              child: MvIcon(
                'heart',
                size: size,
                strokeWidth: 1.5,
                color: wished ? MvColors.badgeRed : mv.textMuted,
                fill: wished ? MvColors.badgeRed : null,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Small pink "40% OFF" pill.
class DiscountChip extends StatelessWidget {
  const DiscountChip(this.percent, {super.key});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3A1424) : const Color(0xFFFFE9EF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$percent% OFF',
        style: TextStyle(
          color: dark ? const Color(0xFFFF8DB0) : const Color(0xFFD81B60),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Image well on a card: width:height. Near-square on purpose, so a card
/// (image plus a one-line name and the price) stays only modestly taller than
/// it is wide. Use 0.8 for a 4:5 portrait well.
const double kProductImageAspect = 1;

/// Gap between a card's edge and its image well.
const double _kCardInset = 6;

/// Height of the text block under the image (one-line name, then price and
/// rating): 15 of padding plus 41 of text at the default font size.
const double _kCardTextPadding = 15;
const double _kCardTextLines = 41;

/// Total height of a card [width] logical pixels wide, so grids and strips can
/// give every card in a row the same height. The text block grows with the
/// phone's font-size setting so large text is not cut off.
double productCardHeight(double width, [TextScaler scaler = TextScaler.noScaling]) =>
    _kCardInset + (width - 2 * _kCardInset) / kProductImageAspect + _kCardTextPadding + scaler.scale(_kCardTextLines);

/// Storefront tile: rounded image well with the heart (and a "New" pill),
/// then the name and the price with its rating, in a compact near-square card.
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product, this.width});
  final Product product;
  final double? width;

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
        border: Border.all(color: mv.border),
        boxShadow: context.mvCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/product/${p.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(_kCardInset, _kCardInset, _kCardInset, 0),
              child: AspectRatio(
                aspectRatio: kProductImageAspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(MvRadius.image),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: mv.surfaceMuted),
                      ProductImage(src: p.image),
                      if (p.soldOut)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF172B34),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Text(
                              'SOLD OUT',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .3),
                            ),
                          ),
                        )
                      else if (p.onSale)
                        Positioned(left: 8, top: 8, child: DiscountChip(p.percentOff)),
                      Positioned(right: 6, top: 6, child: WishHeart(product: p)),
                      // No buyer reviews yet: a "New" pill on the image, as in the reference design.
                      if (p.reviews == 0)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: mv.surface.withValues(alpha: .96),
                              borderRadius: BorderRadius.circular(MvRadius.chip),
                            ),
                            child: Text('New', style: TextStyle(color: mv.text, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 13, height: 1.25),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // The price always shows in full; the old price and the rating give way.
                        Flexible(
                          flex: 3,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(money(p.price), maxLines: 1, style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w800, fontSize: 13.5)),
                          ),
                        ),
                        if (p.onSale) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            flex: 2,
                            child: Text(
                              money(p.oldPrice),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: mv.textMuted, fontSize: 10.5, decoration: TextDecoration.lineThrough),
                            ),
                          ),
                        ],
                        // A rating only when buyers have actually reviewed it.
                        if (p.reviews > 0) ...[
                          const Spacer(),
                          const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF0A91A)),
                          const SizedBox(width: 1),
                          Text(ratingLabel(p.rating), maxLines: 1, style: TextStyle(color: mv.textMuted, fontSize: 10.5)),
                        ],
                      ],
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

/// Two/three/four-column product grid (sliver).
class ProductGridSliver extends StatelessWidget {
  const ProductGridSliver({
    super.key,
    required this.products,
  });
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        final cols =
            c.crossAxisExtent >= 700 ? 4 : (c.crossAxisExtent >= 480 ? 3 : 2);
        final w = (c.crossAxisExtent - (cols - 1) * 12) / cols;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: productCardHeight(w, MediaQuery.textScalerOf(context)),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ProductCard(product: products[i]),
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
      final cols = c.maxWidth >= 700 ? 4 : (c.maxWidth >= 480 ? 3 : 2);
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      // The first frame can lay out at zero width; wait until there is room.
      if (w <= 2 * _kCardInset) return const SizedBox.shrink();
      return Semantics(
        label: 'Loading products',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: w,
                height: productCardHeight(w, MediaQuery.textScalerOf(context)),
                decoration: BoxDecoration(color: mv.surface, borderRadius: BorderRadius.circular(MvRadius.card), border: Border.all(color: mv.border)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(_kCardInset, _kCardInset, _kCardInset, 0),
                      child: Skeleton(width: w - 2 * _kCardInset, height: (w - 2 * _kCardInset) / kProductImageAspect, radius: MvRadius.image),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton(width: w * .62, height: 12, radius: 6),
                          const SizedBox(height: 8),
                          Skeleton(width: w * .35, height: 13, radius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}
