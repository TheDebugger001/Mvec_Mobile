/// Who works on a supplier's account, and what each of them is allowed to do.
///
/// The supplier owns the account but rarely runs it alone: someone packs the
/// orders, someone confirms deliveries, someone takes the payouts. This module
/// models that as a role per member plus a fixed permission set per role, so
/// the Team page can both manage the roster and show which operational areas
/// are covered by nobody.
library;

// Prefixed so the [TeamMember.initials] getter below can share its name with
// the shared helper rather than shadowing it.
import '../../../core/utils.dart' as utils;

/// One thing a staff member can be allowed to do on the supplier account.
///
/// Ordered from least to most sensitive so the coverage list reads as a ladder.
enum TeamPermission {
  viewDashboard,
  manageSupply,
  adjustStock,
  manageOrders,
  confirmDelivery,
  viewFinance,
  requestPayout,
  manageTeam;

  String get label => switch (this) {
    TeamPermission.viewDashboard => 'View dashboard',
    TeamPermission.manageSupply => 'Raise supply requests',
    TeamPermission.adjustStock => 'Adjust stock',
    TeamPermission.manageOrders => 'Manage vendor orders',
    TeamPermission.confirmDelivery => 'Confirm deliveries',
    TeamPermission.viewFinance => 'View earnings & reports',
    TeamPermission.requestPayout => 'Request payouts',
    TeamPermission.manageTeam => 'Manage the team',
  };

  String get description => switch (this) {
    TeamPermission.viewDashboard => 'See sales, stock and open orders.',
    TeamPermission.manageSupply => 'Create and cancel supply requests.',
    TeamPermission.adjustStock =>
      'Change quantities and prices in the catalogue.',
    TeamPermission.manageOrders => 'Move orders through packing and dispatch.',
    TeamPermission.confirmDelivery =>
      'Confirm delivery so escrow releases the money.',
    TeamPermission.viewFinance =>
      'See balances, transactions, analytics and reports.',
    TeamPermission.requestPayout =>
      'Move cleared earnings to a bank or wallet.',
    TeamPermission.manageTeam => 'Add, edit and remove staff on this account.',
  };

  String get slug => switch (this) {
    TeamPermission.viewDashboard => 'VIEW_DASHBOARD',
    TeamPermission.manageSupply => 'MANAGE_SUPPLY',
    TeamPermission.adjustStock => 'ADJUST_STOCK',
    TeamPermission.manageOrders => 'MANAGE_ORDERS',
    TeamPermission.confirmDelivery => 'CONFIRM_DELIVERY',
    TeamPermission.viewFinance => 'VIEW_FINANCE',
    TeamPermission.requestPayout => 'REQUEST_PAYOUT',
    TeamPermission.manageTeam => 'MANAGE_TEAM',
  };
}

/// A job on the supplier account. [permissions] is the whole grant — the app
/// stores the role and derives the rest, so widening a role later widens every
/// member who holds it.
enum TeamRole {
  owner,
  operations,
  warehouse,
  fulfilment,
  finance,
  viewer;

  String get slug => switch (this) {
    TeamRole.owner => 'OWNER',
    TeamRole.operations => 'OPERATIONS',
    TeamRole.warehouse => 'WAREHOUSE',
    TeamRole.fulfilment => 'FULFILMENT',
    TeamRole.finance => 'FINANCE',
    TeamRole.viewer => 'VIEWER',
  };

  String get label => switch (this) {
    TeamRole.owner => 'Owner',
    TeamRole.operations => 'Operations manager',
    TeamRole.warehouse => 'Warehouse',
    TeamRole.fulfilment => 'Fulfilment',
    TeamRole.finance => 'Finance',
    TeamRole.viewer => 'Viewer',
  };

  String get description => switch (this) {
    TeamRole.owner => 'Full control of the account, including the team.',
    TeamRole.operations =>
      'Runs the day to day: catalogue, stock and vendor orders.',
    TeamRole.warehouse => 'Receives stock in, counts it and keeps it accurate.',
    TeamRole.fulfilment =>
      'Packs and dispatches orders and confirms delivery on arrival.',
    TeamRole.finance =>
      'Watches earnings and takes the payouts once money is cleared.',
    TeamRole.viewer => 'Read-only access to the dashboard and orders.',
  };

