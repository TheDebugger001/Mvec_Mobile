import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_api.dart';
import '../api/commerce_api.dart';
import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/product.dart';
import 'auth_state.dart';

const _guestCartKey = 'mvec_cart';
const _maxQty = 100;

/// One cart line, the same shape for guests and signed-in buyers.
class CartLine {
  const CartLine({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.qty,
    required this.stock,
    required this.status,
    required this.sku,
    required this.vendor,
    required this.vendorId,
  });

  final String id;
  final String name;
  final String image;
  final num price;
  final int qty;

  /// -1 when unknown.
  final int stock;
  final String status;
  final String sku;
  final String vendor;
  final String vendorId;

  bool get unavailable => (status.isNotEmpty && status != 'ACTIVE') || (stock >= 0 && stock <= 0);
  bool get overStock => stock > 0 && qty > stock;
  bool get atMax => stock > 0 && qty >= stock;

  CartLine withQty(int q) => CartLine(
        id: id,
        name: name,
        image: image,
        price: price,
        qty: q,
        stock: stock,
        status: status,
        sku: sku,
        vendor: vendor,
        vendorId: vendorId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image': image,
        'price': price,
        'qty': qty,
        'stock': stock,
        'sku': sku,
        'vendor': vendor,
        'vendorId': vendorId,
      };

  factory CartLine.fromGuest(Map<String, dynamic> m) => CartLine(
        id: strOf(m['id'] ?? m['_id']),
        name: strOf(m['name'], 'Product'),
        image: strOf(m['image']),
        price: numOf(m['price']),
        qty: (numOf(m['qty'] ?? m['quantity'], 1).toInt()).clamp(1, _maxQty),
        stock: m['stock'] == null ? -1 : numOf(m['stock']).toInt(),
        status: strOf(m['status'], 'ACTIVE'),
        sku: strOf(m['sku']),
        vendor: _vendorName(m['vendor']),
        vendorId: strOf(m['vendorId']),
      );

  static CartLine? fromServer(Map<String, dynamic> item) {
    final prod = item['product'];
    if (prod is! Map) return null;
    final p = asMap(prod);
    final media = asMap(p['media']);
    final price = numOf(p['price']);
    final discount = numOf(p['discountPrice']);
    final effective = discount > 0 && discount < price ? discount : price;
    final vendor = p['vendor'];
    return CartLine(
      id: strOf(p['_id'] ?? p['id']),
      name: strOf(p['name'], 'Product'),
      image: resolveImageUrl(media['mainImage'] ?? p['image']),
      price: numOf(item['price']) > 0 ? numOf(item['price']) : effective,
      qty: numOf(item['quantity'], 1).toInt().clamp(1, _maxQty),
      stock: numOf(p['stockQuantity']).toInt(),
      status: strOf(p['status'], 'ACTIVE'),
      sku: strOf(p['sku']),
      vendor: _vendorName(vendor),
      vendorId: strOf(vendor is Map ? (vendor['_id'] ?? vendor['id']) : vendor),
    );
  }
}

String _vendorName(dynamic vendor) {
  if (vendor is Map) {
    return strOf(
      vendor['companyName'] ?? vendor['Fullname'] ?? vendor['fullName'] ?? vendor['businessName'] ?? vendor['name'],
      'MVEC Seller',
    );
  }
  return strOf(vendor, 'MVEC Seller');
}

class CartState {
  const CartState({this.lines = const [], this.loading = false, this.notice = ''});
  final List<CartLine> lines;
  final bool loading;
  final String notice;

  int get count => lines.fold(0, (n, l) => n + l.qty);
  num get subtotal => lines.fold<num>(0, (s, l) => s + l.price * l.qty);
  bool get blocked => lines.any((l) => l.unavailable || l.overStock);

  CartState copyWith({List<CartLine>? lines, bool? loading, String? notice}) => CartState(
        lines: lines ?? this.lines,
        loading: loading ?? this.loading,
        notice: notice ?? this.notice,
      );
}

typedef CartResult = ({bool ok, String message});

/// Guests keep the basket on the phone; once signed in the cart lives on the
/// account. Anything added while signed out is moved over at sign-in, like the
/// web `MarketplaceProvider`.
class CartNotifier extends Notifier<CartState> {
  int _seq = 0;

  SharedPreferences? get _prefs => ref.read(sharedPreferencesProvider);

  @override
  CartState build() {
    ref.listen<String?>(authProvider.select((a) => a.user?.id), (prev, next) {
      _load();
    });
    Future.microtask(_load);
    return CartState(lines: _readGuest());
  }

