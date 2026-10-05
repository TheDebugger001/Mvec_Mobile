// Tests for the storefront's interest model and the ranking it drives.
//
// The ranking rule is deliberately a pure function of (catalogue, profile) so
// the behaviour that decides what a shopper sees first can be pinned here
// rather than inferred from a rendered grid.

import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/features/marketplace/data/interest/interest_profile.dart';
import 'package:mvec_mobile/features/marketplace/data/interest/interest_store.dart';
import 'package:mvec_mobile/features/marketplace/data/interest/new_product_notices.dart';
import 'package:mvec_mobile/features/marketplace/data/models/category_model.dart';
import 'package:mvec_mobile/features/marketplace/data/models/product_model.dart';

Product _product(
  int id,
  String name, {
  int? categoryId,
  String? categoryName,
  List<String> badges = const <String>[],
  int stock = 10,
}) => Product(
  id: id,
  name: name,
  slug: name.toLowerCase().replaceAll(' ', '-'),
  description: 'A product used by the interest tests.',
  price: 10,
  imageUrl: '',
  stockQuantity: stock,
  badges: badges,
  categoryId: categoryId,
  categoryName: categoryName,
);

/// Builds a profile from a handful of interactions, as the store would.
InterestProfile _profile({
  required List<({int? categoryId, InterestSignal signal})> signals,
  DateTime? now,
}) {
  var profile = InterestProfile.empty;
  for (final s in signals) {
    profile = profile.record(
      categoryId: s.categoryId,
      signal: s.signal,
      productId: null,
      now: now,
    );
  }
  return profile;
}

