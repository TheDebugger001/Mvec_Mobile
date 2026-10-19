import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/cart_state.dart';
import '../../widgets/common.dart';
import '../common/page_frame.dart';

/// `/cart` — lines grouped by seller, quantity steppers, subtotal and the way
/// to checkout (`pages/Cart.jsx`).
class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key});

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  String _error = '';
  String _busy = '';

  Future<void> _run(String id, Future<CartResult> Function() action) async {
    setState(() {
      _error = '';
      _busy = id;
    });
    final r = await action();
    if (!mounted) return;
    setState(() {
      _busy = '';
      if (!r.ok && r.message.isNotEmpty) _error = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final grouped = <String, List<CartLine>>{};
    for (final l in cart.lines) {
      grouped.putIfAbsent(l.vendor, () => []).add(l);
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          const PageTitle(eyebrow: 'Shopping cart', title: 'Your cart', subtitle: 'Products from different vendors are fulfilled separately.'),
          if (_error.isNotEmpty) Notice(text: _error),
          if (cart.loading && cart.lines.isEmpty) const LoadingState(label: 'Loading your cart…'),
          if (!cart.loading && cart.lines.isEmpty)
            EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Your cart is empty',
              action: GradientButton(label: 'Continue shopping', compact: true, onPressed: () => context.go('/shop')),
            ),
          for (final entry in grouped.entries) ...[
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text(entry.key, style: TextStyle(fontWeight: FontWeight.w600, color: mv.text, fontSize: 13.5))),
            for (final item in entry.value) _CartTile(item: item, busy: _busy == item.id, onQty: (q) => _run(item.id, () => notifier.setQty(item.id, q)), onRemove: () => _run(item.id, () => notifier.remove(item.id))),
          ],
          if (cart.lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            DataCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order summary', style: TextStyle(fontWeight: FontWeight.w600, color: mv.text, fontSize: 14)),
                  const SizedBox(height: 6),
                  SummaryRow('Subtotal', money(cart.subtotal)),
                  const SummaryRow('Delivery', 'Calculated at checkout'),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text('Each seller sets its own delivery fee for your district. You see the exact amount at checkout before you pay.', style: TextStyle(color: mv.textMuted, fontSize: 11.5, height: 1.4)),
                  ),
                  const Divider(height: 18),
                  SummaryRow('Subtotal', money(cart.subtotal), bold: true),
                  const SizedBox(height: 10),
                  GradientButton(label: 'Proceed to checkout', expand: true, onPressed: cart.blocked ? null : () => context.push('/checkout')),
                  if (cart.blocked) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Fix the highlighted items to continue.', style: TextStyle(color: MvColors.errorText, fontSize: 12))),
                  const SizedBox(height: 8),
                  Text('Your payment is held by MVEC until you confirm delivery.', style: TextStyle(color: mv.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.item, required this.busy, required this.onQty, required this.onRemove});
  final CartLine item;
  final bool busy;
  final ValueChanged<int> onQty;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final i = item;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(onTap: () => context.push('/product/${i.id}'), child: SizedBox(width: 68, height: 68, child: ProductImage(src: i.image, radius: 10))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(onTap: () => context.push('/product/${i.id}'), child: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w500, fontSize: 13, height: 1.25))),
                const SizedBox(height: 3),
                Text(money(i.price), style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w700, fontSize: 13)),
                if (i.unavailable) const Padding(padding: EdgeInsets.only(top: 3), child: Text('No longer available. Remove it to continue.', style: TextStyle(color: MvColors.errorText, fontSize: 11.5)))
                else if (i.overStock) Padding(padding: const EdgeInsets.only(top: 3), child: Text('Only ${i.stock} left. Lower the quantity.', style: const TextStyle(color: MvColors.errorText, fontSize: 11.5))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    QtyStepper(value: i.qty, max: i.stock > 0 ? i.stock.clamp(1, 100) : 100, busy: busy || i.unavailable, onChanged: onQty),
                    const Spacer(),
                    IconButton(onPressed: busy ? null : onRemove, tooltip: 'Remove ${i.name}', icon: Icon(Icons.delete_outline_rounded, color: mv.textMuted, size: 21)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