  List<CartLine> _readGuest() {
    try {
      final raw = _prefs?.getString(_guestCartKey);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.whereType<Map>().map((e) => CartLine.fromGuest(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return const [];
    }
  }

  void _writeGuest(List<CartLine> lines) {
    _prefs?.setString(_guestCartKey, jsonEncode([for (final l in lines) l.toJson()]));
  }

  List<CartLine> _fromServer(Map<String, dynamic> cart) =>
      asMaps(cart['items']).map(CartLine.fromServer).whereType<CartLine>().toList();

  bool get _signedIn => ref.read(authProvider).user != null;

  Future<void> _load() async {
    final auth = ref.read(authProvider);
    if (auth.restoring) return;
    final seq = ++_seq;
    if (auth.user == null) {
      state = CartState(lines: _readGuest());
      return;
    }
    state = state.copyWith(loading: true);
    try {
      // Move what was added while signed out into the account cart; items that
      // cannot be added are reported and the guest cart is cleared either way.
      final guest = _readGuest();
      final skipped = <String>[];
      for (final item in guest) {
        try {
          if (item.id.isNotEmpty) await CartApi.add(item.id, item.qty.clamp(1, _maxQty));
        } catch (e) {
          skipped.add('${item.name}: ${errorText(e)}');
        }
      }
      if (guest.isNotEmpty) await _prefs?.remove(_guestCartKey);
      final cart = await CartApi.get();
      if (seq == _seq) {
        state = CartState(
          lines: _fromServer(cart),
          notice: skipped.isEmpty ? '' : 'Some items could not be moved to your cart. ${skipped.join(' ')}',
        );
      }
    } catch (e) {
      if (seq == _seq) {
        state = state.copyWith(loading: false, notice: 'We could not load your cart. ${errorText(e)}');
      }
    }
  }

  Future<void> refresh() => _load();

  void dismissNotice() => state = state.copyWith(notice: '');

  Future<CartResult> add(Product p, [int qty = 1]) async {
    final id = p.id;
    final amount = qty.clamp(1, _maxQty);
    if (id.isEmpty) return (ok: false, message: 'This product cannot be added right now.');
    if (p.stock <= 0) return (ok: false, message: 'This product is out of stock.');

    if (!_signedIn) {
      final lines = [...state.lines];
      final i = lines.indexWhere((l) => l.id == id);
      final wanted = (i >= 0 ? lines[i].qty : 0) + amount;
      final capped = p.stock > 0 ? wanted.clamp(1, p.stock) : wanted;
      final message = capped < wanted ? 'Only ${p.stock} available. Your cart has the maximum.' : 'Added to your cart.';
      final line = CartLine(
        id: id,
        name: p.name,
        image: p.image,
        price: p.price,
        qty: capped.clamp(1, _maxQty),
        stock: p.stock,
        status: 'ACTIVE',
        sku: p.sku,
        vendor: p.vendor,
        vendorId: p.vendorId,
      );
      if (i >= 0) {
        lines[i] = line;
      } else {
        lines.add(line);
      }
      _writeGuest(lines);
      state = state.copyWith(lines: lines);
      return (ok: true, message: message);
    }
    try {
      final cart = await CartApi.add(id, amount);
      state = state.copyWith(lines: _fromServer(cart));
      return (ok: true, message: 'Added to your cart.');
    } catch (e) {
      return (ok: false, message: errorText(e));
    }
  }

  Future<CartResult> remove(String id) async {
    if (!_signedIn) {
      final lines = state.lines.where((l) => l.id != id).toList();
      _writeGuest(lines);
      state = state.copyWith(lines: lines);
      return (ok: true, message: '');
    }
    try {
      final cart = await CartApi.remove(id);
      state = state.copyWith(lines: _fromServer(cart));
      return (ok: true, message: '');
    } catch (e) {
      return (ok: false, message: errorText(e));
    }
  }

  Future<CartResult> setQty(String id, int qty) async {
    final i = state.lines.indexWhere((l) => l.id == id);
    final line = i >= 0 ? state.lines[i] : null;
    final max = line != null && line.stock > 0 ? line.stock.clamp(1, _maxQty) : _maxQty;
    final next = qty.clamp(1, max);
    if (line != null && next == line.qty) {
      return (ok: false, message: qty > max ? 'Only $max available.' : '');
    }
    if (!_signedIn) {
      final lines = [...state.lines];
      if (i >= 0) lines[i] = lines[i].withQty(next);
      _writeGuest(lines);
      state = state.copyWith(lines: lines);
      return (ok: true, message: '');
    }
    try {
      final cart = await CartApi.updateQuantity(id, next);
      state = state.copyWith(lines: _fromServer(cart));
      return (ok: true, message: '');
    } catch (e) {
      return (ok: false, message: errorText(e));
    }
  }

  /// After an order is placed from the cart the server has already emptied it.
  void clearLocal() {
    _prefs?.remove(_guestCartKey);
    state = const CartState();
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

// ─── Wishlist ────────────────────────────────────────────────────────────────

class WishItem {
  const WishItem({
    required this.id,
    required this.name,
    required this.image,
    required this.vendor,
    required this.price,
    required this.stock,
    required this.status,
    required this.savedPrice,
  });

  final String id;
  final String name;
  final String image;
  final String vendor;
  final num price;
  final int stock;
  final String status;
  final num savedPrice;

  bool get unavailable => status.isNotEmpty && !['ACTIVE', 'OUT_OF_STOCK'].contains(status);
  bool get soldOut => !unavailable && (status == 'OUT_OF_STOCK' || stock <= 0);
  bool get priceDropped => savedPrice > 0 && price < savedPrice;

  factory WishItem.fromServer(Map<String, dynamic> w) {
    final p = asMap(w['product']);
    final media = asMap(p['media']);
    final price = numOf(p['price']);
    final discount = numOf(p['discountPrice']);
    return WishItem(
      id: strOf(p['_id'] ?? p['id']),
      name: strOf(p['name'], 'Product'),
      image: resolveImageUrl(media['mainImage']),
      vendor: _vendorName(p['vendor']),
      price: discount > 0 && discount < price ? discount : price,
      stock: numOf(p['stockQuantity']).toInt(),
      status: strOf(p['status']),
      savedPrice: numOf(w['savedPrice']),
    );
  }

  Product asProduct() => Product(
        id: id,
        publicId: '',
        name: name,
        category: '',
        brand: '',
        vendor: vendor,
        vendorId: '',
        price: price,
        oldPrice: 0,
        rating: 0,
        reviews: 0,
        stock: stock,
        sku: '',
        image: image,
        gallery: const [],
        description: '',
        status: status.isEmpty ? 'ACTIVE' : status,
        slug: '',
        attributes: const {},
      );
}

/// The wishlist lives on the account, so it only exists when signed in.
class WishlistNotifier extends Notifier<List<WishItem>> {
  @override
  List<WishItem> build() {
    ref.listen<String?>(authProvider.select((a) => a.user?.id), (prev, next) {
      _load(next);
    }, fireImmediately: false);
    Future.microtask(() => _load(ref.read(authProvider).user?.id));
    return const [];
  }

  Future<void> _load(String? userId) async {
    if (userId == null) {
      state = const [];
      return;
    }
    try {
      final items = await AuthApi.wishlist();
      state = items.map(WishItem.fromServer).toList();
    } catch (_) {
      // Keep whatever is on screen.
    }
  }

  Future<void> refresh() => _load(ref.read(authProvider).user?.id);

  bool contains(String id) => state.any((w) => w.id == id);

  /// Returns false when the person must sign in first.
  Future<bool> toggle(Product p) async {
    if (ref.read(authProvider).user == null) return false;
    final exists = contains(p.id);
    final before = state;
    // Update the screen immediately, then sync with the account.
    state = exists
        ? state.where((w) => w.id != p.id).toList()
        : [
            ...state,
            WishItem(
              id: p.id,
              name: p.name,
              image: p.image,
              vendor: p.vendor,
              price: p.price,
              stock: p.stock,
              status: 'ACTIVE',
              savedPrice: p.price,
            ),
          ];
    try {
      final items = exists ? await AuthApi.wishlistRemove(p.id) : await AuthApi.wishlistAdd([p.id]);
      state = items.map(WishItem.fromServer).toList();
    } catch (_) {
      state = before;
    }
    return true;
  }

  Future<void> removeId(String id) async {
    final before = state;
    state = state.where((w) => w.id != id).toList();
    try {
      final items = await AuthApi.wishlistRemove(id);
      state = items.map(WishItem.fromServer).toList();
    } catch (_) {
      state = before;
    }
  }
}

final wishlistProvider = NotifierProvider<WishlistNotifier, List<WishItem>>(WishlistNotifier.new);
