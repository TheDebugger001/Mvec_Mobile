import '../../../core/api_client.dart';
import '../models/supplier_team.dart';
import 'supplier_team_service.dart';

/// Local demo implementation of [SupplierTeamService] for the supplier Team &
/// Staff page.
///
/// The roster is seeded so every operational area of the account is covered at
/// least once, apart from payouts-on-behalf: the demo deliberately leaves
/// [TeamPermission.requestPayout] to the owner alone so the coverage panel has
/// a real gap to point at rather than a wall of green.
class MockSupplierTeamService implements SupplierTeamService {
  MockSupplierTeamService({this.delay = const Duration(milliseconds: 550)});

  final Duration delay;

  late final List<TeamMember> _members = _seedMembers();

  /// Derived from the roster length so ids stay unique as people are added.
  int get _nextId => 7 + _members.length;

  @override
  bool get isDemo => true;

  @override
  String? get fallbackReason => null;

  Future<void> _latency() => Future<void>.delayed(delay);

  @override
  Future<List<TeamMember>> members() async {
    await _latency();
    return [..._members];
  }

  @override
  Future<TeamSummary> summary() async {
    await _latency();
    return TeamSummary.fromMembers([..._members]);
  }

  @override
  Future<TeamMember> addMember({
    required String fullName,
    required String phone,
    required TeamRole role,
    String? email,
    String? note,
  }) async {
    final name = fullName.trim();
    if (name.isEmpty) throw ApiException('Enter the team member’s name');
    final local = normalizeRwandanPhone(phone);
    if (local == null) {
      throw ApiException('Enter a Rwandan number, e.g. +250 788 000 000');
    }
    if (_members.any((m) => normalizeRwandanPhone(m.phone) == local)) {
      throw ApiException('That number is already on this account');
    }
    if (role.isProtected) {
      throw ApiException('This account already has an owner');
    }

    await _latency();
    final now = DateTime.now();
    final member = TeamMember(
      id: 'sup-team-$_nextId',
      fullName: name,
      role: role,
      phone: formatRwandanPhone(phone),
      email: _clean(email),
      status: TeamMemberStatus.invited,
      joinedAt: now,
      note: _clean(note),
    );
    _members.add(member);
    return member;
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
    final index = _members.indexWhere((m) => m.id == id);
    if (index < 0) throw ApiException('That team member no longer exists');

    final existing = _members[index];
    if (existing.isOwner) {
      throw ApiException(
        'The account owner cannot be changed — transfer ownership from '
        'Settings instead',
      );
    }
    final name = fullName?.trim();
    if (name != null && name.isEmpty) {
      throw ApiException('Enter the team member’s name');
    }
    if (phone != null) {
      final local = normalizeRwandanPhone(phone);
      if (local == null) {
        throw ApiException('Enter a Rwandan number, e.g. +250 788 000 000');
      }
      final clash = _members.any(
        (m) => m.id != id && normalizeRwandanPhone(m.phone) == local,
      );
      if (clash) throw ApiException('That number is already on this account');
    }
    if (role?.isProtected ?? false) {
      throw ApiException('Ownership cannot be assigned from the team page');
    }
    if (status == TeamMemberStatus.active &&
        existing.status == TeamMemberStatus.suspended) {
      throw ApiException(
        '${existing.fullName} accepted the invite — their status updates '
        'itself once they sign in',
      );
    }

    await _latency();
    final updated = existing.copyWith(
      fullName: name,
      role: role,
      phone: phone == null ? null : formatRwandanPhone(phone),
      email: email == null ? null : _clean(email),
      status: status,
      note: note == null ? null : _clean(note),
    );
    _members[index] = updated;
    return updated;
  }

  @override
  Future<void> removeMember(String id) async {
    final index = _members.indexWhere((m) => m.id == id);
    if (index < 0) throw ApiException('That team member no longer exists');

    final existing = _members[index];
    if (existing.isOwner) {
      throw ApiException('The account owner cannot be removed');
    }

    await _latency();
    _members.removeAt(index);
  }

  // ── demo dataset ─────────────────────────────────────────────────────────

  static DateTime _ago(int days) =>
      DateTime.now().subtract(Duration(days: days));

  static String? _clean(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  List<TeamMember> _seedMembers() => [
    TeamMember(
      id: 'sup-team-1',
      fullName: 'Divine Ingabire',
      role: TeamRole.owner,
      phone: '+250 788 245 610',
      email: 'divine@freshbasket.rw',
      joinedAt: _ago(420),
      lastActiveAt: _ago(0),
      note: 'Account owner — signs off on payouts.',
    ),
    TeamMember(
      id: 'sup-team-2',
      fullName: 'Aline Umutoni',
      role: TeamRole.operations,
      phone: '+250 788 512 044',
      email: 'aline@freshbasket.rw',
      joinedAt: _ago(210),
      lastActiveAt: _ago(1),
      note: 'Runs the daily order and catalogue checks.',
    ),
    TeamMember(
      id: 'sup-team-3',
      fullName: 'Eric Nshimiyimana',
      role: TeamRole.warehouse,
      phone: '+250 782 330 176',
      joinedAt: _ago(180),
      lastActiveAt: _ago(0),
    ),
    TeamMember(
      id: 'sup-team-4',
      fullName: 'Sandrine Mukamana',
      role: TeamRole.fulfilment,
      phone: '+250 785 904 233',
      joinedAt: _ago(150),
      lastActiveAt: _ago(2),
      note: 'Confirms delivery so escrow releases.',
    ),
    TeamMember(
      id: 'sup-team-5',
      fullName: 'Olivier Twagiramungu',
      role: TeamRole.viewer,
      phone: '+250 733 118 902',
      status: TeamMemberStatus.invited,
      joinedAt: _ago(2),
      note: 'Invited by Divine — has not signed in yet.',
    ),
    TeamMember(
      id: 'sup-team-6',
      fullName: 'Clarisse Uwase',
      role: TeamRole.warehouse,
      phone: '+250 789 447 015',
      status: TeamMemberStatus.suspended,
      joinedAt: _ago(300),
      lastActiveAt: _ago(64),
      note: 'Paused while on leave.',
    ),
  ];
}
