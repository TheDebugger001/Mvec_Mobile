import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/catalog_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/compare_state.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/mv_icon.dart';
import '../common/page_frame.dart';
import 'product_card.dart';

/// `/product/:id` — gallery, price, stock, vendor, reviews, add to cart, buy
/// now, wishlist and compare (`pages/ProductDetails.jsx`).
class ProductPage extends ConsumerStatefulWidget {
  const ProductPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<ProductPage> {
  Product? _p;
  Object? _error;
  bool _loading = true;
  int _qty = 1;
  String _image = '';
  List<Map<String, dynamic>> _reviews = const [];
  ({bool ok, String message})? _feedback;
  bool _adding = false;
  // True for a moment after the cart confirms an add: the button shows a check.
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await CatalogApi.product(widget.id);
      if (!mounted) return;
      setState(() {
        _p = p;
        _image = p.image;
      });
      CatalogApi.reviews(p.id).then((r) {
        if (mounted) setState(() => _reviews = r);
      }).catchError((_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final p = _p;
    if (_loading) return const PageFrame(title: 'Product', shopping: true, body: LoadingState());
    if (p == null) {
      return PageFrame(
        title: 'Product',
        shopping: true,
        body: _error != null && statusOf(_error!) != 404
            ? ErrorState(error: _error!, onRetry: _load)
            : EmptyState(
                title: 'Product not found',
                message: 'It may have been removed or is no longer available.',
                action: GradientButton(label: 'Back to shop', compact: true, onPressed: () => context.go('/shop')),
              ),
      );
    }

    final user = ref.watch(authProvider.select((a) => a.user));
    final compare = ref.watch(compareProvider);
    final comparing = compare.contains(p.id);
    final stock = p.stock;
    final maxQty = stock.clamp(1, 100);
    final images = {p.image, ...p.gallery}.where((e) => e.isNotEmpty).toList();
    final attrs = p.attributes.entries.where((e) => e.value.isNotEmpty).toList();

    return PageFrame(
      title: 'Product',
      shopping: true,
      bottom: Row(
        children: [
          Expanded(
            child: GradientButton(
              label: _added ? 'Added' : (_adding ? 'Adding…' : 'Add to cart'),
              icon: Icons.shopping_cart_outlined,
              onPressed: p.soldOut ? null : _addToCart,
              loading: _adding,
              success: _added,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: SolidButton(label: 'Buy now', onPressed: p.soldOut ? null : () => context.push('/checkout?product=${Uri.encodeQueryComponent(p.id)}&qty=$_qty'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Main image on a soft panel; swipe sideways for the next photo.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: GestureDetector(
              onHorizontalDragEnd: images.length < 2
                  ? null
                  : (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v.abs() < 200) return;
                      final i = images.indexOf(_image.isEmpty ? p.image : _image);
                      setState(() => _image = images[(i + (v < 0 ? 1 : -1)) % images.length]);
                    },
              child: Container(
                decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 1.05,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: Motion.reduced(context) ? Duration.zero : Motion.base,
                        switchInCurve: Motion.out,
                        transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: .97, end: 1).animate(a), child: child)),
                        child: Padding(
                          key: ValueKey(_image),
                          padding: const EdgeInsets.all(12),
                          child: ProductImage(src: _image.isEmpty ? p.image : _image, fit: BoxFit.contain, radius: 16),
                        ),
                      ),
                      if (p.onSale) Positioned(left: 14, top: 14, child: DiscountChip(p.percentOff)),
                      Positioned(right: 12, top: 12, child: WishHeart(product: p, size: 18)),
                      if (images.length > 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 12,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final img in images)
                                AnimatedContainer(
                                  duration: Motion.base,
                                  curve: Motion.out,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: img == (_image.isEmpty ? p.image : _image) ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: img == (_image.isEmpty ? p.image : _image) ? MvColors.primaryDark : mv.border, borderRadius: BorderRadius.circular(3)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (images.length > 1)
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _image = images[i]),
                  child: AnimatedContainer(
                    duration: Motion.quick,
                    width: 50,
                    decoration: BoxDecoration(border: Border.all(color: images[i] == _image ? MvColors.primaryDark : mv.border, width: images[i] == _image ? 2 : 1), borderRadius: BorderRadius.circular(12)),
                    child: ProductImage(src: images[i], radius: 10),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.category}${p.sku.isEmpty ? '' : ' · SKU ${p.sku}'}', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text(p.name, style: context.mvH1.copyWith(fontSize: 19, height: 1.25)),
                const SizedBox(height: 6),
                if (_reviews.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.star_rounded, size: 17, color: Color(0xFFF2B01E)),
                    const SizedBox(width: 3),
                    Text('${ratingLabel(p.rating)}  ·  ${_reviews.length} review${_reviews.length == 1 ? '' : 's'}', style: TextStyle(color: mv.textMuted, fontSize: 12.5, fontWeight: FontWeight.w500)),
                  ])
                else
                  Text('No reviews yet', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 10,
                  children: [
                    Text(money(p.price), style: context.mvPrice.copyWith(fontSize: 24)),
                    if (p.onSale) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(money(p.oldPrice), style: TextStyle(color: mv.textMuted, decoration: TextDecoration.lineThrough, fontSize: 13))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p.soldOut ? 'Out of stock' : (stock <= 5 ? 'Only $stock left in stock' : 'In stock'),
                  style: TextStyle(color: p.soldOut ? MvColors.errorText : (stock <= 5 ? MvColors.warningText : MvColors.successText), fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(p.description, style: TextStyle(color: mv.text, fontSize: 13, height: 1.5)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Avatar(name: p.vendor, radius: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Sold by', style: TextStyle(color: mv.textMuted, fontSize: 11)), Text(p.vendor, style: TextStyle(color: mv.text, fontWeight: FontWeight.w600, fontSize: 13))])),
                  ],
                ),
                if (attrs.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in attrs)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(MvRadius.chip)),
                          child: Text.rich(TextSpan(children: [TextSpan(text: '${a.key}: ', style: TextStyle(color: mv.textMuted)), TextSpan(text: a.value, style: const TextStyle(fontWeight: FontWeight.w600))]), style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ],
                if (user == null) ...[
                  const SizedBox(height: 14),
                  const Notice(info: true, text: "You can browse and add to cart without an account. You'll sign in at checkout."),
                ],
                if (_feedback != null) ...[
                  const SizedBox(height: 10),
                  Notice(
                    text: _feedback!.message,
                    ok: _feedback!.ok,
                    child: _feedback!.ok ? GestureDetector(onTap: () => context.go('/cart'), child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('View cart', style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w600, fontSize: 12.5)))) : null,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    QtyStepper(value: _qty, max: maxQty, onChanged: p.soldOut ? (_) {} : (v) => setState(() => _qty = v)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlineBtn(
                        label: comparing ? 'Comparing' : 'Compare',
                        icon: Icons.compare_arrows_rounded,
                        compact: true,
                        onPressed: () {
                          final r = ref.read(compareProvider.notifier).toggle(p.id);
                          setState(() => _feedback = r);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (final t in const ['Mobile money or card', 'Payment held until delivery', 'Delivery code at your door'])
                      Row(mainAxisSize: MainAxisSize.min, children: [const MvIcon('check', size: 13, color: MvColors.successText, strokeWidth: 2), const SizedBox(width: 4), Text(t, style: TextStyle(color: mv.textMuted, fontSize: 11.5))]),
                  ],
                ),
                const SizedBox(height: 22),
                Text('Ratings & reviews', style: context.mvH1.copyWith(fontSize: 16)),
                const SizedBox(height: 4),
                Text('Reviews are written by buyers after their order is delivered.', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                const SizedBox(height: 10),
                if (_reviews.isEmpty) Text('No reviews yet.', style: TextStyle(color: mv.textMuted, fontSize: 12.5)),
                for (final r in _reviews.take(10)) _ReviewTile(review: r),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    final r = await ref.read(cartProvider.notifier).add(_p!, _qty);
    if (mounted) {
      setState(() {
        _adding = false;
        _feedback = r;
        _added = r.ok;
      });
    }
    if (r.ok) {
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _added = false);
      });
    }
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final r = review;
    final rating = numOf(r['rating']).toInt().clamp(0, 5);
    final user = r['user'];
    final who = strOf(r['reviewer'] ?? (user is Map ? (user['fullName'] ?? user['Fullname']) : user), 'Verified buyer');
    final reply = strOf(r['vendorReply']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${'★' * rating}${'☆' * (5 - rating)}', style: const TextStyle(color: Color(0xFFF0A91A), fontSize: 13)),
          const SizedBox(height: 4),
          Text(strOf(r['review'] ?? r['comment'] ?? r['reviewText']), style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 4),
          Text('$who${r['isVerifiedPurchase'] == true ? ' · Verified purchase' : ''} · ${formatDate(r['date'] ?? r['createdAt'])}', style: TextStyle(color: mv.textMuted, fontSize: 11)),
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(8)), child: Text('Seller reply: $reply', style: const TextStyle(fontSize: 12))),
          ],
        ],
      ),
    );
  }
}
