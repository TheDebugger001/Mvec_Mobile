import 'package:dio/dio.dart';

import '../../../../core/api_client.dart';
import 'api_home_service.dart';
import 'empty_home_service.dart';
import 'home_service.dart';

/// Prefers the live home feed and degrades to [EmptyHomeService] when the
/// endpoint cannot be reached.
///
/// Mirrors `FallbackAffiliateService` / `FallbackSupplierFinanceService`: the
/// first unreachable response pins the module to empty state for the rest of the
/// session, so a flaky request cannot split the home screen between two sources
/// and every rebuild stops re-probing a missing route.
class FallbackHomeService implements HomeService {
  FallbackHomeService(
    ApiClient api, {
    HomeService? fallback,
    String path = ApiHomeService.defaultPath,
  }) : _api = ApiHomeService(api, path: path),
       _fallback = fallback ?? EmptyHomeService();

  final ApiHomeService _api;
  final HomeService _fallback;
  bool _degraded = false;

  /// Human-readable reason for the last degradation, for the home screen notice.
  String? lastFallbackReason;

  @override
  bool get isDemo => false;

  @override
  Future<Map<String, dynamic>> getHomeFeed() async {
    if (_degraded) return _fallback.getHomeFeed();
    try {
      return await _api.getHomeFeed();
    } catch (error) {
      if (_isUnreachable(error)) {
        _degraded = true;
        lastFallbackReason =
            'The marketplace home feed is not available yet — showing an '
            'empty storefront.';
        return _fallback.getHomeFeed();
      }
      rethrow;
    }
  }

  /// Connection failures (`statusCode == null`) and "route not shipped"
  /// responses (404 / 501) degrade to empty. Genuine client/server errors on a
  /// live endpoint keep throwing so the screen can surface them.
  ///
  /// `ApiClient` rejects with a `DioException` whose `.error` carries the
  /// `ApiException`, so both shapes are unwrapped here.
  bool _isUnreachable(Object error) {
    if (error is ApiException) {
      return error.statusCode == null ||
          error.statusCode == 404 ||
          error.statusCode == 501;
    }
    if (error is DioException) {
      final nested = error.error;
      if (nested is ApiException) return _isUnreachable(nested);
      final code = error.response?.statusCode;
      return code == null || code == 404 || code == 501;
    }
    return false;
  }
}
