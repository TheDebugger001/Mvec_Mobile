import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../../data/models/category_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/vendor_model.dart';
import '../../data/services/home_service.dart';
import '../../data/services/api_home_service.dart';

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

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    final nested = json['feed'];
    final data = nested is Map
        ? Map<String, dynamic>.from(nested)
        : json;
    final products = json['products'] ??
        data['products'] ??
        data['featuredProducts'];

    return HomeFeed(
      banners: _parse(data['banners'], BannerItem.fromJson),
      categories: _parse(data['categories'], Category.fromJson),
      featuredVendors: _parse(
        data['featuredVendors'] ?? data['topVendors'],
        Vendor.fromJson,
      ),
      featuredProducts: _parse(data['featuredProducts'], Product.fromJson),
      recommendedProducts: _parse(
        data['recommendedProducts'],
        Product.fromJson,
      ),
      products: _parse(products, Product.fromJson),
      recentlyViewed: _parse(data['recentlyViewed'], Product.fromJson),
    );
  }

  static List<T> _parse<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
    if (value is! List<dynamic>) return <T>[];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}

/// State manager for the marketplace home feed.
///
/// The app is backend-first: the provider resolves the live API response and
/// never ships with bundled mock marketplace content.
class HomeProvider extends ChangeNotifier {
  HomeProvider({HomeService? service}) : _service = service ?? ApiHomeService() {
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => loadHomeFeed(),
    );
  }

  final HomeService _service;
  late final Timer _refreshTimer;

  HomeFeed _feed = const HomeFeed();
  bool _isLoading = true;
  bool _isFetching = false;
  bool _hasLoaded = false;
  String? _error;

  HomeFeed get feed => _feed;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Whether the current data comes from the local mock service.
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
    if (_isFetching) return;
    _isFetching = true;
    _isLoading = !_hasLoaded;
    _error = null;
    notifyListeners();

    try {
      final payload = await _service.getHomeFeed();
      _feed = HomeFeed.fromJson(payload);
    } catch (e) {
      _error = 'Could not load the home feed: $e';
    } finally {
      _hasLoaded = true;
      _isFetching = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
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