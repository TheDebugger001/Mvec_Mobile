/// Vendor staff roles and the members returned by `/api/staff`.
library;

enum VendorTeamRole {
  storeManager,
  orderManager,
  catalogManager;

  String get apiValue => switch (this) {
    VendorTeamRole.storeManager => 'STORE_MANAGER',
    VendorTeamRole.orderManager => 'ORDER_MANAGER',
    VendorTeamRole.catalogManager => 'CATALOG_MANAGER',
  };

  String get label => switch (this) {
    VendorTeamRole.storeManager => 'Vendor manager',
    VendorTeamRole.orderManager => 'Order manager',
    VendorTeamRole.catalogManager => 'Catalog manager',
  };

  String get description => switch (this) {
    VendorTeamRole.storeManager =>
      'Manage products and orders, and view vendor analytics.',
    VendorTeamRole.orderManager => 'Manage and process store orders.',
    VendorTeamRole.catalogManager => 'Create and maintain store products.',
  };

  Map<String, bool> get permissions => switch (this) {
    VendorTeamRole.storeManager => const {
      'canManageProducts': true,
      'canManageOrders': true,
      'canViewAnalytics': true,
      'canManageSettings': false,
    },
    VendorTeamRole.orderManager => const {
      'canManageProducts': false,
      'canManageOrders': true,
      'canViewAnalytics': false,
      'canManageSettings': false,
    },
    VendorTeamRole.catalogManager => const {
      'canManageProducts': true,
      'canManageOrders': false,
      'canViewAnalytics': false,
      'canManageSettings': false,
    },
  };

  static VendorTeamRole parse(String? raw) {
    for (final role in values) {
      if (role.apiValue == raw?.trim().toUpperCase()) return role;
    }
    throw FormatException('Unknown vendor staff role: $raw');
  }
}

class VendorTeamMember {
  const VendorTeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.permissions,
  });

  final String id;
  final String name;
  final String email;
  final VendorTeamRole role;
  final String status;
  final Map<String, bool> permissions;

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  List<String> get grantedPermissions => [
    if (permissions['canManageProducts'] == true) 'Manage products',
    if (permissions['canManageOrders'] == true) 'Manage orders',
    if (permissions['canViewAnalytics'] == true) 'View analytics',
    if (permissions['canManageSettings'] == true) 'Manage store settings',
  ];

  factory VendorTeamMember.fromJson(Map<String, dynamic> json) {
    final user =
        json['user'] is Map
            ? Map<String, dynamic>.from(json['user'] as Map)
            : const <String, dynamic>{};
    final rawPermissions =
        json['permissions'] is Map
            ? Map<String, dynamic>.from(json['permissions'] as Map)
            : const <String, dynamic>{};
    final email = '${user['email'] ?? json['email'] ?? ''}'.trim();
    final name =
        '${user['Fullname'] ?? user['fullname'] ?? user['name'] ?? ''}'.trim();

    return VendorTeamMember(
      id: '${json['_id'] ?? json['id'] ?? ''}',
      name: name.isEmpty ? email : name,
      email: email,
      role: VendorTeamRole.parse(json['role']?.toString()),
      status: '${json['status'] ?? 'ACTIVE'}',
      permissions: {
        for (final key in const [
          'canManageProducts',
          'canManageOrders',
          'canViewAnalytics',
          'canManageSettings',
        ])
          key: rawPermissions[key] == true,
      },
    );
  }
}
