import '../../../core/api_client.dart';
import '../models/supplier_team.dart';
import 'supplier_team_service.dart';

/// Empty-state implementation of [SupplierTeamService].
///
/// The bundled roster this used to serve is gone, so the Team & Staff page now
/// resolves to an empty account: no members and a [TeamSummary] with every
/// counter at zero. The page renders its "no staff yet" state while
/// `/suppliers/me/team` is being connected.
///
/// Writes throw an [ApiException] — inviting or removing staff cannot be
/// acknowledged locally, so the forms have to report the failure.
class EmptySupplierTeamService implements SupplierTeamService {
  EmptySupplierTeamService({this.delay = Duration.zero});

  final Duration delay;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  Future<T> _latency<T>(T value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return value;
  }

  @override
  Future<List<TeamMember>> members() => _latency(const <TeamMember>[]);

  @override
  Future<TeamSummary> summary() => _latency(const TeamSummary());

  Never _writeUnsupported(String what) => throw ApiException(
    '$what is not available yet — this endpoint has not shipped.',
    statusCode: 501,
  );

  @override
  Future<TeamMember> addMember({
    required String fullName,
    required String phone,
    required TeamRole role,
    String? email,
    String? note,
  }) => _writeUnsupported('Staff accounts');

  @override
  Future<TeamMember> updateMember(
    String id, {
    String? fullName,
    String? phone,
    TeamRole? role,
    TeamMemberStatus? status,
    String? email,
    String? note,
  }) => _writeUnsupported('Staff accounts');

  @override
  Future<void> removeMember(String id) =>
      _writeUnsupported('Staff accounts');
}
