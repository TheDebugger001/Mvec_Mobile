import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/nav_items.dart';
import 'features/auth/forgot_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/signup_page.dart';
import 'features/account/activity_pages.dart';
import 'features/account/profile_page.dart';
import 'features/common/coming_soon.dart';
import 'features/common/page_frame.dart';
import 'features/marketplace/browse_pages.dart';
import 'features/marketplace/cart_page.dart';
import 'features/marketplace/checkout_page.dart';
import 'features/marketplace/home_page.dart';
import 'features/marketplace/order_detail_page.dart';
import 'features/marketplace/orders_page.dart';
import 'features/marketplace/payment_page.dart';
import 'features/marketplace/product_page.dart';
import 'features/marketplace/shop_page.dart';
import 'features/marketplace/wishlist_page.dart';
import 'features/admin/admin_money_pages.dart';
import 'features/admin/admin_people_pages.dart';
import 'features/admin/admin_platform_pages.dart';
import 'features/affiliate/affiliate_pages.dart';
import 'features/seller/affiliate_program_page.dart';
import 'features/seller/finance_pages.dart';
import 'features/seller/orders_pages.dart';
import 'features/seller/products_pages.dart';
import 'features/seller/store_pages.dart';
import 'features/supplier/supplier_pages.dart';
import 'features/wholesale/wholesale_pages.dart';
import 'portal/delivery_tracking.dart';
import 'portal/portal_shell.dart';
import 'portal/shared_pages.dart';
import 'shell/marketplace_shell.dart';
import 'state/auth_state.dart';
import 'widgets/common.dart';

/// Pages that need an account.
bool _needsLogin(String path) =>
    path == '/wishlist' ||
    path == '/buyer/support/requests' ||
    path == '/profile' ||
    path.startsWith('/orders') ||
    path.startsWith('/payment') ||
    const ['/buyer/refunds', '/buyer/messages', '/buyer/notifications', '/buyer/subscription'].contains(path) ||
    path.startsWith('/vendor') ||
    path.startsWith('/supplier') ||
    path.startsWith('/admin') ||
    path.startsWith('/affiliate') ||
    path.startsWith('/delivery');

/// Dashboard prefix -> the role allowed in.
const _portalRoles = {'/vendor': 'vendor', '/supplier': 'supplier', '/admin': 'super_admin', '/affiliate': 'affiliate', '/delivery': 'delivery'};

