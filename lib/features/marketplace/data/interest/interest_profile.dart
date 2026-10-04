import 'dart:math' as math;

import '../models/product_model.dart';

/// A behaviour that says something about what a shopper buys.
///
/// The weights are what make the ordering defensible rather than a count of
/// taps: buying a thing is a far stronger statement about the next purchase
/// than looking at one, so a single order outweighs a long tail of views.
enum InterestSignal {
  viewed(1.0),
  wishlisted(3.0),
  carted(4.5),
  purchased(9.0);

  const InterestSignal(this.weight);

  final double weight;
}

/// One category's accumulated evidence, with when it was last seen.
class CategoryInterest {
  const CategoryInterest({required this.weight, required this.lastSignalAt});

  final double weight;
  final DateTime lastSignalAt;

  /// Evidence fades: a category someone bought from last month is a better
  /// guide than one they browsed a year ago, and without decay the feed would
  /// freeze on whatever they happened to look at first.
  ///
  /// Halves every [halfLifeDays], so old signal never quite reaches zero but
  /// stops competing with anything recent.
  double score(DateTime now, {int halfLifeDays = 21}) {
    final days = now.difference(lastSignalAt).inHours / 24.0;
    if (days <= 0) return weight;
    return weight * math.pow(2, -days / halfLifeDays).toDouble();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'w': weight,
    't': lastSignalAt.toIso8601String(),
  };

  static CategoryInterest? fromJson(dynamic value) {
    if (value is! Map) return null;
    final weight = _toDouble(value['w']);
    final at = DateTime.tryParse('${value['t']}');
    if (weight <= 0 || at == null) return null;
    return CategoryInterest(weight: weight, lastSignalAt: at);
  }
}

/// What one account has shown interest in, per category.
///
/// Keyed by `categoryId` so it survives a category being renamed. This is a
/// plain immutable value with no Flutter or Riverpod in it, which keeps the
/// ranking rule testable on its own.
class InterestProfile {
  const InterestProfile({
    this.categories = const <int, CategoryInterest>{},
    this.seenProductIds = const <int>{},
  });

  /// categoryId -> accumulated evidence.
  final Map<int, CategoryInterest> categories;

  /// Products already surfaced, so a "new in your categories" notification is
  /// not repeated forever for something they have already been told about.
  final Set<int> seenProductIds;

  static const InterestProfile empty = InterestProfile();

  /// Ceiling on how much a single category can accumulate, so no one category
  /// can take over the feed on volume alone. A purchase (weight 9) lands near
  /// half of it.
  static const double _saturationCeiling = 12;

  /// Nothing observed yet, so there is nothing to personalise with.
  bool get isEmpty => categories.isEmpty;

  /// Whether this shopper has enough signal to justify reordering anything.
  ///
  /// One stray view is noise, so a single category has to clear a weight bar
  /// before it is acted on; two different categories count on their own.
  bool get hasSignal => categories.length >= 2 || _totalWeight >= 3;

  double get _totalWeight =>
      categories.values.fold<double>(0, (sum, c) => sum + c.weight);

  /// The categories this account leans towards, strongest first.
  List<int> rankedCategoryIds(DateTime now) {
    final entries =
        categories.entries.toList()..sort((a, b) {
          final byScore = b.value.score(now).compareTo(a.value.score(now));
          // Ties keep catalogue order so the feed does not reshuffle on reload.
          return byScore != 0 ? byScore : a.key.compareTo(b.key);
        });
    return entries.map((e) => e.key).toList();
  }

  /// Score of a category at [now], or 0 when it is not one of this shopper's.
  double scoreOf(int? categoryId, DateTime now) {
    if (categoryId == null) return 0;
    final interest = categories[categoryId];
    return interest == null ? 0 : interest.score(now);
  }

  /// Adds one observation, returning a new profile.
  ///
  /// Repeated signals inside the same category add up but with diminishing
  /// returns, so browsing twenty phones does not drown out everything else.
  InterestProfile record({
    required int? categoryId,
    required InterestSignal signal,
    required int? productId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final next = Map<int, CategoryInterest>.of(categories);
    if (categoryId != null) {
      final existing = next[categoryId];
      final prior = existing == null ? 0.0 : existing.weight;
      // Saturating accumulation: evidence keeps counting but with diminishing
      // returns, so browsing twenty phones in one sitting cannot outweigh every
      // other interest the account has shown. Monotonically increasing in
      // `prior + signal`, which is what makes repeated taps accumulate instead
      // of overwriting each other.
      final combined = prior + signal.weight;
      next[categoryId] = CategoryInterest(
        weight:
            _saturationCeiling * (1 - math.exp(-combined / _saturationCeiling)),
        lastSignalAt: at,
      );
    }
    return InterestProfile(
      categories: next,
      seenProductIds:
          productId == null
              ? seenProductIds
              : <int>{...seenProductIds, productId},
    );
  }

  /// Marks products as already surfaced.
  InterestProfile markSeen(Iterable<int> productIds) => InterestProfile(
    categories: categories,
    seenProductIds: <int>{...seenProductIds, ...productIds},
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'categories': categories.map((k, v) => MapEntry('$k', v.toJson())),
    'seen': seenProductIds.toList(),
  };

  static InterestProfile fromJson(dynamic value) {
    if (value is! Map) return empty;
    final rawCategories = value['categories'];
    final categories = <int, CategoryInterest>{};
    if (rawCategories is Map) {
      rawCategories.forEach((key, entry) {
        final id = int.tryParse('$key');
        final interest = CategoryInterest.fromJson(entry);
        if (id != null && interest != null) categories[id] = interest;
      });
    }
    final rawSeen = value['seen'];
    final seen =
        rawSeen is List
            ? rawSeen.map((e) => int.tryParse('$e')).whereType<int>().toSet()
            : <int>{};
    return InterestProfile(categories: categories, seenProductIds: seen);
  }
}

/// Orders [products] so the ones matching this shopper's categories come
/// first, strongest category first, and everything else keeps its original
/// order behind them.
///
/// With no profile, or no signal worth acting on, the list is returned
/// untouched — a guest and a brand-new account both see the catalogue as it
/// was written, rather than a personalised-looking page built from one tap.
List<Product> rankByInterest(
  List<Product> products,
  InterestProfile? profile, {
  DateTime? now,
}) {
  if (profile == null || !profile.hasSignal) return products;
  final at = now ?? DateTime.now();

  final ranked = profile.rankedCategoryIds(at);
  final rank = <int, int>{for (var i = 0; i < ranked.length; i++) ranked[i]: i};

  final matched = <({int index, int rank, double score})>[];
  final rest = <({int index, Product product})>[];
  for (var i = 0; i < products.length; i++) {
    final product = products[i];
    final r = rank[product.categoryId];
    if (r == null) {
      rest.add((index: i, product: product));
    } else {
      matched.add((
        index: i,
        rank: r,
        score: profile.scoreOf(product.categoryId, at),
      ));
    }
  }
  // Rank first, then score, then original position: a stable, explainable
  // order that does not reshuffle between two builds of the same catalogue.
  matched.sort((a, b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return <Product>[
    ...matched.map((m) => products[m.index]),
    ...rest.map((r) => r.product),
  ];
}

/// The categories whose products should be treated as "likely to be bought".
Set<int> interestCategoryIds(InterestProfile? profile, DateTime now) {
  if (profile == null || !profile.hasSignal) return const <int>{};
  return profile.rankedCategoryIds(now).toSet();
}

double _toDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