  String get icon => switch (this) {
    TeamRole.owner => 'shield',
    TeamRole.operations => 'settings',
    TeamRole.warehouse => 'box',
    TeamRole.fulfilment => 'cart',
    TeamRole.finance => 'wallet',
    TeamRole.viewer => 'eye',
  };

  Set<TeamPermission> get permissions => switch (this) {
    TeamRole.owner => TeamPermission.values.toSet(),
    TeamRole.operations => {
      TeamPermission.viewDashboard,
      TeamPermission.manageSupply,
      TeamPermission.adjustStock,
      TeamPermission.manageOrders,
      TeamPermission.confirmDelivery,
      TeamPermission.viewFinance,
    },
    TeamRole.warehouse => {
      TeamPermission.viewDashboard,
      TeamPermission.adjustStock,
      TeamPermission.manageOrders,
    },
    TeamRole.fulfilment => {
      TeamPermission.viewDashboard,
      TeamPermission.manageOrders,
      TeamPermission.confirmDelivery,
    },
    TeamRole.finance => {
      TeamPermission.viewDashboard,
      TeamPermission.viewFinance,
      TeamPermission.requestPayout,
    },
    TeamRole.viewer => {TeamPermission.viewDashboard},
  };

  /// The owner cannot be edited or removed, so the account can never be left
  /// without someone who can manage the team.
  bool get isProtected => this == TeamRole.owner;

  static TeamRole parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll('-', '_');
    return switch (v) {
      'operations' || 'manager' || 'ops' => TeamRole.operations,
      'warehouse' || 'stock' => TeamRole.warehouse,
      'fulfilment' || 'fulfillment' || 'delivery' => TeamRole.fulfilment,
      'finance' || 'accountant' => TeamRole.finance,
      'viewer' || 'read_only' || 'readonly' => TeamRole.viewer,
      _ => TeamRole.viewer,
    };
  }
}

/// Reduces any reasonable way of writing a Rwandan number to its 9-digit local
/// form, or returns null when it is not one.
///
/// Accepts, and treats as the same number: `+250788000000`,
/// `+250 788 000 000`, `00250 788 000 000`, `0788000000` and `788000000`. A
/// Rwandan mobile number is nine digits starting with 7 — the two digits after
/// it pick the carrier, so `78`, `79`, `73`, `72` and the rest all pass. Written
/// in the local form it carries a leading zero, which is dropped here.
///
/// Lives here rather than in `core/utils.dart` so the add form's validator and
/// the service's own check cannot drift apart.
String? normalizeRwandanPhone(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  // Only strip the country code when what is left can still be a local number,
  // so a genuine number never starts with 250 by accident.
  if (digits.length > 9 && digits.startsWith('250')) {
    digits = digits.substring(3);
  }
  if (digits.length == 10 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits.length == 9 && digits.startsWith('7') ? digits : null;
}

/// The error to show for an unparseable number, or null when it is fine.
String? rwandanPhoneError(String? value) =>
    value == null || normalizeRwandanPhone(value) == null
        ? 'Enter a Rwandan number, e.g. +250 788 000 000'
        : null;

/// A Rwandan number in the app's display format, e.g. `+250 78 800 0000`.
String formatRwandanPhone(String value) {
  final local = normalizeRwandanPhone(value);
  if (local == null) return value.trim();
  return '+250 ${local.substring(0, 2)} '
      '${local.substring(2, 5)} ${local.substring(5)}';
}

/// The carrier behind a number, when it is one MVEC recognises. Used as helper
/// text so the supplier can see their entry was understood.
String? rwandanCarrier(String value) =>
    switch (normalizeRwandanPhone(value)?.substring(0, 2)) {
      '72' || '73' => 'Airtel',
      '78' || '79' => 'MTN',
      _ => null,
    };

/// Lifecycle of one staff record.
enum TeamMemberStatus {
  active,
  invited,
  suspended;

  String get slug => switch (this) {
    TeamMemberStatus.active => 'ACTIVE',
    TeamMemberStatus.invited => 'INVITED',
    TeamMemberStatus.suspended => 'SUSPENDED',
  };

  String get label => switch (this) {
    TeamMemberStatus.active => 'Active',
    TeamMemberStatus.invited => 'Invited',
    TeamMemberStatus.suspended => 'Suspended',
  };

  static TeamMemberStatus parse(String? raw) {
    final v = raw?.trim().toLowerCase();
    return switch (v) {
      'invited' || 'pending' => TeamMemberStatus.invited,
      'suspended' || 'disabled' => TeamMemberStatus.suspended,
      _ => TeamMemberStatus.active,
    };
  }
}

/// One person on the supplier's account.
class TeamMember {
  const TeamMember({
    required this.id,
    required this.fullName,
    required this.role,
    required this.phone,
    this.email,
    this.status = TeamMemberStatus.active,
    this.joinedAt,
    this.lastActiveAt,
    this.note,
  });

  final String id;
  final String fullName;
  final TeamRole role;
  final String phone;
  final String? email;
  final TeamMemberStatus status;
  final DateTime? joinedAt;
  final DateTime? lastActiveAt;
  final String? note;

  /// Avatar letters, e.g. `DI`.
  String get initials => utils.initials(fullName);

  bool get isOwner => role.isProtected;

  bool get isActive => status == TeamMemberStatus.active;

  /// Only an active member counts towards coverage — an invited or suspended
  /// person cannot actually run the operation.
  bool get countsTowardsCoverage => status == TeamMemberStatus.active;

  Set<TeamPermission> get permissions => role.permissions;

  TeamMember copyWith({
    String? fullName,
    TeamRole? role,
    String? phone,
    String? email,
    TeamMemberStatus? status,
    String? note,
  }) => TeamMember(
    id: id,
    fullName: fullName ?? this.fullName,
    role: role ?? this.role,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    status: status ?? this.status,
    joinedAt: joinedAt,
    lastActiveAt: lastActiveAt,
    note: note ?? this.note,
  );

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
    id: '${j['_id'] ?? j['id'] ?? ''}',
    fullName: '${j['fullName'] ?? j['name'] ?? 'Team member'}',
    role: TeamRole.parse('${j['role'] ?? ''}'),
    phone: '${j['phone'] ?? j['phoneNumber'] ?? ''}',
    email: j['email'] == null ? null : '${j['email']}',
    status: TeamMemberStatus.parse('${j['status'] ?? ''}'),
    joinedAt: _date(j['joinedAt'] ?? j['createdAt']),
    lastActiveAt: _date(j['lastActiveAt'] ?? j['lastSeenAt']),
    note: j['note'] == null ? null : '${j['note']}',
  );
}

