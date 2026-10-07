import '../widgets/local_image_source.dart';
import '../core/api_client.dart';
import '../models/catalog.dart';
import '../models/vendor.dart';
import '../models/vendor_product.dart';
import 'vendor_product_image_store.dart';

/// Vendor-facing API calls.
///
/// Every endpoint here is scoped to the signed-in vendor's own store
/// (`/stores/mine…`), so none of them need a store id. Mirrors the shape of
/// `AdminService`: the same [ApiClient] is injected, and each method unwraps
/// the backend envelope into a domain model.
class VendorService {
  VendorService(this._api);
  final ApiClient _api;

  final _productImages = VendorProductImageStore();

  // ---------- Store profile ----------

  /// The vendor's own profile record, or `null` when they have not completed
  /// onboarding yet. The backend returns this under the `vendor` envelope.
  Future<StoreProfile?> myStore() async {
    try {
      final res = await _api.get('/vendors/me/profile');
      return StoreProfile.fromJson(singleJson(res, ['vendor']));
    } catch (e) {
      if (statusCodeOf(e) == 404) return null;
      rethrow;
    }
  }

  /// Saves the vendor profile using the backend's actual onboarding / profile
  /// routes. The profile is resolved from the auth token, so no id is sent.
  Future<StoreProfile> updateStore(Map<String, dynamic> body) async {
    final current = await myStore();
    final res = current == null
        ? await _api.post('/vendors/onboard', body: body)
        : await _api.patch('/vendors/me/profile', body: body);
    return StoreProfile.fromJson(singleJson(res, ['vendor']));
  }

  // ---------- Verification ----------

  /// Submits verification documents for review. Each entry is
  /// `{type, url}`; the platform moves the store to `PENDING`.
  Future<StoreProfile> submitDocuments(
    List<Map<String, String>> documents,
  ) async {
    throw ApiException(
      'Document submission is not available: the backend has no vendor verification endpoint.',
    );
  }

  // ---------- Overview ----------

  /// Builds the overview from the vendor product, order and payout endpoints
  /// that the backend exposes.
  Future<VendorStats> stats() async {
    final responses = await Future.wait([
      _api.get('/products/vendor/me'),
      _api.get('/orders/vendor/orders'),
      _api.get('/payouts/balance'),
    ]);
    final products = listJson(responses[0], ['products', 'data']);
    final orders = listJson(responses[1], ['orders', 'data']);
    final balance = singleJson(responses[2], ['balance']);
    final today = DateTime.now();
    final todaySales = orders.fold<num>(0, (sum, order) {
      final createdAt = DateTime.tryParse('${order['createdAt'] ?? ''}');
      final paid = '${order['paymentStatus'] ?? ''}'.toUpperCase() == 'PAID';
      if (!paid ||
          createdAt == null ||
          createdAt.year != today.year ||
          createdAt.month != today.month ||
          createdAt.day != today.day) {
        return sum;
      }
      final amount = order['vendorSubtotal'] ?? order['totalAmount'] ?? 0;
      return sum + (amount is num ? amount : num.tryParse('$amount') ?? 0);
    });
    final openOrders = orders.where((order) {
      final status = '${order['orderStatus'] ?? ''}'.toUpperCase();
      return !const {'DELIVERED', 'COMPLETED', 'CANCELLED', 'REFUNDED'}
          .contains(status);
    }).length;
    final lowStock = products.where((product) {
      final quantity = _number(product['stockQuantity'] ?? product['stock']);
      final threshold = _number(
        product['lowStockThreshold'] ?? product['reorderPoint'],
      ) ?? 5;
      return quantity != null && quantity <= threshold;
    }).length;
    return VendorStats(
      dailySales: todaySales,
      activeOrders: openOrders,
      lowStock: lowStock,
      totalProducts: products.length,
      totalOrders: orders.length,
      pendingPayout: _number(balance['availableBalance']),
    );
  }

