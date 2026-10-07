import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/features/marketplace/presentation/providers/home_provider.dart';

void main() {
  test('parses the backend nested home feed and MongoDB identifiers', () {
    final feed = HomeFeed.fromJson({
      'feed': {
        'categories': [
          {'_id': '65a1b2c3d4e5f67890123456', 'name': 'Produce'},
        ],
        'featuredProducts': [
          {
            '_id': '65b1b2c3d4e5f67890123456',
            'name': 'Mangoes',
            'price': 1200,
            'category': {'_id': '65a1b2c3d4e5f67890123456', 'name': 'Produce'},
            'vendor': {'_id': '65c1b2c3d4e5f67890123456'},
          },
        ],
        'topVendors': [
          {'_id': '65c1b2c3d4e5f67890123456', 'companyName': 'Fresh Market'},
        ],
      },
    });

    expect(feed.categories.single.id, isNot(0));
    expect(feed.products.single.apiId, '65b1b2c3d4e5f67890123456');
    expect(feed.products.single.id, isNot(0));
    expect(feed.products.single.categoryId, feed.categories.single.id);
    expect(feed.featuredVendors.single.name, 'Fresh Market');
    expect(feed.featuredVendors.single.id, isNot(0));
  });
}
