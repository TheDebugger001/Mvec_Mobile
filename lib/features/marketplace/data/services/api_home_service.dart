import '../../../../core/api_client.dart';
import 'home_service.dart';

/// Reads the marketplace home feed from the marketplace backend.
///
/// The live route is `GET /api/search/home`, which answers
/// `{feed: {categories, featuredProducts, topVendors}}`. This service unwraps
/// that envelope and renames `topVendors` to the `featuredVendors` the feed
/// model reads, so a backend naming change cannot leave the storefront blank.
class ApiHomeService implements HomeService {
  ApiHomeService(this._api, {this.path = defaultPath});

  /// Path is relative to [kApiBaseUrl], which already carries the `/api`
  /// prefix. The home feed is served by the search controller, not at the root.
  static const String defaultPath = '/search/home';

  final ApiClient _api;
  final String path;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    final response = await _api.get(path);
    final body = switch (response) {
      final Map<dynamic, dynamic> map when map['data'] is Map =>
        Map<String, dynamic>.from(map['data'] as Map),
      final Map<dynamic, dynamic> map => Map<String, dynamic>.from(map),
      // A list or an unexpected scalar carries no feed; hand back an empty
      // payload so the screens render their empty state instead of throwing.
      _ => const <String, dynamic>{},
    };

    final feed = body['feed'];
    if (feed is Map) {
      final resolved = Map<String, dynamic>.from(feed);
      // The feed model reads `featuredVendors`; the backend sends `topVendors`.
      if (!resolved.containsKey('featuredVendors') && resolved['topVendors'] != null) {
        resolved['featuredVendors'] = resolved['topVendors'];
      }
      return resolved;
    }

    return body;
  }
}