  /// Combines the available vendor order and payout feeds. The backend has no
  /// general activity endpoint or inventory-event history.
  Future<Paged<VendorActivity>> activity({
    int page = 1,
    int limit = 20,
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    final responses = await Future.wait([
      _api.get('/orders/vendor/orders'),
      _api.get('/payouts/history'),
    ]);
    final rows = <VendorActivity>[
      for (final order in listJson(responses[0], ['orders', 'data']))
        VendorActivity.fromJson({
          ...order,
          'type': 'ORDERS',
          'title': 'Order ${order['orderNumber'] ?? ''}',
          'amount': order['vendorSubtotal'] ?? order['totalAmount'],
          'status': order['orderStatus'],
          'reference': order['orderNumber'],
        }),
      for (final payout in listJson(responses[1], ['payouts', 'data']))
        VendorActivity.fromJson({
          ...payout,
          'type': 'PAYOUTS',
          'title': 'Payout ${payout['payoutNumber'] ?? ''}',
          'reference': payout['payoutNumber'],
        }),
    ]..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    final filtered = rows.where((row) {
      if (from != null && (row.date == null || row.date!.isBefore(from))) {
        return false;
      }
      if (to != null &&
          (row.date == null ||
              row.date!.isAfter(DateTime(to.year, to.month, to.day, 23, 59)))) {
        return false;
      }
      return type == null || type.isEmpty || type == 'ALL' || row.bucket == type;
    }).toList();
    final offset = (page - 1) * limit;
    final items = offset >= filtered.length
        ? <VendorActivity>[]
        : filtered.skip(offset).take(limit).toList();
    return Paged(
      items: items,
      total: filtered.length,
      page: page,
      pages: (filtered.length / limit).ceil(),
      pageSize: limit,
    );
  }

  // ---------- Products ----------

  /// Fetches the vendor's catalogue, then filters and paginates it locally
  /// because the backend returns the complete product list.
  Future<Paged<VendorProduct>> products({
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    bool? lowStockOnly,
  }) async {
    final res = await _api.get('/products/vendor/me');
    final allProducts = listJson(res, ['products', 'data'])
        .map(VendorProduct.fromJson)
        .toList();
    final localImages = await _productImages.readAll();
    for (final product in allProducts) {
      final id = product.id;
      if (id != null) {
        final paths = localImages[id] ?? const <String>[];
        product.localImagePaths = paths;
        product.localImagePath = paths.isEmpty ? null : paths.first;
      }
    }
    final term = search?.trim().toLowerCase() ?? '';
    final filtered = allProducts.where((product) {
      if (term.isNotEmpty &&
          !product.display.toLowerCase().contains(term) &&
          !(product.sku ?? '').toLowerCase().contains(term)) {
        return false;
      }
      if (status != null &&
          status.isNotEmpty &&
          status != 'ALL' &&
          product.availability != status) {
        return false;
      }
      return lowStockOnly != true || product.isLowStock || product.isOutOfStock;
    }).toList();
    final offset = (page - 1) * limit;
    return Paged(
      items: offset >= filtered.length
          ? <VendorProduct>[]
          : filtered.skip(offset).take(limit).toList(),
      total: filtered.length,
      page: page,
      pages: (filtered.length / limit).ceil(),
      pageSize: limit,
    );
  }

  Future<VendorProduct> createProduct(Map<String, dynamic> body) async {
    final res = await _api.post('/products', body: body);
    return VendorProduct.fromJson(singleJson(res, ['product']));
  }

  Future<VendorProduct> updateProduct(
    String id,
    Map<String, dynamic> body,
  ) async {
    final res = await _api.put('/products/$id', body: body);
    return VendorProduct.fromJson(singleJson(res, ['product']));
  }

  /// Flips a listing between `ACTIVE` and `INACTIVE` without touching any
  /// other field — the availability toggle in the product list.
  Future<VendorProduct> setAvailability(String id, String status) async {
    final res = await _api.put('/products/$id', body: {'status': status});
    return VendorProduct.fromJson(singleJson(res, ['product']));
  }

  /// Soft-deletes a listing: the record is flagged removed, keeping its order
  /// history intact, rather than being erased.
  Future<void> removeProduct(String id) async {
    await _api.delete('/products/$id');
    final imagePaths = await _productImages.remove(id);
    for (final imagePath in imagePaths ?? const <String>[]) {
      await releaseLocalImage(imagePath);
    }
  }

  // ---------- Categories ----------

  /// Categories offered in the product form's category picker.
  Future<List<CategoryRecord>> categories() async {
    final res = await _api.get('/categories', query: {'tree': 'false'});
    return listJson(res, [
      'categories',
      'data',
    ]).map(CategoryRecord.fromJson).toList();
  }

  static num? _number(dynamic value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '');
}
