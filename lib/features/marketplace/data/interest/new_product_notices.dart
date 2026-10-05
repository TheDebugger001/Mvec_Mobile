import '../models/product_model.dart';
import 'interest_profile.dart';

/// Why a product was surfaced to this account, in words the shopper can check.
enum NoticeReason {
  /// Brand new, in a category this account has actually bought from.
  newInFamiliarCategory,

  /// Brand new, in a category they have only browsed or wishlisted.
  newInBrowsedCategory,
}

/// One "you might like this" entry in the shopper's notifications.
class NewProductNotice {
  const NewProductNotice({
    required this.product,
    required this.categoryId,
    required this.categoryName,
    required this.reason,
    required this.matchScore,
  });

  final Product product;
  final int categoryId;
  final String categoryName;
  final NoticeReason reason;

  /// How strongly this product matches the account's history, so the strongest
  /// match can be listed first and explained.
  final double matchScore;

  String get title => 'New in $categoryName';

  String get body => switch (reason) {
    NoticeReason.newInFamiliarCategory =>
      '${product.name} just landed in $categoryName, a category you buy from.',
    NoticeReason.newInBrowsedCategory =>
      '${product.name} is new in $categoryName, which you have been looking at.',
  };
}

/// Category score at which a category counts as one they buy from, rather than
/// one they have only browsed.
///
/// A single purchase lands near 6.3 and a cart add near 3.7, while a wishlist
/// is ~2.7 and a handful of views stays under 2.5 — so this falls between the
/// two groups. It only chooses the wording; both kinds still get notified.
const double _boughtThreshold = 3.0;

/// Builds the "new products you might want" list for one account.
///
/// Returns an empty list for a guest, an account with no interest recorded yet,
/// or nothing new to say — the page then falls back to its plain signed-out
/// empty state rather than inventing recommendations.
///
/// Already-surfaced products are held back by [InterestProfile.seenProductIds]
/// so the same phone does not reappear every visit.
List<NewProductNotice> newProductNotices({
  required List<Product> catalogue,
  required InterestProfile? profile,
  required DateTime now,
  Map<int, String> categoryNames = const <int, String>{},
  int limit = 20,
}) {
  if (profile == null || !profile.hasSignal) return const <NewProductNotice>[];
  final scores = <int, double>{};
  for (final categoryId in profile.rankedCategoryIds(now)) {
    scores[categoryId] = profile.scoreOf(categoryId, now);
  }
  if (scores.isEmpty) return const <NewProductNotice>[];

  final notices = <NewProductNotice>[];
  for (final product in catalogue) {
    final categoryId = product.categoryId;
    if (categoryId == null) continue;
    final score = scores[categoryId] ?? 0;
    if (score <= 0) continue;
    if (profile.seenProductIds.contains(product.id)) continue;
    if (!product.inStock) continue;
    // Only genuine new arrivals. Anything else would invent a reason to
    // interrupt someone: nothing in the catalogue claims an existing product
    // has just come back into stock.
    if (!product.isNewArrival) continue;

    final NoticeReason reason =
        score >= _boughtThreshold
            ? NoticeReason.newInFamiliarCategory
            : NoticeReason.newInBrowsedCategory;

    final name = product.categoryName;
    notices.add(
      NewProductNotice(
        product: product,
        categoryId: categoryId,
        categoryName:
            (name == null || name.trim().isEmpty)
                ? categoryNames[categoryId] ?? 'your saved categories'
                : name,
        reason: reason,
        matchScore: score,
      ),
    );
  }

  // Strongest match first; ties fall back to catalogue order so the list is
  // stable between two launches.
  notices.sort((a, b) {
    final byScore = b.matchScore.compareTo(a.matchScore);
    return byScore != 0 ? byScore : a.product.id.compareTo(b.product.id);
  });
  return notices.take(limit).toList();
}
