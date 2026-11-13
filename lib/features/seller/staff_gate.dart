import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/nav_items.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

/// Shown for a staff role that may not use the dashboard section.
class StaffGate extends ConsumerWidget {
  const StaffGate({super.key, required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((a) => a.user));
    if (staffCan(user, path)) return child;
    return EmptyState(
      icon: Icons.shield_outlined,
      title: "You don't have access to this page",
      message: "Your role (${staffRoleLabel[user?.staffRole] ?? 'Staff'}) doesn't include it. Ask the store owner if you need access.",
      action: OutlineBtn(label: 'Back to dashboard', compact: true, onPressed: () => context.go('/vendor')),
    );
  }
}
