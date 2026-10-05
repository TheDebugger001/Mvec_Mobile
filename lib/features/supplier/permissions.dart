import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import 'models/supplier_team.dart';

/// What the signed-in login is allowed to do on this supplier account.
///
/// Everything here is derived from what the API already put in the token — the
/// login's `staffRole`, and the `permissions` array when the API sends one. It
/// exists to keep the UI honest about who can do what.
///
/// **It is not a security control.** Anything hidden here can still be reached
/// by calling the endpoint directly, so every `/suppliers/me/*` route has to
/// re-check the caller's permissions server-side. Treat this as the difference
/// between a button that is there and a request that is allowed.
final currentSupplierRoleProvider = Provider<TeamRole?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  // Only supplier logins have a role on a supplier account.
  if (user.userType != 'supplier') return null;
  // An invited login has not accepted yet, so it has nothing. This is what
  // keeps a half-finished signup from reaching the portal at all.
  if (user.isPendingInvite) return null;

  // Holding the account *is* the owner. Owner rights are implied, never carried
  // by a role value.
  if (user.isAccountOwner) return TeamRole.owner;

  // `TeamRole.parse` deliberately has no case for `owner`, so a token claiming
  // `staffRole: OWNER` lands on the least privileged role rather than the most.
  // A self-promotion bug therefore loses access instead of gaining the account.
  return TeamRole.parse(user.staffRole);
});

/// The permissions this login may exercise, narrowed further when the API sent
/// an explicit list.
final supplierPermissionsProvider = Provider<Set<TeamPermission>>((ref) {
  final role = ref.watch(currentSupplierRoleProvider);
  if (role == null) return const {};

  final granted = role.permissions;
  final user = ref.watch(currentUserProvider);
  // An empty list means the API did not send the field, not that it granted
  // nothing — so only narrow the role when a list actually arrived.
  if (user == null || user.permissions.isEmpty) return granted;

  final slugs = user.permissions.map((p) => p.toUpperCase()).toSet();
  return granted.where((permission) => slugs.contains(permission.slug)).toSet();
});

/// Whether this login may [permission]. Watch from a button to enable, disable
/// or hide it.
final canDoProvider = Provider.family<bool, TeamPermission>(
  (ref, permission) =>
      ref.watch(supplierPermissionsProvider).contains(permission),
);

/// Whether this login can manage the roster. Gates every write on the Team page.
final canManageTeamProvider = Provider<bool>(
  (ref) => ref.watch(canDoProvider(TeamPermission.manageTeam)),
);

/// Whether this login may see earnings and move money, which is what the
/// Finance & Insights pages both need.
final canViewFinanceProvider = Provider<bool>(
  (ref) => ref.watch(canDoProvider(TeamPermission.viewFinance)),
);
