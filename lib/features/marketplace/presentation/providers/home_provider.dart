import 'package:flutter/foundation.dart' hide Category;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_client.dart';
import '../../data/models/category_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/vendor_model.dart';
import '../../data/services/fallback_home_service.dart';
import '../../data/services/home_service.dart';

/// The home feed's data source.
///
/// Addressed through a provider so tests — and any future offline mode — can
/// swap the live API for a fixture without the app reading a different source
/// in `main`.
final homeServiceProvider = Provider<HomeService>(
  (ref) => FallbackHomeService(ApiClient.instance),
);

/// Promotional banner shown inside the home feed carousel.
class BannerItem {
  const BannerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.link,
  });

  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? link;

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    final media = json['media'];
    return BannerItem(
      id: _toInt(json['id']),
      title: _toString(json['title']),
      subtitle: _toString(json['subtitle']),
      imageUrl: media is Map
          ? _toString(media['mainImage'])
          : _toString(json['image_url'] ?? json['image']),
      link: json['link']?.toString(),
    );
  }

  static String _toString(dynamic value) => value?.toString() ?? '';

  static int _toInt(dynamic value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Aggregated data rendered by the home marketplace feed.
class HomeFeed {
  const HomeFeed({
    this.banners = const <BannerItem>[],
    this.categories = const <Category>[],
    this.featuredVendors = const <Vendor>[],
    this.featuredProducts = const <Product>[],
    this.recommendedProducts = const <Product>[],
    this.products = const <Product>[],
    this.recentlyViewed = const <Product>[],
  });

  final List<BannerItem> banners;
  final List<Category> categories;
  final List<Vendor> featuredVendors;
  final List<Product> featuredProducts;
  final List<Product> recommendedProducts;
  final List<Product> products;
  final List<Product> recentlyViewed;

  /// Deals are derived from products carrying a discount.
  List<Product> get deals =>
      products.where((product) => product.onSale).toList();

  /// All known vendors (featured set acts as the default store list).
  List<Vendor> get vendors => featuredVendors;

  /// Parses the feed payload.
  ///
  /// Every section is looked up under both spellings. The app reads either a
  /// camelCase payload or the snake_case a Node/Express backend sends, and
  /// guessing one of them wrong is not loud: the request succeeds, the section
  /// comes back empty and the storefront renders without its vendors or its
  /// featured row. Accepting both means a naming difference can never quietly
  /// empty the page.
  factory HomeFeed.fromJson(Map<String, dynamic> raw) {
    final json = _sourceOf(raw);
    return HomeFeed(
      banners: _section(json, 'banners', BannerItem.fromJson),
      categories: _section(json, 'categories', Category.fromJson),
      featuredVendors: _section(
        json,
        'featuredVendors',
        Vendor.fromJson,
        'featured_vendors',
      ),
      featuredProducts: _section(
        json,
        'featuredProducts',
        Product.fromJson,
        'featured_products',
      ),
      recommendedProducts: _section(
        json,
        'recommendedProducts',
        Product.fromJson,
        'recommended_products',
      ),
      products: _section(json, 'products', Product.fromJson),
      recentlyViewed: _section(
        json,
        'recentlyViewed',
        Product.fromJson,
        'recently_viewed',
      ),
    );
  }

  /// The map the sections actually live in.
  ///
  /// Most endpoints answer with the feed at the top level, but some wrap it in
  /// `{data: {...}}` or `{success: true, data: [...]}`. Unwrapping once here
  /// means the section lookups do not each have to repeat it, and a payload
  /// that is neither shape is returned untouched so it reads as empty rather
  /// than throwing.
  static Map<String, dynamic> _sourceOf(Map<String, dynamic> raw) {
    for (final key in const ['data', 'result']) {
      final inner = raw[key];
      if (inner is Map) {
        final map = Map<String, dynamic>.from(inner);
        // Only unwrap when the inner object is the sectioned feed; a `data`
        // object that holds the row itself is handled per section.
        const sectionKeys = {
          'banners',
          'categories',
          'featuredVendors',
          'featured_vendors',
          'featuredProducts',
          'featured_products',
          'recommendedProducts',
          'recommended_products',
          'products',
          'recentlyViewed',
          'recently_viewed',
        };
        if (map.keys.any(sectionKeys.contains)) return map;
      }
    }
    return raw;
  }

  /// Reads one section under [camel] or any of its [snake] aliases.
  ///
  /// Also unwraps a `{data: [...]}` or `{items: [...]}` envelope, and falls
  /// back to a single `data` payload spread across the sections when the server
  /// sends one flat object rather than a sectioned feed.
  static List<T> _section<T>(
    Map<String, dynamic> json,
    String camel,
    T Function(Map<String, dynamic>) fromJson, [
    String? snake,
  ]) {
    var value = json[camel];
    value ??= snake == null ? null : json[snake];

    // A single-item endpoint can answer with the row itself rather than a list.
    if (value is Map) value = _unwrap(Map<String, dynamic>.from(value));

    return _parse(value, fromJson);
  }

  static dynamic _unwrap(Map<String, dynamic> value) =>
      value['data'] ?? value['items'] ?? value['results'] ?? const <dynamic>[];

  static List<T> _parse<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
    if (value is! List<dynamic>) return <T>[];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

/// State manager for the marketpce home feed.
///
/// Depends on an injected [HomeService]. The default is [FallbackHomeService],
/// which reads the live feed and degrades to an empty storefront when the
/// endpoint is unreachable, so the UI stays decoupled from the data source.
class HomeProvider extends ChangeNotifier {
  HomeProvider({HomeService? service})
      : _service = service ?? FallbackHomeService(ApiClient.instance);

  final HomeService _service;

  HomeFeed _feed = const HomeFeed();
  bool _isLoading = true;
  String? _error;

  HomeFeed get feed => _feed;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True only when the feed comes from a bundled/local dataset.
  bool get isDemo => _service.isDemo;

  List<BannerItem> get banners => _feed.banners;
  List<Category> get categories => _feed.categories;
  List<Vendor> get vendors => _feed.vendors;
  List<Product> get featuredProducts => _feed.featuredProducts;
  List<Product> get recommendedProducts => _feed.recommendedProducts;
  List<Product> get products => _feed.products;
  List<Product> get recentlyViewed => _feed.recentlyViewed;
  List<Product> get deals => _feed.deals;

  /// Loads the home feed from the injected service and notifies listeners.
  Future<void> loadHomeFeed() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final payload = await _service.getHomeFeed();
      _feed = HomeFeed.fromJson(payload);
    } catch (e) {
      _error = 'Could not load the home feed: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Tracks a product as recently viewed (deduplicated, capped at 12).
  void addRecentlyViewed(Product product) {
    final updated = List<Product>.of(_feed.recentlyViewed)
      ..removeWhere((item) => item.id == product.id)
      ..insert(0, product);
    if (updated.length > 12) {
      updated.removeRange(12, updated.length);
    }
    _feed = HomeFeed(
      banners: _feed.banners,
      categories: _feed.categories,
      featuredVendors: _feed.featuredVendors,
      featuredProducts: _feed.featuredProducts,
      recommendedProducts: _feed.recommendedProducts,
      products: _feed.products,
      recentlyViewed: updated,
    );
    notifyListeners();
  }
}