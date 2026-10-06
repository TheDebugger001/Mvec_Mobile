import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';

import '../../../../screens/cart_page.dart';
import '../../../../screens/checkout_page.dart';
import '../../../../screens/product_detail_page.dart';
import '../../../../screens/track_order_page.dart';
import '../../../../screens/wishlist_page.dart';
import '../../../../models/product.dart' as legacy;
import '../../data/interest/interest_profile.dart';
import '../../data/interest/interest_store.dart';
import '../providers/commerce_provider.dart';
import '../../data/models/product_model.dart' as marketplace;

legacy.Product toLegacyProduct(marketplace.Product product) => legacy.Product(
  id: product.apiId ?? product.id.toString(),
  name: product.name,
  description: product.description,
  price: product.price,
  oldPrice: product.originalPrice,
  stock: product.stockQuantity,
  images:
      product.imageUrl.isEmpty ? const <String>[] : <String>[product.imageUrl],
  colors: const <String>[],
  sizes: const <String>[],
  categoryId: product.categoryId,
  vendor: legacy.Vendor(
    id: product.vendorId?.toString() ?? '',
    name: product.vendorName ?? product.brand ?? 'Marketplace seller',
    logo: '',
    rating: product.rating,
    totalProducts: 0,
  ),
);

/// Reports an interaction on a catalogue product to the signed-in account.
///
/// A no-op for a guest: [InterestStore] has nobody to attach the evidence to,
/// so callers can fire this from every path without checking the session.
void _recordInterest(
  BuildContext context,
  marketplace.Product product,
  InterestSignal signal,
) {
  ProviderScope.containerOf(context, listen: false)
      .read(interestStoreProvider.notifier)
      .record(
        categoryId: product.categoryId,
        productId: product.id,
        signal: signal,
      );
}

void openProductDetails(BuildContext context, marketplace.Product product) {
  final commerce = context.read<CommerceProvider>();
  final detailProduct = toLegacyProduct(product);
  // Opening a product is the weakest signal, but it is the one the shopper
  // generates without meaning to, and it is what makes the first
  // recommendation possible at all.
  _recordInterest(context, product, InterestSignal.viewed);

  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => ProductDetailPage(
            product: detailProduct,
            isWishlisted: commerce.isWishlisted(detailProduct),
            onToggleWishlist: commerce.toggleWishlist,
            onOpenWishlist: () => openWishlist(context, commerce),
            onAddToCart: (product) => _runCartAction(
              context,
              () => commerce.addToCart(product),
            ),
            onOpenCart: () => openCart(context, commerce),
          ),
      settings: const RouteSettings(name: '/product-detail'),
    ),
  );
}

void openWishlist(BuildContext context, CommerceProvider commerce) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => WishlistPage(
            wishlistItems: commerce.wishlistItems,
            onRemoveFromWishlist: commerce.removeFromWishlist,
            onMoveToCart: (product) => _runCartAction(
              context,
              () => commerce.moveToCart(product),
            ),
            onToggleWishlist: commerce.toggleWishlist,
            onOpenCart: () => openCart(context, commerce),
            onAddToCart: (product) => _runCartAction(
              context,
              () => commerce.addToCart(product),
            ),
            cartItemCount:
                () => commerce.cartItems.fold<int>(
                  0,
                  (count, item) => count + item.quantity,
                ),
          ),
    ),
  );
}

Future<void> openCart(BuildContext context, CommerceProvider commerce) async {
  try {
    await commerce.loadCart();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load your cart: $error')),
      );
      return;
    }
  }
  if (!context.mounted) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => CartPage(
            cartItems: commerce.cartItems,
            onUpdateQuantity: (item) => _runCartAction(
              context,
              () => commerce.updateCartQuantity(item),
            ),
            onRemoveItem: (item) => _runCartAction(
              context,
              () => commerce.removeCartItem(item),
            ),
            onProceedToCheckout: () => openCheckout(context, commerce),
            isWishlisted: commerce.isWishlisted,
            onToggleWishlist: commerce.toggleWishlist,
            onOpenWishlist: () => openWishlist(context, commerce),
            onAddToCart: (product) => _runCartAction(
              context,
              () => commerce.addToCart(product),
            ),
            onOpenCart: () => openCart(context, commerce),
          ),
    ),
  );
}

void openCheckout(BuildContext context, CommerceProvider commerce) {
  final subtotal = commerce.cartItems.fold<double>(
    0,
    (sum, item) => sum + item.totalPrice,
  );
  final navigator = Navigator.of(context);

  navigator.push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => CheckoutPage(
            cartItems: commerce.cartItems,
            subtotal: subtotal,
            shippingFee: 0,
            serviceFee: 0,
            tax: 0,
            total: subtotal,
            onOrderPlaced: (order) {
              // A completed order is the strongest evidence available: whatever
              // they actually paid for is what the rest of their feed should be
              // built around.
              for (final item in order.items) {
                _recordInterest(
                  context,
                  marketplace.Product(
                    id: int.tryParse(item.product.id) ?? 0,
                    name: item.product.name,
                    slug: '',
                    description: item.product.description,
                    price: item.product.price,
                    imageUrl: '',
                    categoryId: item.product.categoryId,
                  ),
                  InterestSignal.purchased,
                );
              }
              _runCartAction(context, commerce.clearCart);
              navigator.pop();
              navigator.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TrackOrderPage(order: order),
                ),
              );
            },
          ),
    ),
  );
}

Future<void> _runCartAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cart update failed: $error')),
      );
    }
  }
}
