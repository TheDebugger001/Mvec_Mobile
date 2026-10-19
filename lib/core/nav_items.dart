import '../models/user.dart';

/// One sidebar link: `[href, label, icon]` in the web app.
class NavItem {
  const NavItem(this.href, this.label, this.icon);
  final String href;
  final String label;
  final String icon;
}

class NavGroup {
  const NavGroup(this.label, this.items);
  final String label;
  final List<NavItem> items;
}

/// Where each role lands, and what its dashboard is called.
const Map<String, String> roleHome = {
  'vendor': '/vendor',
  'affiliate': '/affiliate',
  'delivery': '/delivery',
  'super_admin': '/admin',
};

/// Roles that have a mobile dashboard. (Supplier is not implemented yet.)
bool hasDashboard(String? role) => roleHome.containsKey(role);

// The groups below are the web app's `*NavGroups` from `src/data/navItems.js`,
// with identical hrefs, labels and icons.

const adminNavGroups = <NavGroup>[
  NavGroup('Overview', [
    NavItem('/admin', 'Overview', 'grid'),
    NavItem('/admin/become-seller', 'Become a Seller', 'shop'),
  ]),
  NavGroup('People & Stores', [
    NavItem('/admin/vendors', 'Sellers', 'shop'),
    NavItem('/admin/affiliates', 'Affiliates', 'users'),
    NavItem('/admin/users', 'Users', 'users'),
  ]),
  NavGroup('Orders', [
    NavItem('/admin/orders', 'Orders', 'cart'),
    NavItem('/admin/deliveries', 'Deliveries', 'box'),
    NavItem('/admin/disputes', 'Disputes', 'bell'),
  ]),
  NavGroup('Money', [
    NavItem('/admin/payments', 'Payments', 'wallet'),
    NavItem('/admin/vendor-payouts', 'Seller Payouts', 'wallet'),
    NavItem('/admin/transfers', 'Refunds & Withdrawals', 'wallet'),
    NavItem('/admin/commissions', 'MVEC Earnings', 'wallet'),
    NavItem('/admin/commission-rules', 'Commission Rules', 'tag'),
    NavItem('/admin/ledger', 'Financial Ledger', 'wallet'),
  ]),
  NavGroup('Catalog', [
    NavItem('/admin/products', 'Products', 'box'),
    NavItem('/admin/categories', 'Categories', 'tag'),
  ]),
  NavGroup('Growth', [
    NavItem('/admin/advertising', 'Advertising', 'tag'),
    NavItem('/admin/subscriptions', 'Subscriptions', 'wallet'),
  ]),
  NavGroup('Insights', [
    NavItem('/admin/analytics', 'Analytics', 'chart'),
    NavItem('/admin/trust', 'Trust Scores', 'chart'),
    NavItem('/admin/risk', 'Fraud & Risk', 'bell'),
  ]),
  NavGroup('Platform', [
    NavItem('/admin/settings', 'Settings', 'settings'),
    NavItem('/admin/audit-logs', 'Audit Log', 'box'),
  ]),
  NavGroup('Communication', [
    NavItem('/admin/messages', 'Messages', 'users'),
    NavItem('/admin/notifications', 'Notifications', 'bell'),
    NavItem('/admin/support', 'Support Inbox', 'bell'),
  ]),
];

const sellerNavGroups = <NavGroup>[
  NavGroup('Overview', [NavItem('/vendor', 'Dashboard', 'grid')]),
  NavGroup('Store', [
    NavItem('/vendor/stores', 'My Stores', 'shop'),
    NavItem('/vendor/products', 'Products', 'box'),
    NavItem('/vendor/categories', 'Categories', 'tag'),
    NavItem('/vendor/inventory', 'Inventory', 'grid'),
    NavItem('/vendor/shipping', 'Shipping', 'shop'),
  ]),
  NavGroup('Orders & Customers', [
    NavItem('/vendor/orders', 'Orders', 'cart'),
    NavItem('/vendor/purchases', 'Purchases', 'receipt'),
    NavItem('/vendor/quotes', 'Quote Requests', 'receipt'),
    NavItem('/vendor/customers', 'Customers', 'users'),
    NavItem('/vendor/delivery', 'Delivery & Settlement', 'box'),
    NavItem('/vendor/refunds', 'Refunds', 'wallet'),
  ]),
  NavGroup('Finance', [
    NavItem('/vendor/payouts', 'Payouts', 'wallet'),
    NavItem('/vendor/transactions', 'Transactions', 'wallet'),
    NavItem('/vendor/subscription', 'Subscription', 'wallet'),
  ]),
  NavGroup('Growth', [
    NavItem('/vendor/suppliers', 'Find Suppliers', 'shop'),
    NavItem('/vendor/affiliates', 'Affiliate Marketing', 'users'),
    NavItem('/vendor/advertisements', 'Advertisements', 'tag'),
    NavItem('/vendor/promotions', 'Promotions', 'tag'),
    NavItem('/vendor/reviews', 'Reviews', 'heart'),
    NavItem('/vendor/reports', 'Reports', 'chart'),
    NavItem('/vendor/analytics', 'Analytics', 'chart'),
  ]),
  NavGroup('Team & Settings', [
    NavItem('/vendor/team', 'Team / Staff', 'users'),
    NavItem('/vendor/settings', 'Settings', 'settings'),
  ]),
  NavGroup('Support', [
    NavItem('/vendor/messages', 'Messages', 'users'),
    NavItem('/vendor/notifications', 'Notifications', 'bell'),
    NavItem('/vendor/support', 'MVEC Support', 'bell'),
  ]),
];

