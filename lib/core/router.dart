import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/account/account_screen.dart';
import '../screens/buyers/buyers_screen.dart';
import '../screens/layout/admin_shell.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/audit_logs/audit_logs_screen.dart';
import '../screens/categories/categories_screen.dart';
import '../screens/commission_rules/commission_rules_screen.dart';
import '../screens/disputes/disputes_screen.dart';
import '../screens/deliveries/deliveries_screen.dart';
import '../screens/advertising/advertising_screen.dart';
import '../screens/affiliates/affiliates_screen.dart';
import '../screens/languages/languages_screen.dart';
import '../screens/ledger/ledger_screen.dart';
import '../screens/locations/locations_screen.dart';
import '../screens/matching/matching_screen.dart';
import '../screens/messages/messages_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/overview/overview_screen.dart';
import '../screens/payments/payments_screen.dart';
import '../screens/products/products_screen.dart';
import '../screens/recommendations/recommendations_screen.dart';
import '../screens/refunds/refunds_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/reviews/reviews_screen.dart';
import '../screens/risk/risk_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/security/security_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../screens/support/support_screen.dart';
import '../screens/suppliers/suppliers_screen.dart';
import '../screens/system/system_screen.dart';
import '../screens/transactions/transactions_screen.dart';
import '../screens/trust/trust_screen.dart';
import '../screens/users/users_screen.dart';
import '../screens/vendors/vendors_screen.dart';
import '../screens/commissions/commissions_screen.dart';
import '../screens/acquisitions/acquisitions_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final gate = ValueNotifier(0);
  ref.onDispose(gate.dispose);
  ref.listen(authControllerProvider, (prev, next) {
    if (prev?.isLoggedIn != next.isLoggedIn) gate.value++;
  });

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: gate,
    redirect: (context, state) {
      final loggedIn = ref.read(authControllerProvider).isLoggedIn;
      final loc = state.matchedLocation;
      final isAdminRoute = loc.startsWith('/admin');
      if (isAdminRoute && !loggedIn) return '/login';
      if (loc == '/login' && loggedIn) return '/admin';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) {
          final loggedIn = ref.read(authControllerProvider).isLoggedIn;
          return loggedIn ? '/admin' : '/login';
        },
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminShell(path: '/admin', child: OverviewScreen()),
      ),
      GoRoute(
        path: '/admin/messages',
        builder: (context, state) => const AdminShell(path: '/admin/messages', child: MessagesScreen()),
      ),
      GoRoute(
        path: '/admin/analytics',
        builder: (context, state) => const AdminShell(path: '/admin/analytics', child: AnalyticsScreen()),
      ),
      GoRoute(
        path: '/admin/ledger',
        builder: (context, state) => const AdminShell(path: '/admin/ledger', child: LedgerScreen()),
      ),
      GoRoute(
        path: '/admin/commission-rules',
        builder: (context, state) => const AdminShell(path: '/admin/commission-rules', child: CommissionRulesScreen()),
      ),
      GoRoute(
        path: '/admin/risk',
        builder: (context, state) => const AdminShell(path: '/admin/risk', child: RiskScreen()),
      ),
      GoRoute(
        path: '/admin/supplier-acquisition',
        builder: (context, state) => const AdminShell(path: '/admin/supplier-acquisition', child: AcquisitionScreen(type: 'supplier')),
      ),
      GoRoute(
        path: '/admin/vendor-acquisition',
        builder: (context, state) => const AdminShell(path: '/admin/vendor-acquisition', child: AcquisitionScreen(type: 'vendor')),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const AdminShell(path: '/admin/users', child: UsersScreen()),
      ),
      GoRoute(
        path: '/admin/vendors',
        builder: (context, state) => const AdminShell(path: '/admin/vendors', child: VendorsScreen()),
      ),
      GoRoute(
        path: '/admin/suppliers',
        builder: (context, state) => const AdminShell(path: '/admin/suppliers', child: SuppliersScreen()),
      ),
      GoRoute(
        path: '/admin/buyers',
        builder: (context, state) => const AdminShell(path: '/admin/buyers', child: BuyersScreen()),
      ),
      GoRoute(
        path: '/admin/account',
        builder: (context, state) => const AdminShell(path: '/admin/account', child: AccountScreen()),
      ),
      GoRoute(
        path: '/admin/affiliates',
        builder: (context, state) => const AdminShell(path: '/admin/affiliates', child: AffiliatesScreen()),
      ),
      GoRoute(
        path: '/admin/products',
        builder: (context, state) => const AdminShell(path: '/admin/products', child: ProductsScreen()),
      ),
      GoRoute(
        path: '/admin/categories',
        builder: (context, state) => const AdminShell(path: '/admin/categories', child: CategoriesScreen()),
      ),
      GoRoute(
        path: '/admin/orders',
        builder: (context, state) => const AdminShell(path: '/admin/orders', child: OrdersScreen()),
      ),
      GoRoute(
        path: '/admin/payments',
        builder: (context, state) => const AdminShell(path: '/admin/payments', child: PaymentsScreen()),
      ),
      GoRoute(
        path: '/admin/transactions',
        builder: (context, state) => const AdminShell(path: '/admin/transactions', child: TransactionsScreen()),
      ),
      GoRoute(
        path: '/admin/commissions',
        builder: (context, state) => const AdminShell(path: '/admin/commissions', child: CommissionsScreen()),
      ),
      GoRoute(
        path: '/admin/deliveries',
        builder: (context, state) => const AdminShell(path: '/admin/deliveries', child: DeliveriesScreen()),
      ),
      GoRoute(
        path: '/admin/refunds',
        builder: (context, state) => const AdminShell(path: '/admin/refunds', child: RefundsScreen()),
      ),
      GoRoute(
        path: '/admin/disputes',
        builder: (context, state) => const AdminShell(path: '/admin/disputes', child: DisputesScreen()),
      ),
      GoRoute(
        path: '/admin/advertising',
        builder: (context, state) => const AdminShell(path: '/admin/advertising', child: AdvertisingScreen()),
      ),
      GoRoute(
        path: '/admin/subscriptions',
        builder: (context, state) => const AdminShell(path: '/admin/subscriptions', child: SubscriptionsScreen()),
      ),
      GoRoute(
        path: '/admin/reports',
        builder: (context, state) => const AdminShell(path: '/admin/reports', child: ReportsScreen()),
      ),
      GoRoute(
        path: '/admin/recommendations',
        builder: (context, state) => const AdminShell(path: '/admin/recommendations', child: RecommendationsScreen()),
      ),
      GoRoute(
        path: '/admin/matching',
        builder: (context, state) => const AdminShell(path: '/admin/matching', child: MatchingScreen()),
      ),
      GoRoute(
        path: '/admin/trust',
        builder: (context, state) => const AdminShell(path: '/admin/trust', child: TrustScreen()),
      ),
      GoRoute(
        path: '/admin/reviews',
        builder: (context, state) => const AdminShell(path: '/admin/reviews', child: ReviewsScreen()),
      ),
      GoRoute(
        path: '/admin/notifications',
        builder: (context, state) => const AdminShell(path: '/admin/notifications', child: NotificationsScreen()),
      ),
      GoRoute(
        path: '/admin/languages',
        builder: (context, state) => const AdminShell(path: '/admin/languages', child: LanguagesScreen()),
      ),
      GoRoute(
        path: '/admin/locations',
        builder: (context, state) => const AdminShell(path: '/admin/locations', child: LocationsScreen()),
      ),
      GoRoute(
        path: '/admin/audit-logs',
        builder: (context, state) => const AdminShell(path: '/admin/audit-logs', child: AuditLogsScreen()),
      ),
      GoRoute(
        path: '/admin/security',
        builder: (context, state) => const AdminShell(path: '/admin/security', child: SecurityScreen()),
      ),
      GoRoute(
        path: '/admin/system',
        builder: (context, state) => const AdminShell(path: '/admin/system', child: SystemScreen()),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (context, state) => const AdminShell(path: '/admin/settings', child: SettingsScreen()),
      ),
      GoRoute(
        path: '/admin/support',
        builder: (context, state) => const AdminShell(path: '/admin/support', child: SupportScreen()),
      ),
      GoRoute(
        path: '/admin/search',
        builder: (context, state) => const AdminShell(path: '/admin/search', child: SearchScreen()),
      ),
    ],
  );
});