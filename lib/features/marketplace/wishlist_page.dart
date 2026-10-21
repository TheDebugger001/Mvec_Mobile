import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/cart_state.dart';
import '../../widgets/common.dart';

/// `/wishlist` — saved products with live price and stock (`pages/Wishlist.jsx`).
class WishlistPage extends ConsumerStatefulWidget {
  const WishlistPage({super.key});

  @override
  ConsumerState<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends ConsumerState<WishlistPage> {
  ({bool ok, String text})? _notice;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final items = ref.watch(wishlistProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(wishlistProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          const PageTitle(eyebrow: 'Saved items', title: 'Wishlist', subtitle: 'Products you saved. Your list follows you on every device and prices update automatically.'),
          if (_notice != null) Notice(text: _notice!.text, ok: _notice!.ok, onClose: () => setState(() => _notice = null)),
          if (items.isEmpty)
            EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Your wishlist is empty',
              message: 'Save products by tapping the heart icon.',
              action: GradientButton(label: 'Discover products', compact: true, onPressed: () => context.go('/shop')),
            ),
          for (final w in items)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(MvRadius.card), boxShadow: context.mvCardShadow),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(onTap: () => context.push('/product/${w.id}'), child: Container(width: 84, height: 84, decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(14)), clipBehavior: Clip.antiAlias, child: ProductImage(src: w.image))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.vendor, style: TextStyle(color: mv.textMuted, fontSize: 11)),
                        GestureDetector(onTap: () => context.push('/product/${w.id}'), child: Text(w.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 13.5))),
                        const SizedBox(height: 2),
                        Text(money(w.price), style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w800, fontSize: 14)),
                        if (w.priceDropped) Text('↓ ${money(w.savedPrice - w.price)} cheaper than when you saved it', style: const TextStyle(color: MvColors.successText, fontSize: 11)),
                        if (w.unavailable) const Text('No longer available', style: TextStyle(color: MvColors.errorText, fontSize: 11.5)),
                        if (w.soldOut) const Text('Out of stock', style: TextStyle(color: MvColors.errorText, fontSize: 11.5)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GradientButton(
                                label: 'Move to cart',
                                compact: true,
                                onPressed: w.unavailable || w.soldOut
                                    ? null
                                    : () async {
                                        final r = await ref.read(cartProvider.notifier).add(w.asProduct());
                                        if (r.ok) await ref.read(wishlistProvider.notifier).removeId(w.id);
                                        if (mounted) setState(() => _notice = (ok: r.ok, text: r.ok ? '${w.name} moved to your cart.' : r.message));
                                      },
                              ),
                            ),
                            IconButton(onPressed: () => ref.read(wishlistProvider.notifier).removeId(w.id), tooltip: 'Remove from wishlist', icon: Icon(Icons.delete_outline_rounded, color: mv.textMuted, size: 21)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
