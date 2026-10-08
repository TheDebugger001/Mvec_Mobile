import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';

/// Admin intelligence reads, kept apart from [PlatformService] on purpose.
///
/// These routes belong to one feature area — the admin overview surfaces — so
/// they live in their own service and their own provider file rather than in
/// the shared `platform_service.dart` / `admin_providers.dart`. That keeps two
/// teams editing different admin features out of each other's way.
///
/// The backend does not serve these routes yet. Each read therefore degrades to
/// an empty list on an unreachable or "not implemented" response, so a table
/// renders its empty state instead of an error screen. Populate them as the
/// routes land — the screens already handle empty.
class AdminIntelligenceService {
  AdminIntelligenceService(this._api);

  final ApiClient _api;

  factory AdminIntelligenceService.fromClient() =>
      AdminIntelligenceService(ApiClient.instance);

  Future<List<Map<String, dynamic>>> auditLogs({int page = 1, int limit = 50}) =>
      _listOrEmpty('/audit-logs', ['data', 'logs', 'auditLogs'], page: page, limit: limit);

  Future<List<Map<String, dynamic>>> supplierMatches({int page = 1, int limit = 50}) =>
      _listOrEmpty('/supplier-matches', ['data', 'matches'], page: page, limit: limit);

  Future<List<Map<String, dynamic>>> trustScores({int page = 1, int limit = 50}) =>
      _listOrEmpty('/trust-scores', ['data', 'scores', 'parties'], page: page, limit: limit);

  Future<List<Map<String, dynamic>>> systemSettings() =>
      _listOrEmpty('/system/settings', ['data', 'settings']);

  /// Recommendation signals power the marketplace's personalised feed. The list
  /// degrades to empty while the route is unshipped; the toggle write is a normal
  /// request and surfaces the server's error if the route is missing.
  Future<List<Map<String, dynamic>>> recommendationSignals() =>
      _listOrEmpty('/recommendation-signals', ['data', 'signals']);

  Future<void> patchRecommendationSignal(String id, {required bool enabled}) async {
    await _api.patch('/recommendation-signals/$id', body: {'enabled': enabled});
  }

  /// Reads a list route, degrading to an empty list when it is unreachable or
  /// not implemented yet — an unshipped admin route should leave its table in
  /// the empty state, not on an error screen.
  Future<List<Map<String, dynamic>>> _listOrEmpty(
    String path,
    List<String> keys, {
    int? page,
    int? limit,
  }) async {
    try {
      final res = await _api.get(
        path,
        query: {
          if (page != null) 'page': page,
          if (limit != null) 'limit': limit,
        },
      );
      return listJson(res, keys);
    } on ApiException catch (e) {
      if (e.statusCode == null || e.statusCode == 404 || e.statusCode == 501) {
        return const [];
      }
      rethrow;
    }
  }
}

final adminIntelligenceServiceProvider = Provider<AdminIntelligenceService>(
  (ref) => AdminIntelligenceService.fromClient(),
);