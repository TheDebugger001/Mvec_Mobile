import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_detail_page.dart';

class WishlistPage extends StatefulWidget {
  final List<Product> wishlistItems;
  final Function(Product) onRemoveFromWishlist;
  final Function(Product) onMoveToCart;
  final ValueChanged<Product>? onToggleWishlist;
  final VoidCallback? onOpenCart;
  final ValueChanged<Product>? onAddToCart;

  const WishlistPage({
    super.key,
    required this.wishlistItems,
    required this.onRemoveFromWishlist,
    required this.onMoveToCart,
    this.onToggleWishlist,
    this.onOpenCart,
    this.onAddToCart,
  });

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'My Wishlist',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (widget.onOpenCart != null)
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              tooltip: 'Open cart',
              onPressed: widget.onOpenCart,
            ),
        ],
      ),
      body: widget.wishlistItems.isEmpty
          ? _buildEmptyWishlist()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.wishlistItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final product = widget.wishlistItems[index];
                return _buildWishlistItem(product);
              },
            ),
    );
  }

  // ==================== EMPTY STATE ====================
  Widget _buildEmptyWishlist() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Your wishlist is empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Save products you love by tapping the heart icon',
            style: TextStyle(color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==================== WISHLIST ITEM ====================
  Widget _buildWishlistItem(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Product Info (tappable)
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductDetailPage(
                    product: product,
                    isWishlisted: true,
                    onToggleWishlist: _toggleWishlistFromDetail,
                    onAddToCart: widget.onAddToCart,
                    onOpenCart: widget.onOpenCart,
                  ),
                ),
              );
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: product.images.isNotEmpty
                        ? Image.network(
                            product.images.first,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _imagePlaceholder(),
                          )
                        : _imagePlaceholder(),
                  ),
                  const SizedBox(width: 12),

                  // Name + Price + Vendor
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '\$${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.vendor.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action Buttons
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                // Remove from Wishlist
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      widget.onRemoveFromWishlist(product);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Removed from wishlist'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    label: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),

                // Move to Cart
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      widget.onMoveToCart(product);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${product.name} moved to cart'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: Icon(Icons.shopping_cart_outlined,
                        size: 20, color: Theme.of(context).primaryColor),
                    label: Text(
                      'Move to Cart',
                      style: TextStyle(color: Theme.of(context).primaryColor),
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

  void _toggleWishlistFromDetail(Product product) {
    widget.onToggleWishlist?.call(product);
    setState(() {});
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 90,
      height: 90,
      color: Colors.grey[200],
      child: const Icon(Icons.image, color: Colors.grey),
    );
  }
}