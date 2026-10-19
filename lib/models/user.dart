import '../core/format.dart';

/// The signed-in account, shaped like `mapUser()` in the web client.
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.telephone,
    required this.email,
    required this.gender,
    required this.role,
    required this.avatarUrl,
    required this.companyName,
    required this.businessName,
    required this.logoUrl,
    required this.description,
    required this.category,
    required this.isOnboarded,
    required this.isGuest,
    required this.verificationStatus,
    required this.verificationNote,
    required this.isSellerEnabled,
    required this.isStaff,
    required this.staffRole,
    required this.staffStoreName,
    required this.permissionsMap,
    required this.preferences,
    required this.emailVerified,
    required this.hasPassword,
    required this.googleLinked,
    required this.createdAt,
  });

  final String id;
  final String fullName;
  final String telephone;
  final String email;
  final String gender;
  final String role;
  final String avatarUrl;
  final String companyName;
  final String businessName;
  final String logoUrl;
  final String description;
  final String category;
  final bool isOnboarded;
  final bool isGuest;
  final String verificationStatus;
  final String verificationNote;
  final bool isSellerEnabled;

  /// Vendor staff sign in to their employer's store with limited access.
  final bool isStaff;
  final String? staffRole;
  final String? staffStoreName;
  final Map<String, bool> permissionsMap;
  final Map<String, dynamic>? preferences;
  final bool emailVerified;
  final bool hasPassword;
  final bool googleLinked;
  final DateTime? createdAt;

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Account' : parts.first;
  }

  String get initial => fullName.trim().isEmpty ? 'M' : fullName.trim()[0].toUpperCase();

  bool get isBuyer => role == 'buyer';
  bool get isAdmin => role == 'super_admin';

  factory AppUser.fromJson(Map<String, dynamic> u) {
    final role = strOf(u['role'], 'buyer');
    final perms = <String, bool>{};
    asMap(u['permissionsMap']).forEach((k, v) => perms[k] = v == true);
    return AppUser(
      id: strOf(u['_id'] ?? u['id']),
      fullName: strOf(u['Fullname'] ?? u['fullName'] ?? u['name']),
      telephone: strOf(u['phone'] ?? u['telephone']),
      email: strOf(u['email']),
      gender: strOf(u['gender']),
      role: role,
      avatarUrl: strOf(u['avatarUrl']),
      companyName: strOf(u['companyName']),
      businessName: strOf(u['businessName'] ?? u['companyName']),
      logoUrl: strOf(u['logoUrl']),
      description: strOf(u['description']),
      category: strOf(u['category']),
      isOnboarded: u['isOnboarded'] != false,
      isGuest: u['isGuest'] == true,
      // Same rule as the server: a seller with no status yet is unverified.
      verificationStatus: strOf(
        u['verificationStatus'],
        ['vendor', 'supplier'].contains(role) ? 'UNVERIFIED' : 'VERIFIED',
      ),
      verificationNote: strOf(u['verificationNote']),
      isSellerEnabled: u['isSellerEnabled'] == true,
      isStaff: u['isStaff'] == true,
      staffRole: u['staffRole']?.toString(),
      staffStoreName: u['staffStoreName']?.toString(),
      permissionsMap: perms,
      preferences: u['preferences'] is Map ? asMap(u['preferences']) : null,
      emailVerified: u['email_verified'] == true,
      hasPassword: u['hasPassword'] != false,
      googleLinked: u['googleLinked'] == true,
      createdAt: parseDate(u['createdAt']),
    );
  }

  AppUser copyWith({
    String? fullName,
    String? email,
    String? gender,
    String? avatarUrl,
    String? telephone,
    Map<String, dynamic>? preferences,
  }) =>
      AppUser(
        id: id,
        fullName: fullName ?? this.fullName,
        telephone: telephone ?? this.telephone,
        email: email ?? this.email,
        gender: gender ?? this.gender,
        role: role,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        companyName: companyName,
        businessName: businessName,
        logoUrl: logoUrl,
        description: description,
        category: category,
        isOnboarded: isOnboarded,
        isGuest: isGuest,
        verificationStatus: verificationStatus,
        verificationNote: verificationNote,
        isSellerEnabled: isSellerEnabled,
        isStaff: isStaff,
        staffRole: staffRole,
        staffStoreName: staffStoreName,
        permissionsMap: permissionsMap,
        preferences: preferences ?? this.preferences,
        emailVerified: emailVerified,
        hasPassword: hasPassword,
        googleLinked: googleLinked,
        createdAt: createdAt,
      );
}
