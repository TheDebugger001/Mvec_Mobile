import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/catalog_api.dart';
import '../models/product.dart';

/// Products whose ad campaign MVEC approved for the home-page hero. Empty when
/// there is none right now (the web shows a stand-in photo in that case).
final heroAdsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  try {
    return await CatalogApi.liveAds('HOMEPAGE_HERO', limit: 6);
  } catch (_) {
    return const [];
  }
});

/// Featured placements (the scrolling strip on the web home page).
final featuredAdsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  try {
    return await CatalogApi.liveAds('FEATURED', limit: 12);
  } catch (_) {
    return const [];
  }
});
