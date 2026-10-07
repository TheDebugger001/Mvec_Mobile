import '../../../../core/api_client.dart';
import 'home_service.dart';

/// Live marketplace home feed service.
class ApiHomeService implements HomeService {
  ApiHomeService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    final responses = await Future.wait([
      _api.get('/search/home'),
      _fetchAllProducts(),
    ]);
    final home = responses.first;
    if (home is Map) {
      final payload = Map<String, dynamic>.from(home);
      final feed = payload['feed'];
      if (feed is Map) {
        final data = Map<String, dynamic>.from(feed);
        return {
          ...data,
          'featuredVendors': data['featuredVendors'] ?? data['topVendors'],
          'products': responses[1] as List<dynamic>,
        };
      }
      return payload;
    }
    throw const FormatException('Home feed response was not an object');
  }

  Future<List<dynamic>> _fetchAllProducts() async {
    const pageSize = 200;
    final products = <dynamic>[];
    var page = 1;
    int? total;

    do {
      final response = await _api.get('/products', query: {
        'page': '$page',
        'limit': '$pageSize',
        'status': 'ACTIVE',
      });
      if (response is! Map || response['products'] is! List) {
        throw const FormatException('Product catalogue response was invalid');
      }
      final batch = response['products'] as List<dynamic>;
      products.addAll(batch);
      total = response['total'] is num
          ? (response['total'] as num).toInt()
          : products.length;
      page++;
      if (batch.isEmpty) break;
    } while (products.length < total);

    return products;
  }
}