final routerProvider = Provider<GoRouter>((ref) {
  final gate = ValueNotifier(0);
  ref.onDispose(gate.dispose);
  ref.listen(authProvider, (prev, next) {
    if (prev?.user?.id != next.user?.id || prev?.restoring != next.restoring) gate.value++;
  });

  return GoRouter(
    initialLocation: '/',
    errorBuilder: (context, state) {
      final path = state.uri.path;
      if (_portalRoles.keys.any((p) => path == p || path.startsWith('$p/'))) {
        return Scaffold(appBar: AppBar(), body: PortalNotFoundPage(path: path));
      }
      return Scaffold(body: ComingSoonPage(title: 'Page not found'));
    },
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
      if (path == '/login' || path == '/signup') {
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
      GoRoute(path: '/login', builder: (_, s) => LoginPage(next: s.uri.queryParameters['next'] ?? '', checkout: s.uri.queryParameters['checkout'] == '1')),
      GoRoute(path: '/signup', builder: (_, s) => SignupPage(role: s.uri.queryParameters['role'], next: s.uri.queryParameters['next'] ?? '')),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordPage()),
      GoRoute(path: '/track/:code', builder: (_, s) => AffiliateTrackPage(code: s.pathParameters['code']!)),
      // Full-screen pages (own back arrow, no marketplace bars).
      GoRoute(path: '/product/:id', builder: (_, s) => ProductPage(id: s.pathParameters['id']!)),
      GoRoute(
        path: '/checkout',
        builder: (_, s) => CheckoutPage(productId: s.uri.queryParameters['product'], qty: int.tryParse(s.uri.queryParameters['qty'] ?? '') ?? 1),
      ),
      GoRoute(path: '/payment/:id', builder: (_, s) => PaymentPage(orderId: s.pathParameters['id']!)),
      GoRoute(path: '/orders/:id', builder: (_, s) => OrderDetailPage(id: s.pathParameters['id']!)),
      GoRoute(path: '/buyer/messages/:id', builder: (_, s) => ChatPage(id: s.pathParameters['id']!)),
      GoRoute(path: '/buyer/support/requests', builder: (_, __) => const PageFrame(title: 'MVEC Support', fallback: '/buyer/support', body: SupportPage(role: 'buyer'))),
      GoRoute(path: '/vendor/orders/:id', builder: (_, s) => SellerOrderDetailPage(id: s.pathParameters['id']!)),
      GoRoute(path: '/admin/orders/:id', builder: (_, s) => SellerOrderDetailPage(id: s.pathParameters['id']!, admin: true)),
      // Dashboards share the dashboard top bar, side menu and bottom bar.
      ShellRoute(
        builder: (context, state, child) => PortalShell(uri: state.uri, child: child),
        routes: [
          ..._sellerRoutes,
          ..._supplierRoutes,
          ..._affiliateRoutes,
          ..._deliveryRoutes,
          ..._adminRoutes,
          for (final p in const ['/vendor', '/supplier', '/affiliate', '/delivery', '/admin'])
            GoRoute(path: '$p/:section', builder: (_, s) => PortalNotFoundPage(path: s.uri.path)),
        ],
      ),
      // Marketplace pages share the top bar, left sidebar and bottom bar.
      ShellRoute(
        builder: (context, state, child) => MarketplaceShell(uri: state.uri, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomePage()),
          GoRoute(path: '/shop', builder: (_, s) => ShopPage(params: s.uri.queryParameters)),
          GoRoute(path: '/buyer/recommendations', builder: (_, __) => const RecommendationsPage()),
          GoRoute(path: '/orders', builder: (_, __) => const OrdersPage()),
          GoRoute(path: '/cart', builder: (_, __) => const CartPage()),
          GoRoute(path: '/wishlist', builder: (_, __) => const WishlistPage()),
          GoRoute(path: '/vendors', builder: (_, __) => const StoresPage()),
          GoRoute(path: '/vendors/:id', builder: (_, s) => StoreDetailPage(id: s.pathParameters['id']!)),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(path: '/buyer/support', builder: (_, __) => const HelpPage()),
          GoRoute(path: '/buyer/compare', builder: (_, __) => const ComparePage()),
          GoRoute(path: '/buyer/refunds', builder: (_, __) => const RefundsPage()),
          GoRoute(path: '/buyer/messages', builder: (_, __) => const MessagesPage()),
          GoRoute(path: '/buyer/notifications', builder: (_, __) => const NotificationsPage()),
          GoRoute(path: '/buyer/subscription', builder: (_, __) => const SubscriptionPage()),
        ],
      ),
    ],
  );
});

/// Seller dashboard pages, each behind the staff permission for its section.
GoRoute _seller(String path, Widget Function(GoRouterState s) page) => GoRoute(path: path, builder: (_, s) => StaffGate(path: s.uri.path, child: page(s)));

final _sellerRoutes = <GoRoute>[
  _seller('/vendor', (_) => const SellerOverviewPage()),
  _seller('/vendor/products', (s) => SellerProductsPage(addNew: s.uri.queryParameters['add'] == '1', category: s.uri.queryParameters['category'])),
  _seller('/vendor/inventory', (_) => const SellerInventoryPage()),
  _seller('/vendor/categories', (_) => const SellerCategoriesPage()),
  _seller('/vendor/orders', (_) => const SellerOrdersPage()),
  _seller('/vendor/customers', (_) => const SellerCustomersPage()),
  _seller('/vendor/payouts', (_) => const SellerPayoutsPage()),
  _seller('/vendor/transactions', (_) => const SellerTransactionsPage()),
  _seller('/vendor/subscription', (_) => const SellerSubscriptionPage()),
  _seller('/vendor/advertisements', (_) => const SellerAdsPage()),
  _seller('/vendor/promotions', (_) => const SellerPromotionsPage()),
  _seller('/vendor/reviews', (_) => const SellerReviewsPage()),
  _seller('/vendor/analytics', (_) => const SellerAnalyticsPage()),
  _seller('/vendor/reports', (_) => const SellerReportsPage()),
  _seller('/vendor/stores', (_) => const SellerStoresPage()),
  _seller('/vendor/shipping', (_) => const SellerShippingPage()),
  _seller('/vendor/team', (_) => const SellerTeamPage()),
  _seller('/vendor/settings', (_) => const SellerSettingsPage()),
  _seller('/vendor/purchases', (s) => WholesaleOrdersPage(supplier: false, notice: s.uri.queryParameters['notice'])),
  _seller('/vendor/quotes', (_) => const VendorQuotesPage()),
  _seller('/vendor/suppliers', (_) => const FindSuppliersPage()),
  _seller('/vendor/affiliates', (_) => const SellerAffiliateProgramPage()),
  _seller('/vendor/delivery', (_) => const DeliveryTrackingPage(role: 'vendor')),
  _seller('/vendor/refunds', (s) => DisputesListPage(role: 'vendor', openCase: s.uri.queryParameters['case'])),
  GoRoute(path: '/vendor/support', builder: (_, __) => const SupportPage(role: 'vendor')),
  GoRoute(path: '/vendor/notifications', builder: (_, __) => const NotificationsPage()),
  GoRoute(path: '/vendor/messages', builder: (_, __) => const MessagesPage()),
  GoRoute(path: '/vendor/profile', builder: (_, __) => const ProfilePage()),
];

