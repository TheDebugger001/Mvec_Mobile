import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/catalog_api.dart';
import '../models/product.dart';

/// Paid ads live in the home banner, each shown for 5 seconds. Empty when
/// there is none right now (the banner then shows the marketplace slides).
final heroAdsProvider = FutureProvider.autoDispose<List<HeroAd>>((ref) async {
  try {
    return await CatalogApi.heroAds();
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
