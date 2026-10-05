import 'package:flutter/foundation.dart';

import '../../data/interest/interest_profile.dart';
import '../../../../models/cart_item.dart';
import '../../../../models/product.dart';

class CommerceProvider extends ChangeNotifier {
  CommerceProvider({this.onInterest});

  /// Reports a deliberate action on a product so the signed-in account's feed
  /// can learn from it. Null in tests and anywhere personalisation is not
  /// wired up; the store itself ignores everything from a guest.
  final void Function(Product product, InterestSignal signal)? onInterest;

  final List<Product> _wishlistItems = [];
  final List<CartItem> _cartItems = [];

  List<Product> get wishlistItems => _wishlistItems;
  List<CartItem> get cartItems => _cartItems;

  bool isWishlisted(Product product) =>
      _wishlistItems.any((item) => item.id == product.id);

  void toggleWishlist(Product product) {
    if (isWishlisted(product)) {
      _wishlistItems.removeWhere((item) => item.id == product.id);
    } else {
      _wishlistItems.add(product);
      // Saving something is a deliberate statement about what they want, so it
      // is worth more evidence than a browse.
      onInterest?.call(product, InterestSignal.wishlisted);
    }
    notifyListeners();
  }

  void removeFromWishlist(Product product) {
    _wishlistItems.removeWhere((item) => item.id == product.id);
    notifyListeners();
  }

  void addToCart(Product product) {
    _wishlistItems.removeWhere((item) => item.id == product.id);
    _addToCart(product);
    // Stronger than a wishlist entry: the cart is what turns into an order.
    onInterest?.call(product, InterestSignal.carted);
    notifyListeners();
  }

  void moveToCart(Product product) => addToCart(product);

  void _addToCart(Product product) {
    final matchingItems = _cartItems.where(
      (item) => item.product.id == product.id,
    );
    if (matchingItems.isEmpty) {
      _cartItems.add(CartItem(product: product));
    } else if (matchingItems.first.quantity < product.stock) {
      matchingItems.first.quantity++;
    }
  }

  void updateCartQuantity(CartItem item) => notifyListeners();

  void removeCartItem(CartItem item) {
    _cartItems.removeWhere(
      (cartItem) => cartItem.product.id == item.product.id,
    );
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    notifyListeners();
  }
}