final _supplierRoutes = <GoRoute>[
  GoRoute(path: '/supplier', builder: (_, __) => const SupplierOverviewPage()),
  GoRoute(path: '/supplier/products', builder: (_, __) => const SupplierProductsPage()),
  GoRoute(path: '/supplier/inventory', builder: (_, __) => const SupplierInventoryPage()),
  GoRoute(path: '/supplier/orders', builder: (_, __) => const WholesaleOrdersPage(supplier: true)),
  GoRoute(path: '/supplier/delivery', redirect: (_, __) => '/supplier/orders'),
  GoRoute(path: '/supplier/supply-requests', redirect: (_, __) => '/supplier/quotes'),
  GoRoute(path: '/supplier/quotes', builder: (_, __) => const SupplierQuotesPage()),
  GoRoute(path: '/supplier/payments', builder: (_, __) => const SupplierPaymentsPage()),
  GoRoute(path: '/supplier/transactions', builder: (_, __) => const SupplierLedgerPage()),
  GoRoute(path: '/supplier/analytics', builder: (_, __) => const SupplierAnalyticsPage()),
  GoRoute(path: '/supplier/reports', builder: (_, __) => const SupplierLedgerPage(reports: true)),
  GoRoute(path: '/supplier/reviews', builder: (_, __) => const SupplierReviewsPage()),
  GoRoute(path: '/supplier/subscription', builder: (_, __) => const SellerSubscriptionPage(endpoint: '/suppliers/me/subscription', balanceLink: '/supplier/payments')),
  GoRoute(path: '/supplier/team', builder: (_, __) => const SupplierTeamPage()),
  GoRoute(path: '/supplier/settings', builder: (_, __) => const SupplierSettingsPage()),
  GoRoute(path: '/supplier/messages', builder: (_, __) => const MessagesPage()),
  GoRoute(path: '/supplier/notifications', builder: (_, __) => const NotificationsPage()),
  GoRoute(path: '/supplier/support', builder: (_, __) => const SupportPage(role: 'supplier')),
  GoRoute(path: '/supplier/profile', builder: (_, __) => const ProfilePage()),
];

final _affiliateRoutes = <GoRoute>[
  GoRoute(path: '/affiliate', builder: (_, __) => const AffiliateOverviewPage()),
  GoRoute(path: '/affiliate/products', builder: (_, __) => const AffiliateProductsPage()),
  GoRoute(path: '/affiliate/links', builder: (_, __) => const AffiliateLinksPage()),
  GoRoute(path: '/affiliate/commissions', builder: (_, __) => const AffiliateCommissionsPage()),
  GoRoute(path: '/affiliate/wallet', builder: (_, __) => const AffiliateWalletPage()),
  GoRoute(path: '/affiliate/withdrawals', builder: (_, __) => const AffiliateWithdrawalsPage()),
  GoRoute(path: '/affiliate/profile', builder: (_, __) => const AffiliateProfilePage()),
  GoRoute(path: '/affiliate/messages', builder: (_, __) => const MessagesPage()),
  GoRoute(path: '/affiliate/notifications', builder: (_, __) => const NotificationsPage()),
  GoRoute(path: '/affiliate/support', builder: (_, __) => const SupportPage(role: 'affiliate')),
];

