import 'package:flutter/material.dart';
import '../models/product.dart';

class CartPage extends StatefulWidget {
  final List<Product> cartItems;
  final ValueChanged<Product> onRemoveFromCart;
  final ValueChanged<Product> onAddToCart;

  const CartPage({
    super.key,
    required this.cartItems,
    required this.onRemoveFromCart,
    required this.onAddToCart,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  static const double _actionWidth = 88;
  final Map<String, double> _itemOffsets = {};
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('My Cart'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: widget.cartItems.isEmpty
            ? const Center(child: Text('Your cart is empty'))
            : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.cartItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final product = widget.cartItems[index];
                final offset = _itemOffsets[product.id] ?? 0;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: offset == 0,
                          child: offset == 0
                              ? const SizedBox.shrink()
                              : offset < 0
                              ? Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildDeleteButton(product),
                                )
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: _buildDeleteButton(product),
                                ),
                        ),
                      ),
                      GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            final nextOffset =
                                (_itemOffsets[product.id] ?? 0) +
                                details.delta.dx;
                            _itemOffsets[product.id] = nextOffset
                              .clamp(-_actionWidth, _actionWidth)
                                .toDouble();
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          setState(() {
                            final currentOffset = _itemOffsets[product.id] ?? 0;
                            _itemOffsets[product.id] = currentOffset.abs() >= 44
                              ? currentOffset.sign * _actionWidth
                              : 0;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          transform: Matrix4.translationValues(offset, 0, 0),
                          child: _buildCartTile(product),
                        ),
                      ),
                    ],
                  ),
                );
              },
                  ),
                ),
    );
  }

  Widget _buildCartTile(Product product) {
    return ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: product.images.isEmpty
          ? const Icon(Icons.image_outlined)
          : Image.network(
              product.images.first,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
            ),
      title: Text(product.name),
      subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
    );
  }

  Widget _buildDeleteButton(Product product) {
    return SizedBox(
      width: _actionWidth,
      child: IconButton(
        tooltip: 'Delete from cart',
        icon: const Icon(Icons.delete_outline, color: Colors.black54),
        onPressed: () => _deleteProduct(product),
      ),
    );
  }

  void _deleteProduct(Product product) {
    final messenger = _messengerKey.currentState!;
    setState(() {
      _itemOffsets.remove(product.id);
    });
    widget.onRemoveFromCart(product);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Row(
          children: [
            Expanded(child: Text('${product.name} removed from cart')),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                widget.onAddToCart(product);
              },
              child: const Text('Undo'),
            ),
          ],
        ),
      ),
    );
  }
}