import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../../../core/api_config.dart';
import '../models/supplier_team.dart';
import 'mock_supplier_team_service.dart';
import 'supplier_team_service.dart';

/// Prefer the live supplier API and surface a real error instead of shipping demo
/// content to the app.
class FallbackSupplierTeamService implements SupplierTeamService {
  FallbackSupplierTeamService(
    ApiClient api, {
    SupplierTeamService? fallback,
    bool? forceDemo,
  }) : _api = ApiSupplierTeamService(api),
       _fallback = fallback ?? MockSupplierTeamService(),
       _forceDemo = forceDemo ?? kDemoMode {
    if (_forceDemo) {
      _degraded = true;
      lastFallbackReason = 'Demo mode — using the bundled supplier roster.';
    }
  }

  final ApiSupplierTeamService _api;
  final SupplierTeamService _fallback;
  final bool _forceDemo;
  bool _degraded = false;
  String? lastFallbackReason;

  @override
  bool get isDemo => _degraded && _fallback.isDemo;

  @override
  String? get fallbackReason => lastFallbackReason;

  @override
  Future<List<TeamMember>> members() =>
      _resolve((s) => s.members(), source: 'staff accounts');

  @override
  Future<TeamSummary> summary() =>
      _resolve((s) => s.summary(), source: 'staff accounts');

  @override
  Future<TeamMember> addMember({
    required String fullName,
    required String phone,
    required TeamRole role,
    String? email,
    String? note,
  }) => _resolve(
    (s) => s.addMember(
      fullName: fullName,
      phone: phone,
      role: role,
      email: email,
      note: note,
    ),
    source: 'staff accounts',
  );

  @override
  Future<TeamMember> updateMember(
    String id, {
    String? fullName,
    String? phone,
    TeamRole? role,
    TeamMemberStatus? status,
    String? email,
    String? note,
  }) => _resolve(
    (s) => s.updateMember(
      id,
      fullName: fullName,
      phone: phone,
      role: role,
      status: status,
      email: email,
      note: note,
    ),
    source: 'staff accounts',
  );

  @override
  Future<void> removeMember(String id) =>
      _resolve((s) => s.removeMember(id), source: 'staff accounts');

  Future<T> _resolve<T>(
    Future<T> Function(SupplierTeamService service) call, {
    required String source,
  }) async {
    if (_degraded) return call(_fallback);
    try {
      return await call(_api);
    } catch (error) {
      if (_isUnreachable(error)) {
        _degraded = true;
        lastFallbackReason =
            'MVEC does not serve supplier $source yet — the app cannot show demo data.';
        rethrow;
      }
      rethrow;
    }
  }

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