final _deliveryRoutes = <GoRoute>[
  GoRoute(
    path: '/delivery',
    builder:
        (_, __) => const DeliveryTrackingPage(
          role: 'delivery',
          header: InfoBox(
            title: 'Delivery confirmation',
            text:
                "When you hand the items to the buyer, ask for the 6-digit code shown on their order and sent to them by SMS. The correct code completes the delivery and releases the seller's payment. Five wrong codes lock the delivery for MVEC support.",
          ),
        ),
  ),
  GoRoute(path: '/delivery/deliveries', builder: (_, __) => const DeliveryTrackingPage(role: 'delivery')),
  GoRoute(path: '/delivery/history', builder: (_, __) => const DeliveryTrackingPage(role: 'delivery', initialTab: 'done')),
  GoRoute(path: '/delivery/messages', builder: (_, __) => const MessagesPage()),
  GoRoute(path: '/delivery/notifications', builder: (_, __) => const NotificationsPage()),
  GoRoute(path: '/delivery/support', builder: (_, __) => const SupportPage(role: 'delivery')),
  GoRoute(path: '/delivery/profile', builder: (_, __) => const ProfilePage()),
];

GoRoute _go(String from, String to) => GoRoute(path: from, redirect: (_, __) => to);

final _adminRoutes = <GoRoute>[
  GoRoute(path: '/admin', builder: (_, __) => const AdminOverviewPage()),
  GoRoute(path: '/admin/users', builder: (_, __) => const AdminRecordsPage(type: 'users')),
  GoRoute(path: '/admin/products', builder: (_, __) => const AdminRecordsPage(type: 'products')),
  GoRoute(path: '/admin/categories', builder: (_, __) => const AdminRecordsPage(type: 'categories')),
  GoRoute(path: '/admin/orders', builder: (_, __) => const AdminRecordsPage(type: 'orders')),
  GoRoute(path: '/admin/vendors', builder: (_, __) => const AdminSellersPage()),
  GoRoute(path: '/admin/suppliers', builder: (_, s) => AdminSuppliersPage(tab: s.uri.queryParameters['tab'])),
  GoRoute(path: '/admin/affiliates', builder: (_, __) => const AdminAffiliatesPage()),
  GoRoute(path: '/admin/deliveries', builder: (_, __) => const DeliveryTrackingPage(role: 'admin')),
  GoRoute(path: '/admin/disputes', builder: (_, s) => DisputesListPage(role: 'admin', openCase: s.uri.queryParameters['case'])),
  GoRoute(path: '/admin/payments', builder: (_, s) => AdminPaymentsPage(status: s.uri.queryParameters['status'] ?? '')),
  GoRoute(path: '/admin/vendor-payouts', builder: (_, __) => const AdminVendorPayoutsPage()),
  GoRoute(path: '/admin/transfers', builder: (_, __) => const AdminTransfersPage()),
  GoRoute(path: '/admin/commissions', builder: (_, __) => const AdminEarningsPage()),
  GoRoute(path: '/admin/commission-rules', builder: (_, __) => const AdminCommissionRulesPage()),
  GoRoute(path: '/admin/ledger', builder: (_, __) => const AdminLedgerPage()),
  GoRoute(path: '/admin/advertising', builder: (_, __) => const AdminAdvertisingPage()),
  GoRoute(path: '/admin/subscriptions', builder: (_, __) => const AdminSubscriptionsPage()),
  GoRoute(path: '/admin/analytics', builder: (_, __) => const AdminAnalyticsPage()),
  GoRoute(path: '/admin/trust', builder: (_, __) => const AdminTrustPage()),
  GoRoute(path: '/admin/risk', builder: (_, __) => const AdminRiskPage()),
  GoRoute(path: '/admin/settings', builder: (_, __) => const AdminPlatformPage()),
  GoRoute(path: '/admin/audit-logs', builder: (_, __) => const AdminAuditLogPage()),
  GoRoute(path: '/admin/messages', builder: (_, __) => const MessagesPage()),
  GoRoute(path: '/admin/notifications', builder: (_, __) => const NotificationsPage()),
  GoRoute(path: '/admin/support', builder: (_, s) => AdminSupportInboxPage(openCase: s.uri.queryParameters['case'])),
  GoRoute(path: '/admin/become-seller', builder: (_, __) => const AdminBecomeSellerPage()),
  GoRoute(path: '/admin/profile', builder: (_, __) => const ProfilePage()),
  _go('/admin/refunds', '/admin/disputes'),
  _go('/admin/transactions', '/admin/payments'),
  _go('/admin/reports', '/admin/analytics'),
  _go('/admin/recommendations', '/admin/analytics'),
  _go('/admin/matching', '/admin/suppliers'),
  _go('/admin/supplier-acquisition', '/admin/suppliers'),
  _go('/admin/vendor-acquisition', '/admin/vendors'),
  for (final p in const ['/admin/languages', '/admin/locations', '/admin/security', '/admin/system']) _go(p, '/admin/settings'),
];
