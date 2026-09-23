class NavItem {
  const NavItem(this.label, this.path, this.icon);
  final String label;
  final String path;
  final String icon;
}

/// Full admin navigation mirroring the frontend sidebar order.
class AdminNav {
  AdminNav._();
  static const groups = <(String?, List<NavItem>)>[
    (null, [
      NavItem('Overview', '/admin', 'grid'),
      NavItem('Messages', '/admin/messages', 'users'),
      NavItem('Analytics', '/admin/analytics', 'chart'),
      NavItem('Financial Ledger', '/admin/ledger', 'wallet'),
      NavItem('Commission Rules', '/admin/commission-rules', 'wallet'),
      NavItem('Fraud & Risk', '/admin/risk', 'bell'),
      NavItem('Supplier Acquisition', '/admin/supplier-acquisition', 'users'),
      NavItem('Vendor Acquisition', '/admin/vendor-acquisition', 'users'),
    ]),
    ('Marketplace', [
      NavItem('Users', '/admin/users', 'users'),
      NavItem('Vendors', '/admin/vendors', 'shop'),
      NavItem('Suppliers', '/admin/suppliers', 'shop'),
      NavItem('Affiliates', '/admin/affiliates', 'users'),
      NavItem('Products', '/admin/products', 'box'),
      NavItem('Categories', '/admin/categories', 'tag'),
      NavItem('Orders', '/admin/orders', 'cart'),
      NavItem('Payments', '/admin/payments', 'wallet'),
      NavItem('Transactions', '/admin/transactions', 'wallet'),
      NavItem('Commissions', '/admin/commissions', 'wallet'),
      NavItem('Deliveries', '/admin/deliveries', 'box'),
      NavItem('Refunds', '/admin/refunds', 'wallet'),
      NavItem('Disputes', '/admin/disputes', 'bell'),
      NavItem('Advertising', '/admin/advertising', 'tag'),
      NavItem('Subscriptions', '/admin/subscriptions', 'wallet'),
    ]),
    ('Intelligence', [
      NavItem('Reports', '/admin/reports', 'chart'),
      NavItem('Recommendations', '/admin/recommendations', 'chart'),
      NavItem('Supplier Matching', '/admin/matching', 'users'),
      NavItem('Trust Scores', '/admin/trust', 'chart'),
      NavItem('Reviews', '/admin/reviews', 'chart'),
    ]),
    ('Platform', [
      NavItem('Notifications', '/admin/notifications', 'bell'),
      NavItem('Languages', '/admin/languages', 'grid'),
      NavItem('Locations', '/admin/locations', 'shop'),
      NavItem('Audit Logs', '/admin/audit-logs', 'box'),
      NavItem('Security', '/admin/security', 'settings'),
      NavItem('System Administration', '/admin/system', 'settings'),
      NavItem('Settings', '/admin/settings', 'settings'),
      NavItem('MVEC Support', '/admin/support', 'bell'),
    ]),
  ];

  static List<NavItem> get all => [for (final g in groups) ...g.$2];
}