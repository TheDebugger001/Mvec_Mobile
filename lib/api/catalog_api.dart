import '../core/api_client.dart';
import '../core/format.dart';
import '../models/product.dart';

/// Everything the storefront shows: products, categories, stores, search,
/// sponsored placements and reviews (`catalogApi.js` + `API/*` in the web app).
class CatalogApi {
  CatalogApi._();
  static final _api = Api.instance;

  /// Live products (public). The backend only ever returns ACTIVE ones.
  static Future<List<Product>> products({Map<String, dynamic>? query}) async {
    final res = asMap(await _api.get('/products', query: query));
    return asMaps(res['products']).map(Product.fromJson).where((p) => p.id.isNotEmpty).toList();
  }

  static Future<Product> product(String id) async {
    if (id.isEmpty || id == 'undefined') throw ApiException('Product ID is missing.');
    final res = asMap(await _api.get('/products/$id'));
    return Product.fromJson(asMap(res['product']));
  }

  /// Personalised picks; `personalized` is true when based on past orders.
  static Future<({List<Product> products, bool personalized})> recommendations({int limit = 8}) async {
    final res = asMap(await _api.get('/products/recommendations', query: {'limit': limit}));
    return (
      products: asMaps(res['products']).map(Product.fromJson).toList(),
      personalized: res['personalized'] == true,
    );
  }

  static Future<List<CategoryInfo>> categories() async {
    final res = asMap(await _api.get('/categories'));
    return asMaps(res['categories'])
        .map(CategoryInfo.fromJson)
        .where((c) => c.name.isNotEmpty)
        .toList();
  }

  /// Stores, paged (`{data, meta:{total}}`).
  static Future<({List<StoreSummary> stores, int total})> stores({int page = 1, int pageSize = 100}) async {
    final res = asMap(await _api.get('/vendors', query: {'page': page, 'pageSize': pageSize}));
    final raw = asMaps(res['data'] ?? res['vendors']);
    final total = numOf(asMap(res['meta'])['total'], raw.length).toInt();
    return (stores: raw.map(StoreSummary.fromJson).where((s) => s.id.isNotEmpty).toList(), total: total);
  }

  /// One store by id or slug, with follow state.
  static Future<Map<String, dynamic>> store(String idOrSlug) async =>
      asMap(asMap(await _api.get('/vendors/$idOrSlug'))['vendor']);

  static Future<({bool following, int followers})> follow(String vendorId, {required bool follow}) async {
    final res = asMap(follow
        ? await _api.post('/vendors/$vendorId/follow')
        : await _api.delete('/vendors/$vendorId/follow'));
    return (following: res['following'] == true, followers: numOf(res['followers']).toInt());
  }

  /// Approved, live ads for a slot: HOMEPAGE_HERO, FEATURED, ...
  static Future<List<Product>> liveAds(String placement, {int limit = 6}) async {
    final res = asMap(await _api.get('/advertisements', query: {'placement': placement, 'limit': limit}));
    return asMaps(res['data'])
        .map((ad) => asMap(ad['product']))
        .where((p) => p.isNotEmpty)
        .map(Product.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  /// Sponsored product ids for a surface (`shop`, `home`, `search`, `category`).
  static Future<List<({String adId, String productId})>> sponsored({
    String surface = 'shop',
    String? q,
    String? category,
    int limit = 4,
  }) async {
    final res = asMap(await _api.get('/ads/sponsored',
        query: {'surface': surface, 'q': q, 'category': category, 'limit': limit}));
    return asMaps(res['data'])
        .map((a) => (adId: strOf(a['adId']), productId: strOf(a['productId'])))
        .where((a) => a.productId.isNotEmpty)
        .toList();
  }

  static Future<void> adClick(String adId) async {
    try {
      await _api.post('/ads/$adId/click');
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> reviews(String productId) async =>
      asMaps(asMap(await _api.get('/reviews/product/$productId'))['reviews']);

  static Future<void> createReview({
    required String productId,
    required int rating,
    required String text,
  }) async =>
      _api.post('/reviews', body: {'product': productId, 'rating': rating, 'reviewText': text});
}
