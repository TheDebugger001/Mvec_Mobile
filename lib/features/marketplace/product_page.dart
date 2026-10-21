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
    if (_loading) return const PageFrame(title: 'Product', shopping: true, storefront: true, body: LoadingState());
    if (p == null) {
      return PageFrame(
        title: 'Product',
        shopping: true,
        storefront: true,
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

    final amber = const Color(0xFFF0A91A);
    return PageFrame(
      title: 'Product',
      shopping: true,
      storefront: true,
      bottom: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total price', style: TextStyle(color: mv.textMuted, fontSize: 11)),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(money(p.price * _qty), style: context.mvH1.copyWith(fontSize: 16))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: GradientButton(
              label: _adding ? 'Adding…' : 'Add to cart',
              onPressed: p.soldOut ? null : _addToCart,
              loading: _adding,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: SolidButton(label: 'Buy now', onPressed: p.soldOut ? null : () => context.push('/checkout?product=${Uri.encodeQueryComponent(p.id)}&qty=$_qty'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Picture on a soft well with the heart on top, as in the furniture design.
          Container(
            decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(MvRadius.sheet + 4))),
            child: Column(
              children: [
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1.15,
                      child: Padding(padding: const EdgeInsets.all(18), child: ProductImage(src: _image.isEmpty ? p.image : _image, fit: BoxFit.contain)),
                    ),
                    Positioned(right: 16, top: 14, child: WishHeart(product: p, size: 20)),
                    if (p.soldOut)
                      Positioned(
                        left: 16,
                        top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: const Color(0xFF172B34), borderRadius: BorderRadius.circular(8)),
                          child: const Text('SOLD OUT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
                if (images.length > 1)
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => setState(() => _image = images[i]),
                        child: Container(
                          width: 56,
                          decoration: BoxDecoration(
                            color: mv.surface,
                            border: Border.all(color: images[i] == _image ? mv.accent : mv.border, width: images[i] == _image ? 2 : 1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ProductImage(src: images[i], radius: 12),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${p.category}${p.sku.isEmpty ? '' : ' · SKU ${p.sku}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 12))),
                    const SizedBox(width: 8),
                    Icon(Icons.star_rounded, size: 17, color: amber),
                    const SizedBox(width: 3),
                    Text('${ratingLabel(p.rating)}  ·  ${_reviews.length} review${_reviews.length == 1 ? '' : 's'}', style: TextStyle(color: mv.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(p.name, style: context.mvH1.copyWith(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(money(p.price), style: context.mvH1.copyWith(fontSize: 24, color: mv.accentDeep, fontWeight: FontWeight.w800)),
                    if (p.onSale) Text(money(p.oldPrice), style: TextStyle(color: mv.textMuted, decoration: TextDecoration.lineThrough, fontSize: 13.5)),
                    if (p.onSale) DiscountChip(p.percentOff),
                  ],
                ),
                const SizedBox(height: 8),
                _StockPill(soldOut: p.soldOut, low: stock <= 5, stock: stock),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Product Details', style: context.mvH1.copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(p.description, style: TextStyle(color: mv.textMuted, fontSize: 13.5, height: 1.55)),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(MvRadius.card)),
                  child: Row(
                    children: [
                      Avatar(name: p.vendor, radius: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Sold by', style: TextStyle(color: mv.textMuted, fontSize: 11)), Text(p.vendor, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 14))])),
                    ],
                  ),
                ),
                if (attrs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in attrs)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(999)),
                          child: Text.rich(TextSpan(children: [TextSpan(text: '${a.key}: ', style: TextStyle(color: mv.textMuted)), TextSpan(text: a.value, style: const TextStyle(fontWeight: FontWeight.w700))]), style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ],
                if (user == null) ...[
                  const SizedBox(height: 16),
                  const Notice(info: true, text: "You can browse and add to cart without an account. You'll sign in at checkout."),
                ],
                if (_feedback != null) ...[
                  const SizedBox(height: 10),
                  Notice(
                    text: _feedback!.message,
                    ok: _feedback!.ok,
                    child: _feedback!.ok ? GestureDetector(onTap: () => context.go('/cart'), child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('View cart', style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w700, fontSize: 12.5)))) : null,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    QtyStepper(value: _qty, max: maxQty, onChanged: p.soldOut ? (_) {} : (v) => setState(() => _qty = v)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlineBtn(
                        label: comparing ? 'Comparing' : 'Compare',
                        icon: Icons.compare_arrows_rounded,
                        compact: true,
                        expand: true,
                        onPressed: () {
                          final r = ref.read(compareProvider.notifier).toggle(p.id);
                          setState(() => _feedback = r);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(MvRadius.card)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in const ['Mobile money or card', 'Payment held until delivery', 'Delivery code at your door'])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [const MvIcon('check', size: 15, color: MvColors.successText, strokeWidth: 2.2), const SizedBox(width: 8), Expanded(child: Text(t, style: TextStyle(color: mv.text, fontSize: 12.5)))]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Ratings & reviews', style: context.mvH1.copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Reviews are written by buyers after their order is delivered.', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                const SizedBox(height: 12),
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
      });
    }
  }
}

/// "In stock" / "Only 3 left" / "Out of stock" as a tinted pill.
class _StockPill extends StatelessWidget {
  const _StockPill({required this.soldOut, required this.low, required this.stock});
  final bool soldOut;
  final bool low;
  final int stock;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final (bg, fg, text) = soldOut
        ? (dark ? const Color(0xFF3A1414) : MvColors.errorBg, MvColors.errorText, 'Out of stock')
        : low
            ? (dark ? const Color(0xFF332712) : MvColors.warningBg, MvColors.warningText, 'Only $stock left in stock')
            : (dark ? const Color(0xFF0F2F25) : MvColors.successBg, MvColors.successText, 'In stock');
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(MvRadius.card)),
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