/// Whether one permission is handled by at least one active member.
class TeamPermissionCoverage {
  const TeamPermissionCoverage({
    required this.permission,
    required this.holders,
  });

  final TeamPermission permission;

  /// Active members who hold it.
  final List<TeamMember> holders;

  bool get isCovered => holders.isNotEmpty;

  /// Role labels of the holders, for the tooltip on the coverage chip.
  String get holderSummary =>
      holders.isEmpty
          ? 'Nobody on the account can do this'
          : holders.map((m) => m.fullName).join(', ');
}

/// Counts for the Team page header, plus the per-permission coverage.
class TeamSummary {
  const TeamSummary({
    this.total = 0,
    this.active = 0,
    this.invited = 0,
    this.suspended = 0,
    this.byRole = const <TeamRole, int>{},
    this.coverage = const <TeamPermissionCoverage>[],
  });

  final int total;
  final int active;
  final int invited;
  final int suspended;
  final Map<TeamRole, int> byRole;
  final List<TeamPermissionCoverage> coverage;

  /// Operational areas nobody on the account can currently handle.
  List<TeamPermissionCoverage> get gaps =>
      coverage.where((c) => !c.isCovered).toList();

  double get coveredShare =>
      coverage.isEmpty ? 0 : (coverage.length - gaps.length) / coverage.length;

  int countFor(TeamRole role) => byRole[role] ?? 0;

  factory TeamSummary.fromMembers(List<TeamMember> members) {
    final activeMembers =
        members.where((m) => m.countsTowardsCoverage).toList();
    final byRole = <TeamRole, int>{};
    for (final member in members) {
      byRole[member.role] = (byRole[member.role] ?? 0) + 1;
    }
    return TeamSummary(
      total: members.length,
      active: members.where((m) => m.status == TeamMemberStatus.active).length,
      invited:
          members.where((m) => m.status == TeamMemberStatus.invited).length,
      suspended:
          members.where((m) => m.status == TeamMemberStatus.suspended).length,
      byRole: byRole,
      coverage: [
        for (final permission in TeamPermission.values)
          TeamPermissionCoverage(
            permission: permission,
            holders:
                activeMembers
                    .where((m) => m.permissions.contains(permission))
                    .toList(),
          ),
      ],
    );
  }
}

DateTime? _date(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