const affiliateNavGroups = <NavGroup>[
  NavGroup('Overview', [NavItem('/affiliate', 'Dashboard', 'grid')]),
  NavGroup('Promotion', [
    NavItem('/affiliate/products', 'Promote Products', 'box'),
    NavItem('/affiliate/links', 'My Links', 'tag'),
  ]),
  NavGroup('Earnings', [
    NavItem('/affiliate/commissions', 'Commissions', 'chart'),
    NavItem('/affiliate/wallet', 'Wallet', 'wallet'),
    NavItem('/affiliate/withdrawals', 'Withdrawals', 'wallet'),
  ]),
  NavGroup('Account', [NavItem('/affiliate/profile', 'Profile', 'user')]),
  NavGroup('Support', [
    NavItem('/affiliate/messages', 'Messages', 'users'),
    NavItem('/affiliate/notifications', 'Notifications', 'bell'),
    NavItem('/affiliate/support', 'MVEC Support', 'bell'),
  ]),
];

const deliveryNavGroups = <NavGroup>[
  NavGroup('Overview', [NavItem('/delivery', 'Dashboard', 'grid')]),
  NavGroup('Work', [
    NavItem('/delivery/deliveries', 'My Deliveries', 'box'),
    NavItem('/delivery/history', 'Delivered', 'chart'),
  ]),
  NavGroup('Support', [
    NavItem('/delivery/messages', 'Messages', 'users'),
    NavItem('/delivery/support', 'MVEC Support', 'bell'),
    NavItem('/profile', 'My Account', 'user'),
  ]),
];

/// Mobile bottom-bar items per role (the web's `mobilePrimaryByRole`). Admin
/// follows the product owner's brief — Overview, Sales, Wallet, Users — mapped
/// onto the admin pages that really exist: Orders (sales), MVEC Earnings
/// (the MVEC wallet) and Users.
const Map<String, List<String>> mobilePrimaryByRole = {
  'vendor': ['/vendor', '/vendor/products', '/vendor/orders', '/vendor/payouts'],
  'super_admin': ['/admin', '/admin/orders', '/admin/commissions', '/admin/users'],
  'affiliate': ['/affiliate', '/affiliate/links', '/affiliate/wallet', '/affiliate/withdrawals'],
  'delivery': ['/delivery', '/delivery/deliveries', '/delivery/history', '/delivery/messages'],
};

/// Short bottom-bar labels (the sidebar labels are too long for 5 slots).
const Map<String, String> bottomLabel = {
  '/admin': 'Overview',
  '/admin/orders': 'Sales',
  '/admin/commissions': 'Wallet',
  '/admin/users': 'Users',
};

// ─── Permission-aware navigation (mirrors the web sidebar) ───────────────────

const _vendorStaffPermission = <String, String>{
  '/vendor/products': 'canManageProducts',
  '/vendor/inventory': 'canManageProducts',
  '/vendor/categories': 'canManageProducts',
  '/vendor/promotions': 'canManageMarketing',
  '/vendor/purchases': 'canManageProducts',
  '/vendor/suppliers': 'canManageProducts',
  '/vendor/orders': 'canManageOrders',
  '/vendor/quotes': 'canManageOrders',
  '/vendor/customers': 'canManageOrders',
  '/vendor/refunds': 'canManageOrders',
  '/vendor/delivery': 'canManageOrders',
  '/vendor/payouts': 'canManagePayouts',
  '/vendor/transactions': 'canManagePayouts',
  '/vendor/subscription': 'canManagePayouts',
  '/vendor/affiliates': 'canManageMarketing',
  '/vendor/advertisements': 'canManageMarketing',
  '/vendor/reviews': 'canManageMarketing',
  '/vendor/analytics': 'canViewAnalytics',
  '/vendor/reports': 'canViewAnalytics',
  '/vendor/team': 'canManageStaff',
  '/vendor/stores': 'canManageSettings',
  '/vendor/shipping': 'canManageSettings',
  '/vendor/settings': 'canManageSettings',
};

String? permissionForPath(String path) {
  for (final e in _vendorStaffPermission.entries) {
    if (path == e.key || path.startsWith('${e.key}/')) return e.value;
  }
  return null;
}

/// Owners can open everything; staff only what their role allows.
bool staffCan(AppUser? user, String path) {
  if (user == null || !user.isStaff) return true;
  final key = permissionForPath(path);
  return key == null || user.permissionsMap[key] == true;
}

const staffRoleLabel = {
  'STORE_MANAGER': 'Store manager',
  'ORDER_MANAGER': 'Order manager',
  'CATALOG_MANAGER': 'Catalog manager',
  'MARKETING_MANAGER': 'Marketing manager',
  'FINANCE_MANAGER': 'Finance manager',
};

/// Sidebar groups for [role], with links a staff member can't use removed.
List<NavGroup> navGroupsFor(String? role, AppUser? user) {
  final groups = switch (role) {
    'super_admin' => adminNavGroups,
    'affiliate' => affiliateNavGroups,
    'delivery' => deliveryNavGroups,
    _ => sellerNavGroups,
  };
  if (role == 'super_admin') return groups;
  final out = <NavGroup>[];
  for (final g in groups) {
    final items = g.items.where((i) => staffCan(user, i.href)).toList();
    if (items.isNotEmpty) out.add(NavGroup(g.label, items));
  }
  return out;
}

List<NavItem> flatNav(String? role, AppUser? user) => [
      for (final g in navGroupsFor(role, user)) ...g.items,
    ];

/// Account-settings route for a role (`PORTAL_PROFILE` in the web app).
const Map<String, String> portalProfile = {
  'vendor': '/vendor/profile',
  'super_admin': '/admin/profile',
  'affiliate': '/affiliate/profile',
  'delivery': '/delivery/profile',
};
