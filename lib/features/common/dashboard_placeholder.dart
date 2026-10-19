import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/auth_state.dart';
import '../../widgets/common.dart';

/// Landing for the role dashboards, which are the next phase of the rebuild.
class DashboardPlaceholderPage extends ConsumerWidget {
  const DashboardPlaceholderPage({super.key, required this.location});
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((a) => a.user));
    return Scaffold(
      appBar: AppBar(title: const MvLogo(size: 24), actions: const [ThemeToggleButton()]),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(
                  icon: Icons.construction_rounded,
                  title: 'Dashboard coming next',
                  message: 'Signed in as ${user?.fullName ?? 'your account'}. The dashboard at $location is part of the next phase of the mobile rebuild.',
                ),
                GradientButton(label: 'Open the marketplace', compact: true, onPressed: () => context.go('/')),
                const SizedBox(height: 10),
                OutlineBtn(
                  label: 'Sign out',
                  compact: true,
                  onPressed: () async {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) context.go('/');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
