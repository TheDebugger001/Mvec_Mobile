import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../shell/marketplace_shell.dart' show ShopShortcuts;
import '../../widgets/common.dart';

/// Full-screen page with a back arrow (product, checkout, payment, order).
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.body, this.actions, this.bottom, this.fallback = '/', this.shopping = false});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;
  final String fallback;

  /// Shows compare, wishlist and cart in the top bar, as on the storefront.
  final bool shopping;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go(fallback),
        ),
        title: Text(title),
        actions: shopping ? [...?actions, const ShopShortcuts(), const SizedBox(width: 6)] : actions,
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: context.mv.border)),
      ),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: bottom == null
          ? null
          : Container(
              decoration: BoxDecoration(color: context.mv.surface, border: Border(top: BorderSide(color: context.mv.border))),
              child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 10), child: bottom)),
            ),
    );
  }
}

/// Scrolling page body with the standard 14px gutter.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: children,
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Prompt for pages that need an account.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.what});
  final String what;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Sign in to see $what',
        action: GradientButton(label: 'Sign in', compact: true, onPressed: () => context.push('/login?next=${Uri.encodeQueryComponent(GoRouterState.of(context).uri.toString())}')),
      );
}
