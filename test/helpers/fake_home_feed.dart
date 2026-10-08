import 'package:mvec_mobile/features/marketplace/data/services/home_service.dart';

/// A deterministic home feed for tests.
///
/// The app reads the storefront from the API, so a widget test that needs a
/// catalogue injects this instead of relying on a bundled dataset. It exists
/// only under `test/`: nothing in `lib/` ships these products.
class FakeHomeService implements HomeService {
  FakeHomeService({Map<String, dynamic>? payload, this.fails = false})
    : _payload = payload ?? defaultFeed();

  final Map<String, dynamic> _payload;

  /// When true the feed throws, so the error state can be exercised.
  final bool fails;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    if (fails) throw StateError('The home feed is unavailable');
    return _payload;
  }

  /// The feed every marketplace test renders against: three categories (so
  /// category-scoped rows and recommendation ordering are both exercised) and
  /// a catalogue that includes one discounted item, so the Deals tab is not
  /// empty, plus a new arrival in Electronics for the alert tests.
static Map<String, dynamic> defaultFeed() => <String, dynamic>{
    'banners': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'title': 'Fresh from Rwandan growers',
        'subtitle': 'Coffee, tea and spices, shipped nationwide',
        'image_url': '',
      },
    ],
    'categories': <Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'name': 'Electronics', 'slug': 'electronics'},
      <String, dynamic>{'id': 2, 'name': 'Fashion', 'slug': 'fashion'},
      <String, dynamic>{'id': 5, 'name': 'Sports', 'slug': 'sports'},
    ],
    'featuredVendors': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 11,
        'name': 'Kigali Electronics',
        'rating': 4.6,
        'totalProducts': 2,
      },
    ],
    'featuredProducts': <Map<String, dynamic>>[
      _product('9000', 'Wireless Over-Ear Headphones', 85000, 95000, 1,
          stock: 42),
    ],
    'recommendedProducts': <Map<String, dynamic>>[
      _product('9002', 'Running Shoes', 68000, 68000, 5),
      _product('9003', 'Cotton T-Shirt', 9000, 12000, 2),
    ],
    'products': <Map<String, dynamic>>[
      _product('9000', 'Wireless Over-Ear Headphones', 85000, 95000, 1,
          stock: 42),
      _product('9001', 'Wireless Earbuds', 45000, 52000, 1),
      _product('9002', 'Running Shoes', 68000, 68000, 5),
      _product('9003', 'Cotton T-Shirt', 9000, 12000, 2),
      _product('9004', 'Smart Watch Series 5', 120000, 120000, 1,
          badges: const <String>['new']),
      _product('9005', 'Football', 18000, 18000, 5),
    ],
    'recentlyViewed': <Map<String, dynamic>>[
      _product('9002', 'Running Shoes', 68000, 68000, 5),
    ],
  };

  static Map<String, dynamic> _product(
    String id,
    String name,
    num price,
    num oldPrice,
    int categoryId, {
    int stock = 12,
    List<String> badges = const <String>[],
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'description': '$name, supplied by a Rwandan seller.',
    'price': price,
    'originalPrice': oldPrice,
    'stockQuantity': stock,
    'category_id': categoryId,
    'isFeatured': false,
    'badges': badges,
    'vendor': <String, dynamic>{
      'id': 11,
      'name': 'Kigali Electronics',
      'rating': 4.6,
      'totalProducts': 2,
    },
  };
}