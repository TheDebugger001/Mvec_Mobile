import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/cart_state.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/checkout_steps.dart';
import '../../widgets/common.dart';

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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          if (cart.lines.isNotEmpty) const CheckoutSteps(current: 0),
          const PageTitle(eyebrow: 'Shopping cart', title: 'Your cart', subtitle: 'Products from different vendors are fulfilled separately.'),
          if (_error.isNotEmpty) Notice(text: _error),
          if (cart.loading && cart.lines.isEmpty) const LoadingState(label: 'Loading your cart…'),
          if (!cart.loading && cart.lines.isEmpty)
            EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Your cart is empty',
              message: 'Browse the shop and add what you like. It will wait for you here.',
              action: GradientButton(label: 'Continue shopping', compact: true, onPressed: () => context.go('/shop')),
            ),
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, size: 17, color: mv.accentDeep),
                  const SizedBox(width: 7),
                  Expanded(child: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 14))),
                ],
              ),
            ),
            for (final item in entry.value) _CartTile(item: item, busy: _busy == item.id, onQty: (q) => _run(item.id, () => notifier.setQty(item.id, q)), onRemove: () => _run(item.id, () => notifier.remove(item.id))),
          ],
          if (cart.lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            BrandPanel(
              children: [
                const PanelTitle('Order summary'),
                PanelRow('Subtotal', money(cart.subtotal)),
                const PanelRow('Delivery', 'Calculated at checkout'),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text('Each seller sets its own delivery fee for your district. You see the exact amount at checkout before you pay.', style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11.5, height: 1.4)),
                ),
                Divider(height: 22, color: Colors.white.withValues(alpha: .22)),
                PanelRow('Subtotal', money(cart.subtotal), bold: true),
                const SizedBox(height: 14),
                OnBrandButton(label: 'Proceed to checkout', onPressed: cart.blocked ? null : () => context.push('/checkout')),
                if (cart.blocked)
                  const Padding(padding: EdgeInsets.only(top: 10), child: Text('Fix the highlighted items to continue.', style: TextStyle(color: Color(0xFFFFB4AB), fontSize: 12, fontWeight: FontWeight.w600))),
                const SizedBox(height: 10),
                Text('Your payment is held by MVEC until you confirm delivery.', style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11.5)),
              ],
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
    final problem = i.unavailable || i.overStock;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: mv.surface,
        border: Border.all(color: problem ? MvColors.errorText.withValues(alpha: .5) : mv.border),
        borderRadius: BorderRadius.circular(MvRadius.card),
        boxShadow: context.mvCardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/product/${i.id}'),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(14)),
              clipBehavior: Clip.antiAlias,
              child: ProductImage(src: i.image),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.push('/product/${i.id}'),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.25)),
                        ),
                      ),
                    ),
                    InkResponse(
                      onTap: busy ? null : onRemove,
                      radius: 20,
                      child: Tooltip(
                        message: 'Remove ${i.name}',
                        child: Padding(padding: const EdgeInsets.fromLTRB(8, 2, 2, 6), child: Icon(Icons.delete_outline_rounded, color: mv.textMuted, size: 20)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(money(i.price), style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w800, fontSize: 14)),
                if (i.unavailable)
                  const Padding(padding: EdgeInsets.only(top: 3), child: Text('No longer available. Remove it to continue.', style: TextStyle(color: MvColors.errorText, fontSize: 11.5)))
                else if (i.overStock)
                  Padding(padding: const EdgeInsets.only(top: 3), child: Text('Only ${i.stock} left. Lower the quantity.', style: const TextStyle(color: MvColors.errorText, fontSize: 11.5))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    QtyStepper(value: i.qty, max: i.stock > 0 ? i.stock.clamp(1, 100) : 100, busy: busy || i.unavailable, onChanged: onQty),
                    const Spacer(),
                    if (i.qty > 1) Flexible(child: Text(money(i.price * i.qty), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600))),
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
