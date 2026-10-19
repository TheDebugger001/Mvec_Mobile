import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/nav_items.dart';
import 'features/auth/login_page.dart';
import 'features/common/coming_soon.dart';
import 'features/marketplace/home_page.dart';
import 'features/marketplace/shop_page.dart';
import 'shell/marketplace_shell.dart';
import 'state/auth_state.dart';
import 'widgets/common.dart';

/// Pages that need an account.
bool _needsLogin(String path) =>
    path == '/wishlist' ||
    path == '/profile' ||
    path.startsWith('/orders') ||
    path.startsWith('/payment') ||
    const ['/buyer/refunds', '/buyer/messages', '/buyer/notifications', '/buyer/subscription'].contains(path) ||
    path.startsWith('/vendor') ||
    path.startsWith('/admin') ||
    path.startsWith('/affiliate') ||
    path.startsWith('/delivery');

/// Dashboard prefix -> the role allowed in.
const _portalRoles = {'/vendor': 'vendor', '/admin': 'super_admin', '/affiliate': 'affiliate', '/delivery': 'delivery'};

final routerProvider = Provider<GoRouter>((ref) {
  final gate = ValueNotifier(0);
  ref.onDispose(gate.dispose);
  ref.listen(authProvider, (prev, next) {
    if (prev?.user?.id != next.user?.id || prev?.restoring != next.restoring) gate.value++;
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: gate,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      final here = state.uri.toString();

      if (path == '/boot') {
        if (auth.restoring) return null;
        final next = state.uri.queryParameters['next'] ?? '/';
        return next;
      }
      if (auth.restoring) return _needsLogin(path) ? '/boot?next=${Uri.encodeQueryComponent(here)}' : null;

      final user = auth.user;
      if (user == null) {
        return _needsLogin(path) ? '/login?next=${Uri.encodeQueryComponent(here)}' : null;
      }
      // Signed in people never sit on the sign-in pages.
      if (path == '/login') {
        final next = state.uri.queryParameters['next'] ?? '';
        return next.isNotEmpty && next.startsWith('/') && !next.startsWith('//') ? next : (roleHome[user.role] ?? '/');
      }
      // Portals are only for their own role (an admin may act as a seller).
      for (final e in _portalRoles.entries) {
        if (path == e.key || path.startsWith('${e.key}/')) {
          final actingSeller = user.role == 'super_admin' && user.isSellerEnabled && e.value == 'vendor';
          if (user.role != e.value && !actingSeller) return roleHome[user.role] ?? '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/boot', builder: (_, __) => const Scaffold(body: Center(child: LoadingState(label: 'Loading MVEC…')))),
      GoRoute(path: '/login', builder: (_, s) => LoginPage(next: s.uri.queryParameters['next'] ?? '')),
      GoRoute(path: '/signup', builder: (_, __) => const Scaffold(body: ComingSoonPage(title: 'Create account'))),
      GoRoute(path: '/forgot-password', builder: (_, __) => const Scaffold(body: ComingSoonPage(title: 'Forgot password'))),
      ShellRoute(
        builder: (context, state, child) => MarketplaceShell(uri: state.uri, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomePage()),
          GoRoute(path: '/shop', builder: (_, s) => ShopPage(params: s.uri.queryParameters)),
          GoRoute(path: '/buyer/recommendations', builder: (_, __) => const ComingSoonPage(title: 'Recommended for you')),
          GoRoute(path: '/orders', builder: (_, __) => const ComingSoonPage(title: 'My orders')),
          GoRoute(path: '/cart', builder: (_, __) => const ComingSoonPage(title: 'Your cart')),
          GoRoute(path: '/wishlist', builder: (_, __) => const ComingSoonPage(title: 'Wishlist')),
          GoRoute(path: '/vendors', builder: (_, __) => const ComingSoonPage(title: 'Stores')),
          GoRoute(path: '/profile', builder: (_, __) => const ComingSoonPage(title: 'My account')),
          GoRoute(path: '/buyer/support', builder: (_, __) => const ComingSoonPage(title: 'Help & Support')),
        ],
      ),
    ],
  );
});
