import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/core/json_fields.dart';
import 'package:mvec_mobile/features/marketplace/data/models/category_model.dart';
import 'package:mvec_mobile/features/marketplace/data/models/product_model.dart';
import 'package:mvec_mobile/features/marketplace/data/models/vendor_model.dart';
import 'package:mvec_mobile/features/marketplace/presentation/providers/home_provider.dart';

void main() {
  group('json field resolution', () {
    test('prefers the first name that is present', () {
      final json = {'score': 10, 'trust_score': 20};
      expect(field(json, ['score', 'trustScore']), 10);
      expect(field(json, ['missing', 'score']), 10);
    });

    test('falls through a null to a later alias', () {
      expect(stringField({'name': 'a'}, ['party', 'name']), 'a');
    });

    test('treats an empty string as absent rather than blank content', () {
      expect(stringField({'party': '', 'name': 'Ada'}, ['party', 'name']), 'Ada');
    });

    test('reads numbers that arrive as strings', () {
      expect(numField({'weight': '42'}, ['weight']), 42);
      expect(intField({'score': '87'}, ['score']), 87);
    });

    test('normalises the boolean spellings a backend may send', () {
      for (final raw in <dynamic>[true, 1, 'true', 'TRUE', 'yes']) {
        expect(boolField({'enabled': raw}, ['enabled']), isTrue, reason: '$raw');
      }
      for (final raw in <dynamic>[false, 0, 'false', null, 'no']) {
        expect(boolField({'enabled': raw}, ['enabled']), isFalse, reason: '$raw');
      }
    });

    test('generates the snake_case alias for a camelCase name', () {
      expect(spellings('refundRate'), ['refundRate', 'refund_rate']);
      expect(spellings('id'), ['id', 'id']);
    });
  });

  group('HomeFeed', () {
    test('reads the camelCase feed', () {
      final feed = HomeFeed.fromJson({
        'banners': [
          {'id': 1, 'title': 'Sale', 'image_url': 'a.png'},
        ],
        'categories': [
          {'id': 2, 'name': 'Tools', 'product_count': 4},
        ],
        'featuredVendors': [
          {'id': 3, 'name': 'Acme'},
        ],
        'featuredProducts': [
          {'id': 4, 'title': 'Hammer'},
        ],
        'recommendedProducts': [
          {'id': 5, 'title': 'Saw'},
        ],
        'products': [
          {'id': 6, 'title': 'Drill'},
        ],
        'recentlyViewed': [
          {'id': 7, 'title': 'Level'},
        ],
      });

      expect(feed.banners.single.title, 'Sale');
      expect(feed.categories.single.name, 'Tools');
      expect(feed.categories.single.productCount, 4);
      expect(feed.featuredVendors.single.name, 'Acme');
      expect(feed.featuredProducts.single.name, 'Hammer');
      expect(feed.recommendedProducts.single.name, 'Saw');
      expect(feed.products.single.name, 'Drill');
      expect(feed.recentlyViewed.single.name, 'Level');
    });

    test('reads the snake_case feed a Node backend sends', () {
      final feed = HomeFeed.fromJson({
        'featured_vendors': [
          {'id': 3, 'name': 'Acme'},
        ],
        'featured_products': [
          {'id': 4, 'title': 'Hammer'},
        ],
        'recommended_products': [
          {'id': 5, 'title': 'Saw'},
        ],
        'recently_viewed': [
          {'id': 7, 'title': 'Level'},
        ],
      });

      expect(feed.featuredVendors, hasLength(1));
      expect(feed.featuredProducts, hasLength(1));
      expect(feed.recommendedProducts, hasLength(1));
      expect(feed.recentlyViewed, hasLength(1));
    });

    test('unwraps a data envelope', () {
      final feed = HomeFeed.fromJson({
        'data': {
          'featured_products': [
            {'id': 4, 'title': 'Hammer'},
          ],
        },
      });

      expect(feed.featuredProducts.single.name, 'Hammer');
    });

    test('stays empty rather than throwing on an unrelated payload', () {
      final feed = HomeFeed.fromJson({'message': 'no access'});

      expect(feed.banners, isEmpty);
      expect(feed.featuredVendors, isEmpty);
      expect(feed.products, isEmpty);
    });
  });

  group('marketplace models accept either casing', () {
    test('vendor flags', () {
      expect(
        Vendor.fromJson({'id': 1, 'is_verified': true}).isVerified,
        isTrue,
      );
      expect(
        Vendor.fromJson({'id': 1, 'is_featured': true}).isFeatured,
        isTrue,
      );
      expect(Vendor.fromJson({'id': 1, 'verified': true}).isVerified, isTrue);
    });

    test('product stock, counts and flags', () {
      final product = Product.fromJson({
        'id': 1,
        'title': 'Hammer',
        'stock': 12,
        'rating_count': 9,
        'is_featured': true,
      });

      expect(product.stockQuantity, 12);
      expect(product.ratingCount, 9);
      expect(product.isFeatured, isTrue);
      expect(Product.fromJson({'id': 1, 'stock_quantity': 3}).stockQuantity, 3);
    });

    test('a price reduction still implies a sale', () {
      final product = Product.fromJson({
        'id': 1,
        'title': 'Hammer',
        'originalPrice': 20,
        'salePrice': 15,
      });

      expect(product.isOnSale, isTrue);
    });
  });

  group('the real backend document shapes', () {
    // Taken from the Mongoose models in Mvec_backend/src/models. Each of these
    // is a field the app read under a different name, which rendered the
    // storefront blank while every request still succeeded.
    test('Vendor: businessName, logoUrl, ratingAvg, verificationStatus', () {
      final vendor = Vendor.fromJson({
        'publicId': 7,
        'businessName': 'Kampala Hardware',
        'slug': 'kampala-hardware',
        'logoUrl': '/uploads/logo.png',
        'bannerUrl': '/uploads/banner.png',
        'ratingAvg': 4.5,
        'verificationStatus': 'VERIFIED',
      });

      expect(vendor.id, 7);
      expect(vendor.name, 'Kampala Hardware');
      expect(vendor.logoUrl, '/uploads/logo.png');
      expect(vendor.bannerUrl, '/uploads/banner.png');
      expect(vendor.rating, 4.5);
      expect(vendor.isVerified, isTrue);
    });

    test('Category: imageUrl', () {
      final category = Category.fromJson({'id': 3, 'name': 'Tools', 'imageUrl': '/c.png'});
      expect(category.imageUrl, '/c.png');
    });

    test('Product: discountPrice becomes the price you pay', () {
      final product = Product.fromJson({
        'publicId': 11,
        'name': 'Claw Hammer',
        'price': 20000,
        'discountPrice': 15000,
        'stockQuantity': 4,
        'media': {'mainImage': '/uploads/hammer.png'},
      });

      expect(product.id, 11);
      expect(product.name, 'Claw Hammer');
      expect(product.price, 15000);
      expect(product.originalPrice, 20000);
      expect(product.discountPercent, 25);
      expect(product.isOnSale, isTrue);
      expect(product.imageUrl, '/uploads/hammer.png');
    });

    test('Product: an undiscounted row keeps price as the current price', () {
      final product = Product.fromJson({'id': 12, 'name': 'Saw', 'price': 8000});

      expect(product.price, 8000);
      expect(product.originalPrice, isNull);
      expect(product.discountPercent, 0);
    });

    test('Product: a discountPrice above price is not a sale', () {
      final product = Product.fromJson({
        'id': 13,
        'name': 'Level',
        'price': 5000,
        'discountPrice': 9000,
      });

      expect(product.price, 5000);
      expect(product.originalPrice, isNull);
      expect(product.isOnSale, isFalse);
    });
  });
}
