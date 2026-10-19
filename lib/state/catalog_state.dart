import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/catalog_api.dart';
import '../models/product.dart';

/// Everything the storefront browses, loaded together like `loadCatalog()` in
/// the web app and cached for five minutes.
class Catalog {
  const Catalog({
    this.products = const [],
    this.categories = const [],
    this.stores = const [],
    this.error = false,
  });

  final List<Product> products;
  final List<CategoryInfo> categories;
  final List<StoreSummary> stores;
  final bool error;

  List<String> get categoryNames => categories.map((c) => c.name).toList();

  List<Product> get deals => products.where((p) => p.onSale && p.stock > 0).toList();

  /// Best rated with the most reviews first (the web "Popular" order).
  List<Product> get popular {
    double score(Product p) => p.rating.toDouble() * math.log(1 + p.reviews);
    final list = [...products];
    list.sort((a, b) => score(b).compareTo(score(a)));
    return list;
  }
}

class CatalogNotifier extends AsyncNotifier<Catalog> {
  DateTime? _at;

  @override
  Future<Catalog> build() async {
    final c = await _load();
    _at = DateTime.now();
    return c;
  }

  Future<Catalog> _load() async {
    final results = await Future.wait<Object?>([
      CatalogApi.products().then<Object?>((v) => v).catchError((_) => null),
      CatalogApi.categories().then<Object?>((v) => v).catchError((_) => null),
      CatalogApi.stores(pageSize: 100).then<Object?>((v) => v).catchError((_) => null),
    ]);
    final products = (results[0] as List<Product>?) ?? const <Product>[];
    final categories = (results[1] as List<CategoryInfo>?) ?? const <CategoryInfo>[];
    final storeRes = results[2] as ({List<StoreSummary> stores, int total})?;
    final stores = (storeRes?.stores ?? const <StoreSummary>[]).map((s) {
      final own = products.where((p) => p.vendorId.isNotEmpty && p.vendorId == s.userId).toList();
      final counts = <String, int>{};
      for (final p in own) {
        counts[p.category] = (counts[p.category] ?? 0) + 1;
      }
      final top = counts.entries.isEmpty
          ? ''
          : (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      return s.withProducts(own.length, top.isEmpty ? 'Marketplace store' : top);
    }).toList();
    return Catalog(
      products: products,
      categories: categories,
      stores: stores,
      error: results[0] == null,
    );
  }

  /// Reload now. When [force] is false a recent load is reused.
  Future<void> refresh({bool force = true}) async {
    if (!force && _at != null && DateTime.now().difference(_at!) < const Duration(minutes: 5)) {
      return;
    }
    state = const AsyncLoading<Catalog>().copyWithPrevious(state);
    state = await AsyncValue.guard(_load);
    _at = DateTime.now();
  }
}

final catalogProvider = AsyncNotifierProvider<CatalogNotifier, Catalog>(CatalogNotifier.new);
