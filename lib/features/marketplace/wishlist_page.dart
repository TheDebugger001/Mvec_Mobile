import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/cart_state.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/mv_icon.dart';

/// `/wishlist` — saved products with live price and stock (`pages/Wishlist.jsx`).
class WishlistPage extends ConsumerStatefulWidget {
  const WishlistPage({super.key});

  @override
  ConsumerState<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends ConsumerState<WishlistPage> {
  ({bool ok, String text})? _notice;

  void _show(bool ok, String text) {
    if (mounted) setState(() => _notice = (ok: ok, text: text));
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(wishlistProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(wishlistProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
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
          // Two saved products per row, each row as tall as its taller card.
          AnimatedSize(
            duration: Motion.reduced(context) ? Duration.zero : Motion.base,
            curve: Motion.out,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (var r = 0; r < items.length; r += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _WishCard(key: ValueKey(items[r].id), item: items[r], onNotice: _show)),
                          const SizedBox(width: 12),
                          Expanded(child: r + 1 < items.length ? _WishCard(key: ValueKey(items[r + 1].id), item: items[r + 1], onNotice: _show) : const SizedBox()),
                        ],
                      ),
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

/// A saved product: image panel with the remove heart, name, price and "Move to cart".
class _WishCard extends ConsumerWidget {
  const _WishCard({super.key, required this.item, required this.onNotice});
  final WishItem item;
  final void Function(bool ok, String text) onNotice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mv = context.mv;
    final w = item;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: mv.surface,
        borderRadius: BorderRadius.circular(MvRadius.card),
        border: Border.all(color: mv.border.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: mv.shadow.withValues(alpha: context.isDarkMode ? .3 : .045), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pressable(
            child: GestureDetector(
              onTap: () => context.push('/product/${w.id}'),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(color: context.isDarkMode ? mv.surfaceMuted : MvColors.pink.withValues(alpha: .55), borderRadius: BorderRadius.circular(MvRadius.image)),
                      child: ProductImage(src: w.image, radius: MvRadius.image),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Semantics(
                        button: true,
                        label: 'Remove from wishlist',
                        child: Pressable(
                          scale: .85,
                          child: Material(
                            color: mv.surface,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => ref.read(wishlistProvider.notifier).removeId(w.id),
                              child: const Padding(
                                padding: EdgeInsets.all(7),
                                child: MvIcon('heart', size: 16, strokeWidth: 1.6, color: MvColors.rose, fill: MvColors.rose),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 9, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.vendor, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(w.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w600, fontSize: 13, height: 1.25)),
                const SizedBox(height: 4),
                Text(money(w.price), style: context.mvPrice.copyWith(fontSize: 14)),
                if (w.priceDropped) Text('${money(w.savedPrice - w.price)} cheaper than when you saved it', style: const TextStyle(color: MvColors.successText, fontSize: 10.5, fontWeight: FontWeight.w600)),
                if (w.unavailable) const Text('No longer available', style: TextStyle(color: MvColors.errorText, fontSize: 11)),
                if (w.soldOut) const Text('Out of stock', style: TextStyle(color: MvColors.errorText, fontSize: 11)),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 8),
          GradientButton(
            label: 'Move to cart',
            compact: true,
            expand: true,
            onPressed: w.unavailable || w.soldOut
                ? null
                : () async {
                    final r = await ref.read(cartProvider.notifier).add(w.asProduct());
                    if (r.ok) await ref.read(wishlistProvider.notifier).removeId(w.id);
                    onNotice(r.ok, r.ok ? '${w.name} moved to your cart.' : r.message);
                  },
          ),
        ],
      ),
    );
  }
}
