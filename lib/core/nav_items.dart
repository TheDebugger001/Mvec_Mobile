class NavItem {
  const NavItem(this.label, this.path, this.icon);
  final String label;
  final String path;
  final String icon;
}

class NavGroup {
  const NavGroup(this.label, this.items);
  final String label;
  final List<NavItem> items;
}

/// Full admin navigation. Groups mirror the frontend `adminNavGroups`
/// (accordion sidebar), plus the two dedicated management features
/// (Buyers, Account) the admin console requires.
class AdminNav {
  AdminNav._();

  static const groups = <NavGroup>[
    NavGroup('Overview', [
      NavItem('Overview', '/admin', 'grid'),
    ]),
    NavGroup('Insights', [
      NavItem('Analytics', '/admin/analytics', 'chart'),
      NavItem('Reports', '/admin/reports', 'chart'),
      NavItem('Recommendations', '/admin/recommendations', 'chart'),
      NavItem('Supplier Matching', '/admin/matching', 'users'),
      NavItem('Trust Scores', '/admin/trust', 'chart'),
      NavItem('Reviews', '/admin/reviews', 'chart'),
    ]),
    NavGroup('People & Stores', [
      NavItem('Users', '/admin/users', 'users'),
      NavItem('Vendors', '/admin/vendors', 'shop'),
      NavItem('Suppliers', '/admin/suppliers', 'shop'),
      NavItem('Affiliates', '/admin/affiliates', 'users'),
      NavItem('Buyers', '/admin/buyers', 'users'),
      NavItem('Supplier Acquisition', '/admin/supplier-acquisition', 'users'),
      NavItem('Vendor Acquisition', '/admin/vendor-acquisition', 'users'),
    ]),
    NavGroup('Catalog', [
      NavItem('Products', '/admin/products', 'box'),
      NavItem('Categories', '/admin/categories', 'tag'),
    ]),
    NavGroup('Orders & Payments', [
      NavItem('Orders', '/admin/orders', 'cart'),
      NavItem('Payments', '/admin/payments', 'wallet'),
      NavItem('Transactions', '/admin/transactions', 'wallet'),
      NavItem('Commissions', '/admin/commissions', 'wallet'),
      NavItem('Commission Rules', '/admin/commission-rules', 'wallet'),
      NavItem('Financial Ledger', '/admin/ledger', 'wallet'),
      NavItem('Deliveries', '/admin/deliveries', 'box'),
      NavItem('Refunds', '/admin/refunds', 'wallet'),
      NavItem('Disputes', '/admin/disputes', 'bell'),
    ]),
    NavGroup('Growth', [
      NavItem('Advertising', '/admin/advertising', 'tag'),
      NavItem('Subscriptions', '/admin/subscriptions', 'wallet'),
    ]),
    NavGroup('Platform', [
      NavItem('Languages', '/admin/languages', 'grid'),
      NavItem('Locations', '/admin/locations', 'shop'),
      NavItem('Audit Logs', '/admin/audit-logs', 'box'),
      NavItem('Security', '/admin/security', 'settings'),
      NavItem('System Administration', '/admin/system', 'settings'),
      NavItem('Settings', '/admin/settings', 'settings'),
      NavItem('Fraud & Risk', '/admin/risk', 'bell'),
      NavItem('Account', '/admin/account', 'user'),
    ]),
    NavGroup('Communication', [
      NavItem('Messages', '/admin/messages', 'users'),
      NavItem('Notifications', '/admin/notifications', 'bell'),
      NavItem('MVEC Support', '/admin/support', 'bell'),
    ]),
  ];

  static List<NavItem> get all => [for (final g in groups) ...g.items];

  /// Primary items shown directly in the mobile bottom bar (frontend
  /// `mobilePrimaryByRole.super_admin`) + a "More" entry that opens the
  /// grouped drawer.
  static const bottomNav = <NavItem>[
    NavItem('Overview', '/admin', 'grid'),
    NavItem('Vendors', '/admin/vendors', 'shop'),
    NavItem('Orders', '/admin/orders', 'cart'),
    NavItem('Ledger', '/admin/ledger', 'wallet'),
  ];

  /// Find the group containing a path (used to auto-open the drawer group).
  static String? groupFor(String path) {
    for (final g in groups) {
      if (g.items.any((i) => i.path == path || (path.startsWith(i.path) && i.path != '/admin'))) {
        return g.label;
      }
    }
    return null;
  }
}