import '../../../core/api_client.dart';
import '../models/supplier_team.dart';

/// Contract for the staff roster on a supplier account.
///
/// [MockSupplierTeamService] and [ApiSupplierTeamService] are interchangeable;
/// see `supplier_dependencies.dart` for the switch. Writes are token-scoped
/// (`/me/team/*`) so the app never sends a supplier id.
abstract class SupplierTeamService {
  bool get isDemo;

  /// Why the bundled dataset is being served instead of the API, when that is
  /// the case. Null while the live API is answering.
  String? get fallbackReason;

  /// Everyone on the account, owners first.
  Future<List<TeamMember>> members();

  /// Counters and per-permission coverage, derived from the same roster.
  Future<TeamSummary> summary();

  /// Adds a staff member.
  ///
  /// Throws when [fullName] or [phone] is blank, the phone number is malformed
  /// for Rwanda, or [role] is [TeamRole.owner] — the account already has one.
  Future<TeamMember> addMember({
    required String fullName,
    required String phone,
    required TeamRole role,
    String? email,
    String? note,
  });

  /// Changes an existing member. Throws on the owner or on an unknown id.
  Future<TeamMember> updateMember(
    String id, {
    String? fullName,
    String? phone,
    TeamRole? role,
    TeamMemberStatus? status,
    String? email,
    String? note,
  });

  /// Removes a member. Throws on the owner, or when it would leave the account
  /// without anyone who can manage the team.
  Future<void> removeMember(String id);
}

/// Talks to the platform's supplier team API.
///
/// The route is not served by the backend yet, so
/// `FallbackSupplierTeamService` takes over from the bundled roster rather than
/// leaving the page blank.
class ApiSupplierTeamService implements SupplierTeamService {
  ApiSupplierTeamService(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  String? get fallbackReason => null;

  @override
  Future<List<TeamMember>> members() async {
    final res = await _api.get('/suppliers/me/team');
    return listJson(res, [
      'members',
      'team',
      'data',
    ]).map(TeamMember.fromJson).toList();
  }

  @override
  Future<TeamSummary> summary() async {
    final res = await _api.get('/suppliers/me/team/summary');
    final json = singleJson(res, ['summary', 'team', 'data']);
    final rows = listJson(res, ['members', 'team']);
    // Prefer the server's own counts, but fall back to deriving them from the
    // roster when only one of the two is present.
    return rows.isEmpty
        ? TeamSummary(
          total: _int(json['total']),
          active: _int(json['active']),
          invited: _int(json['invited']),
          suspended: _int(json['suspended']),
        )
        : TeamSummary.fromMembers(rows.map(TeamMember.fromJson).toList());
  }

  @override
  Future<TeamMember> addMember({
    required String fullName,
    required String phone,
    required TeamRole role,
    String? email,
    String? note,
  }) async {
    final res = await _api.post(
      '/suppliers/me/team',
      body: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'role': role.slug,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return TeamMember.fromJson(singleJson(res, ['member']));
  }

  @override
  Future<TeamMember> updateMember(
    String id, {
    String? fullName,
    String? phone,
    TeamRole? role,
    TeamMemberStatus? status,
    String? email,
    String? note,
  }) async {
    final res = await _api.patch(
      '/suppliers/me/team/$id',
      body: {
        if (fullName != null) 'fullName': fullName.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (role != null) 'role': role.slug,
        if (status != null) 'status': status.slug,
        if (email != null) 'email': email.trim(),
        if (note != null) 'note': note.trim(),
      },
    );
    return TeamMember.fromJson(singleJson(res, ['member']));
  }

  @override
  Future<void> removeMember(String id) => _api.delete('/suppliers/me/team/$id');
}

int _int(dynamic value) => value is num ? value.toInt() : 0;
