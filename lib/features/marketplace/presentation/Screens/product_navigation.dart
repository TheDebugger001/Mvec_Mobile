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
  id: product.id.toString(),
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
            onAddToCart: commerce.addToCart,
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
            onMoveToCart: commerce.moveToCart,
            onToggleWishlist: commerce.toggleWishlist,
            onOpenCart: () => openCart(context, commerce),
            onAddToCart: commerce.addToCart,
            cartItemCount:
                () => commerce.cartItems.fold<int>(
                  0,
                  (count, item) => count + item.quantity,
                ),
          ),
    ),
  );
}

void openCart(BuildContext context, CommerceProvider commerce) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => CartPage(
            cartItems: commerce.cartItems,
            onUpdateQuantity: commerce.updateCartQuantity,
            onRemoveItem: commerce.removeCartItem,
            onProceedToCheckout: () => openCheckout(context, commerce),
            isWishlisted: commerce.isWishlisted,
            onToggleWishlist: commerce.toggleWishlist,
            onOpenWishlist: () => openWishlist(context, commerce),
            onAddToCart: commerce.addToCart,
            onOpenCart: () => openCart(context, commerce),
          ),
    ),
  );
}

void openCheckout(BuildContext context, CommerceProvider commerce) {
  const shippingFee = 5.0;
  const serviceFee = 2.5;
  final subtotal = commerce.cartItems.fold<double>(
    0,
    (sum, item) => sum + item.totalPrice,
  );
  final tax = subtotal * 0.08;
  final navigator = Navigator.of(context);

  navigator.push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => CheckoutPage(
            cartItems: commerce.cartItems,
            subtotal: subtotal,
            shippingFee: shippingFee,
            serviceFee: serviceFee,
            tax: tax,
            total: subtotal + shippingFee + serviceFee + tax,
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
              commerce.clearCart();
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
