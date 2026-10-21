import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/cart_state.dart';
import '../../widgets/common.dart';
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

/// Height of the text block under a product image (category, two-line name,
/// rating and price), used to size grid cells.
const double kProductCardInfoHeight = 124;

/// Storefront tile: soft image well with the heart, then name, rating and
/// price (the Landing page product card).
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product, this.label, this.width});
  final Product product;
  final String? label;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final p = product;
    return Container(
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
            AspectRatio(
              aspectRatio: 1,
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
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label ?? p.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mv.textMuted, fontSize: 10.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 13, height: 1.25),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF0A91A)),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          '${ratingLabel(p.rating)}${p.reviews > 0 ? ' (${p.reviews})' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: mv.textMuted, fontSize: 10.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          money(p.price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ),
                      if (p.onSale) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            money(p.oldPrice),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: mv.textMuted, fontSize: 10.5, decoration: TextDecoration.lineThrough),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    this.showVendor = false,
  });
  final List<Product> products;
  final bool showVendor;

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
            mainAxisExtent: w + kProductCardInfoHeight,
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
