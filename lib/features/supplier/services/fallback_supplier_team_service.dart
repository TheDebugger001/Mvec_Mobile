import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../models/supplier_team.dart';
import 'empty_supplier_team_service.dart';
import 'supplier_team_service.dart';

/// Runs every [SupplierTeamService] call against the live API and degrades to
/// [EmptySupplierTeamService] when the route does not exist yet.
///
/// Same sticky-session contract as `FallbackSupplierFinanceService`: the first
/// unreachable response degrades the module for the rest of the session, so the
/// Team page shows its empty roster instead of erroring on every rebuild.
class FallbackSupplierTeamService implements SupplierTeamService {
  FallbackSupplierTeamService(
    ApiClient api, {
    SupplierTeamService? fallback,
    bool? forceEmpty,
  }) : _api = ApiSupplierTeamService(api),
       _fallback = fallback ?? EmptySupplierTeamService(),
       _forceEmpty = forceEmpty ?? false {
    if (_forceEmpty) {
      _degraded = true;
      lastFallbackReason =
          'Supplier staff accounts are not available yet — showing an empty roster.';
    }
  }

  final ApiSupplierTeamService _api;
  final SupplierTeamService _fallback;
  final bool _forceEmpty;
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
            'MVEC does not serve supplier $source yet — showing an empty '
            'roster until it does.';
        return call(_fallback);
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
