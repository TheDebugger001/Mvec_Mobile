import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/cart_state.dart';
import '../../widgets/common.dart';

/// Storefront tile (`ProductCard.jsx`): image, sale / sold-out badge, wishlist
/// heart, name, rating and price.
class ProductCard extends ConsumerWidget {
  const ProductCard({super.key, required this.product, this.label});
  final Product product;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final p = product;
    final wished = ref.watch(wishlistProvider.select((w) => w.any((x) => x.id == p.id)));

    return Container(
      decoration: BoxDecoration(
        color: mv.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mv.border),
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
                  ProductImage(src: p.image),
                  if (p.soldOut || p.onSale)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.soldOut ? const Color(0xFF172B34) : MvColors.badgeRed,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.soldOut ? 'SOLD OUT' : 'SALE',
                          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: mv.surface.withValues(alpha: .92),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () async {
                          final ok = await ref.read(wishlistProvider.notifier).toggle(p);
                          if (!ok && context.mounted) {
                            context.push('/login?next=${Uri.encodeQueryComponent(GoRouterState.of(context).uri.toString())}');
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(
                            wished ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 19,
                            color: wished ? MvColors.badgeRed : mv.textMuted,
                            semanticLabel: wished ? 'Remove from wishlist' : 'Save to wishlist',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label ?? p.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 13, height: 1.25)),
                  const SizedBox(height: 4),
                  Text(
                    '★ ${ratingLabel(p.rating)}${p.reviews > 0 ? ' (${p.reviews})' : ''}',
                    style: TextStyle(color: mv.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(money(p.price), style: TextStyle(color: mv.text, fontWeight: FontWeight.w800, fontSize: 14)),
                      if (p.onSale) Text(money(p.oldPrice), style: TextStyle(color: mv.textMuted, fontSize: 11.5, decoration: TextDecoration.lineThrough)),
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

/// Two-column product grid inside a scroll view (sliver).
class ProductGridSliver extends StatelessWidget {
  const ProductGridSliver({super.key, required this.products, this.showVendor = false});
  final List<Product> products;
  final bool showVendor;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, c) {
      final cols = c.crossAxisExtent >= 700 ? 4 : (c.crossAxisExtent >= 480 ? 3 : 2);
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: (c.crossAxisExtent - (cols - 1) * 10) / cols + 112,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => ProductCard(product: products[i], label: showVendor ? products[i].vendor : null),
          childCount: products.length,
        ),
      );
    });
  }
}