void main() {
  final now = DateTime(2026, 3, 1);

  group('interest accumulation', () {
    test('a purchase outweighs a view', () {
      final viewed = InterestProfile.empty.record(
        categoryId: 1,
        signal: InterestSignal.viewed,
        productId: null,
        now: now,
      );
      final bought = InterestProfile.empty.record(
        categoryId: 1,
        signal: InterestSignal.purchased,
        productId: null,
        now: now,
      );

      expect(bought.scoreOf(1, now), greaterThan(viewed.scoreOf(1, now)));
    });

    test('repeated signals accumulate but with diminishing returns', () {
      final once = InterestProfile.empty.record(
        categoryId: 1,
        signal: InterestSignal.viewed,
        productId: null,
        now: now,
      );
      final twice = once.record(
        categoryId: 1,
        signal: InterestSignal.viewed,
        productId: null,
        now: now,
      );
      final thrice = twice.record(
        categoryId: 1,
        signal: InterestSignal.viewed,
        productId: null,
        now: now,
      );

      // Strictly increasing...
      expect(twice.scoreOf(1, now), greaterThan(once.scoreOf(1, now)));
      expect(thrice.scoreOf(1, now), greaterThan(twice.scoreOf(1, now)));
      // ...but each step adds less than the one before.
      final firstGain = twice.scoreOf(1, now) - once.scoreOf(1, now);
      final secondGain = thrice.scoreOf(1, now) - twice.scoreOf(1, now);
      expect(secondGain, lessThan(firstGain));
    });

    test('one category cannot run away with the feed', () {
      var profile = InterestProfile.empty;
      for (var i = 0; i < 200; i++) {
        profile = profile.record(
          categoryId: 1,
          signal: InterestSignal.viewed,
          productId: null,
          now: now,
        );
      }
      // Saturated, not unbounded.
      expect(profile.scoreOf(1, now), lessThan(13));
    });

    test('old evidence fades relative to recent evidence', () {
      final old = _profile(
        signals: [(categoryId: 1, signal: InterestSignal.purchased)],
        now: now.subtract(const Duration(days: 120)),
      );
      final recent = _profile(
        signals: [(categoryId: 2, signal: InterestSignal.wishlisted)],
        now: now,
      );

      expect(old.scoreOf(1, now), lessThan(recent.scoreOf(2, now)));
    });
  });

  group('hasSignal', () {
    test('a single category with one weak view is not enough', () {
      final profile = _profile(
        signals: [(categoryId: 1, signal: InterestSignal.viewed)],
        now: now,
      );
      expect(profile.hasSignal, isFalse);
    });

    test('two different categories count on their own', () {
      final profile = _profile(
        signals: [
          (categoryId: 1, signal: InterestSignal.viewed),
          (categoryId: 2, signal: InterestSignal.viewed),
        ],
        now: now,
      );
      expect(profile.hasSignal, isTrue);
    });

    test('a purchase in one category is enough', () {
      final profile = _profile(
        signals: [(categoryId: 1, signal: InterestSignal.purchased)],
        now: now,
      );
      expect(profile.hasSignal, isTrue);
    });
  });

  group('rankByInterest', () {
    final catalogue = <Product>[
      _product(1, 'Phone case', categoryId: 9),
      _product(2, 'Running shoes', categoryId: 5, categoryName: 'Sports'),
      _product(3, 'Laptop stand', categoryId: 1, categoryName: 'Electronics'),
      _product(4, 'Desk lamp', categoryId: 7),
      _product(5, 'USB hub', categoryId: 1, categoryName: 'Electronics'),
    ];

    test('a guest gets the catalogue untouched', () {
      expect(rankByInterest(catalogue, null, now: now), catalogue);
    });

    test('an account with no signal gets the catalogue untouched', () {
      final profile = _profile(
        signals: [(categoryId: 1, signal: InterestSignal.viewed)],
        now: now,
      );
      expect(rankByInterest(catalogue, profile, now: now), catalogue);
    });

    test('matching categories come first and the rest keep their order', () {
      final profile = _profile(
        signals: [
          (categoryId: 1, signal: InterestSignal.purchased),
          (categoryId: 5, signal: InterestSignal.wishlisted),
        ],
        now: now,
      );

      final ranked = rankByInterest(catalogue, profile, now: now);
      final ids = ranked.map((p) => p.id).toList();

      // Electronics (bought) leads, then Sports (wishlisted)...
      expect(ids.indexOf(3), lessThan(ids.indexOf(5)));
      expect(ids.indexOf(3), lessThan(ids.indexOf(2)));
      // ...and everything uninterested keeps its original relative order behind.
      expect(ids.indexOf(1), lessThan(ids.indexOf(4)));
      expect(ranked.length, catalogue.length);
    });

    test('the strongest category leads, not just any match', () {
      final profile = _profile(
        signals: [
          (categoryId: 5, signal: InterestSignal.viewed),
          (categoryId: 1, signal: InterestSignal.purchased),
        ],
        now: now,
      );
      final ranked = rankByInterest(catalogue, profile, now: now);

      expect(ranked.first.categoryId, 1);
      // The other Electronics product is second; Sports follows it.
      expect(ranked[1].categoryId, 1);
      expect(ranked[2].categoryId, 5);
    });

    test('the same inputs always produce the same order', () {
      final profile = _profile(
        signals: [
          (categoryId: 1, signal: InterestSignal.purchased),
          (categoryId: 5, signal: InterestSignal.carted),
        ],
        now: now,
      );
      expect(
        rankByInterest(catalogue, profile, now: now).map((p) => p.id).toList(),
        rankByInterest(catalogue, profile, now: now).map((p) => p.id).toList(),
      );
    });

    test('a product with no category is never treated as a match', () {
      final profile = _profile(
        signals: [(categoryId: null, signal: InterestSignal.purchased)],
        now: now,
      );
      expect(rankByInterest(catalogue, profile, now: now), catalogue);
    });
  });

  group('interestCategoryIds', () {
    test('is empty for a guest and for a cold account', () {
      expect(interestCategoryIds(null, now), isEmpty);
      expect(interestCategoryIds(InterestProfile.empty, now), isEmpty);
    });

    test('lists the categories with evidence behind them', () {
      final profile = _profile(
        signals: [
          (categoryId: 1, signal: InterestSignal.purchased),
          (categoryId: 5, signal: InterestSignal.wishlisted),
        ],
        now: now,
      );
      expect(interestCategoryIds(profile, now), <int>{1, 5});
    });
  });

  group('new product notices', () {
    final catalogue = <Product>[
      _product(
        10,
        'Smart Watch Series 5',
        categoryId: 1,
        categoryName: 'Electronics',
        badges: const <String>['new'],
      ),
      _product(
        11,
        'Vitamin C Serum',
        categoryId: 4,
        categoryName: 'Beauty',
        badges: const <String>['new'],
      ),
      _product(
        12,
        'Ordinary Widget',
        categoryId: 1,
        categoryName: 'Electronics',
      ),
      _product(
        13,
        'Sold out phone',
        categoryId: 1,
        categoryName: 'Electronics',
        badges: const <String>['new'],
        stock: 0,
      ),
    ];

    test('a guest is told nothing', () {
      expect(
        newProductNotices(catalogue: catalogue, profile: null, now: now),
        isEmpty,
      );
    });

    test('an account with no signal is told nothing', () {
      expect(
        newProductNotices(
          catalogue: catalogue,
          profile: InterestProfile.empty,
          now: now,
        ),
        isEmpty,
      );
    });

    test('only new arrivals in the account\'s own categories are listed', () {
      final profile = _profile(
        signals: [(categoryId: 1, signal: InterestSignal.purchased)],
        now: now,
      );
      final notices = newProductNotices(
        catalogue: catalogue,
        profile: profile,
        now: now,
      );
      final ids = notices.map((n) => n.product.id).toSet();

      // The new Electronics watch qualifies.
      expect(ids, contains(10));
      // The new Beauty serum is not a category they buy from.
      expect(ids, isNot(contains(11)));
      // A plain existing product is not a "new arrival"...
      expect(ids, isNot(contains(12)));
      // ...and neither is something they cannot buy.
      expect(ids, isNot(contains(13)));
    });

    test('a product is not announced twice', () {
      final profile = _profile(
        signals: [(categoryId: 1, signal: InterestSignal.purchased)],
        now: now,
      ).markSeen(<int>[10]);

      final notices = newProductNotices(
        catalogue: catalogue,
        profile: profile,
        now: now,
      );
      expect(notices.map((n) => n.product.id), isNot(contains(10)));
    });

    test(
      'the category name falls back to the catalogue when the product has none',
      () {
        final profile = _profile(
          signals: [(categoryId: 1, signal: InterestSignal.purchased)],
          now: now,
        );
        final notices = newProductNotices(
          catalogue: <Product>[
            _product(
              20,
              'Unlabelled gadget',
              categoryId: 1,
              badges: const <String>['new'],
            ),
          ],
          profile: profile,
          now: now,
          categoryNames: <int, String>{1: 'Electronics'},
        );

        expect(notices.single.categoryName, 'Electronics');
        expect(notices.single.body, contains('Electronics'));
      },
    );

    test('the strongest matching category is listed first', () {
      final profile = _profile(
        signals: [
          (categoryId: 1, signal: InterestSignal.purchased),
          (categoryId: 4, signal: InterestSignal.carted),
        ],
        now: now,
      );
      final notices = newProductNotices(
        catalogue: catalogue,
        profile: profile,
        now: now,
      );

      expect(notices.first.product.id, 10);
      expect(notices.first.categoryName, 'Electronics');
    });
  });

  group('interest store', () {
    test('a guest cannot accumulate anything', () {
      const store = InterestStore.empty;
      final next = store.record(
        categoryId: 1,
        productId: 1,
        signal: InterestSignal.purchased,
      );

      expect(next.current, isNull);
      expect(identical(next, store), isTrue);
    });

    test('a signed-in account accumulates against its own id', () {
      const store = InterestStore(userId: 'buyer-1', profiles: {});
      final next = store.record(
        categoryId: 1,
        productId: 7,
        signal: InterestSignal.purchased,
      );

      expect(next.current!.scoreOf(1, DateTime(2026, 3, 1)), greaterThan(0));
      expect(next.profiles.keys, contains('buyer-1'));
    });

    test('markSeen is a no-op for a guest', () {
      const store = InterestStore.empty;
      expect(identical(store.markSeen(<int>[1, 2, 3]), store), isTrue);
    });

    test('a profile survives a round trip through storage', () {
      var store = const InterestStore(userId: 'buyer-1', profiles: {});
      store = store.record(
        categoryId: 4,
        productId: 11,
        signal: InterestSignal.wishlisted,
        now: DateTime(2026, 3, 1),
      );
      store = store.markSeen(<int>[11]);

      final restored = InterestStore.fromStorage(
        userId: 'buyer-1',
        raw: store.toStorage(),
      );

      final profile = restored.current!;
      expect(profile.categories.containsKey(4), isTrue);
      expect(profile.seenProductIds, contains(11));
      expect(
        profile.scoreOf(4, DateTime(2026, 3, 1)),
        closeTo(store.current!.scoreOf(4, DateTime(2026, 3, 1)), 0.0001),
      );
    });

    test('a corrupt entry is ignored instead of throwing', () {
      final restored = InterestStore.fromStorage(
        userId: 'buyer-1',
        raw: const <String, String>{'mvec.interests.buyer-1': 'not json'},
      );
      expect(restored.current!.categories, isEmpty);
    });

    test('unrelated storage keys are left alone', () {
      final restored = InterestStore.fromStorage(
        userId: 'buyer-1',
        raw: const <String, String>{'mvec.theme_mode': 'dark'},
      );
      expect(restored.profiles, isEmpty);
    });

    test('signing in as someone else does not inherit the first profile', () {
      var first = const InterestStore(userId: 'buyer-1', profiles: {});
      first = first.record(
        categoryId: 1,
        productId: 1,
        signal: InterestSignal.purchased,
      );

      // The account changes but the stored profiles stay put.
      final second = InterestStore(userId: 'buyer-2', profiles: first.profiles);

      expect(second.current!.categories, isEmpty);
      expect(second.profiles.length, 1);
    });
  });

  group('interest_category_ids helper', () {
    test('agrees with the ranked list', () {
      final profile = _profile(
        signals: [
          (categoryId: 1, signal: InterestSignal.purchased),
          (categoryId: 5, signal: InterestSignal.carted),
        ],
        now: now,
      );
      expect(
        interestCategoryIds(profile, now).toList(),
        profile.rankedCategoryIds(now),
      );
    });
  });

  // Guards the assumption the whole feature rests on: a product can be traced
  // back to the category it belongs to.
  group('catalogue category linkage', () {
    test('the model exposes a category id and a name', () {
      final category = Category.fromJson(const <String, dynamic>{
        'id': 3,
        'name': 'Sports',
        'slug': 'sports',
      });
      final product = _product(
        30,
        'Football',
        categoryId: category.id,
        categoryName: category.name,
      );

      expect(product.categoryId, category.id);
      expect(product.categoryName, 'Sports');
    });
  });
}
