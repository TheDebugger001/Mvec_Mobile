import 'package:flutter/foundation.dart';

import '../../../../core/api_client.dart';
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
  final ApiClient _api = ApiClient.instance;

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

  Future<void> loadCart() async {
    if (await ApiClient.readToken() == null) return;
    final response = await _api.get('/cart');
    final cart = singleJson(response, ['cart']);
    final items = cart['items'];
    if (items is! List) return;
    _cartItems
      ..clear()
      ..addAll(items.whereType<Map>().map((item) {
        final row = Map<String, dynamic>.from(item);
        final rawProduct = row['product'];
        if (rawProduct is! Map) {
          throw const FormatException(
            'The backend returned a cart item without its product.',
          );
        }
        final json = Map<String, dynamic>.from(rawProduct);
        final media = json['media'];
        final vendor = json['vendor'];
        final image = media is Map ? media['mainImage'] : null;
        final seller = vendor is Map
            ? (vendor['companyName'] ?? vendor['Fullname'] ?? 'Seller')
            : 'Seller';
        return CartItem(
          product: Product(
            id: '${json['_id'] ?? json['id'] ?? ''}',
            name: '${json['name'] ?? 'Product'}',
            description: '${json['description'] ?? ''}',
            price: _double(row['price'] ?? json['discountPrice'] ?? json['price']),
            stock: _int(json['stockQuantity']),
            images: image is String && image.isNotEmpty ? [image] : const [],
            colors: const [],
            sizes: const [],
            vendor: Vendor(
              id: vendor is Map ? '${vendor['_id'] ?? ''}' : '',
              name: '$seller',
              logo: '',
              rating: 0,
              totalProducts: 0,
            ),
          ),
          quantity: _int(row['quantity']),
        );
      }));
    notifyListeners();
  }

  Future<void> addToCart(Product product) async {
    if (await ApiClient.readToken() != null) {
      if (product.id.trim().isEmpty) {
        throw const FormatException(
          'This product does not have a backend product ID.',
        );
      }
      await _api.post('/cart', body: {'productId': product.id, 'quantity': 1});
      await loadCart();
    } else {
      _wishlistItems.removeWhere((item) => item.id == product.id);
      _addToCart(product);
      notifyListeners();
    }
    // Stronger than a wishlist entry: the cart is what turns into an order.
    onInterest?.call(product, InterestSignal.carted);
  }

  Future<void> moveToCart(Product product) => addToCart(product);

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

  Future<void> updateCartQuantity(CartItem item) async {
    if (await ApiClient.readToken() != null) {
      await _api.put(
        '/cart/items/${item.product.id}',
        body: {'quantity': item.quantity},
      );
    }
    notifyListeners();
  }

  Future<void> removeCartItem(CartItem item) async {
    if (await ApiClient.readToken() != null) {
      await _api.delete('/cart/items/${item.product.id}');
    }
    _cartItems.removeWhere(
      (cartItem) => cartItem.product.id == item.product.id,
    );
    notifyListeners();
  }

  Future<void> clearCart() async {
    if (await ApiClient.readToken() != null) {
      await _api.delete('/cart');
    }
    _cartItems.clear();
    notifyListeners();
  }

  static double _double(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static int _int(dynamic value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? 1;
}
