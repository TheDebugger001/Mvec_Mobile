import '../../../../core/api_client.dart';
import 'home_service.dart';

/// Reads the marketplace home feed from the marketplace backend.
///
/// The response is normalised down to the flat map `HomeFeed.fromJson` expects
/// (`banners`, `categories`, `featuredVendors`, `featuredProducts`,
/// `recommendedProducts`, `products`, `recentlyViewed`). Both a bare object and
/// the `{ data: {...} }` envelope the rest of the API returns are accepted, and
/// any key the backend omits simply stays absent so it parses as an empty list.
class ApiHomeService implements HomeService {
  ApiHomeService(this._api, {this.path = defaultPath});

  /// Path is relative to [kApiBaseUrl], which already carries the `/api`
  /// prefix — this is the single place to change once the backend confirms the
  /// home-feed route.
  static const String defaultPath = '/home';

  final ApiClient _api;
  final String path;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    final response = await _api.get(path);
    return switch (response) {
      final Map<dynamic, dynamic> map when map['data'] is Map =>
        Map<String, dynamic>.from(map['data'] as Map),
      final Map<dynamic, dynamic> map => Map<String, dynamic>.from(map),
      // A list or an unexpected scalar carries no feed; hand back an empty
      // payload so the screens render their empty state instead of throwing.
      _ => const <String, dynamic>{},
    };
  }
}
