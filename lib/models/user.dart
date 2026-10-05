class UserRecord {
  UserRecord({
    this.id,
    this.fullname,
    this.email,
    this.phone,
    this.role,
    this.status,
    this.gender,
    this.companyName,
    this.createdAt,
    this.avatar,
    this.supplierId,
    this.staffRole,
    this.permissions = const [],
  });

  String? id;
  String? fullname;
  String? email;
  String? phone;
  String? role;
  String? status;
  String? gender;
  String? companyName;
  DateTime? createdAt;
  String? avatar;

  /// The supplier account this login belongs to, for staff logins.
  ///
  /// A supplier login carries its own account: [isAccountOwner] is true and
  /// this is null, which is why the API scopes every team query to
  /// `supplierId == me` rather than trusting an id sent by the app.
  String? supplierId;

  /// Which job this login does on the supplier account, e.g. `WAREHOUSE`.
  ///
  /// Deliberately kept separate from [role], which stays `supplier` so every
  /// existing role check, [userType] and [roleHome] keep working. Null means
  /// this login *is* the account, not staff on it.
  String? staffRole;

  /// Permissions granted by the API, when it puts them in the token.
  ///
  /// Used to hide what a member may not do. Never used to decide whether a
  /// request is allowed — the API re-checks every call, because anything the
  /// app can hide, a caller can still reach with curl.
  List<String> permissions;

  factory UserRecord.fromJson(Map<String, dynamic> j) => UserRecord(
    id: j['_id'] ?? j['id'],
    fullname: j['Fullname'] ?? j['fullname'] ?? j['name'],
    email: j['email'],
    phone: j['phone'],
    role: j['role'],
    status: j['status'],
    gender: j['gender'],
    companyName: j['companyName'],
    createdAt: _dt(j['createdAt'] ?? j['created_at']),
    avatar: j['avatar'] ?? j['profileImage'],
    supplierId: j['supplierId'] ?? j['supplier_id'],
    staffRole: j['staffRole'] ?? j['staff_role'],
    permissions: _strings(j['permissions']),
  );

  Map<String, dynamic> toJson() => {
    if (id != null) '_id': id,
    if (fullname != null) 'Fullname': fullname,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (role != null) 'role': role,
    if (status != null) 'status': status,
    if (gender != null) 'gender': gender,
    if (companyName != null) 'companyName': companyName,
    if (supplierId != null) 'supplierId': supplierId,
    if (staffRole != null) 'staffRole': staffRole,
    if (permissions.isNotEmpty) 'permissions': permissions,
  };

  String get display => fullname ?? email ?? phone ?? 'Unknown';

  /// Normalised account type: vendor, supplier, affiliate, buyer, delivery
  /// or super_admin. Unknown values fall back to `buyer`.
  String get userType {
    final r = (role ?? 'buyer').trim().toLowerCase();
    if (r == 'admin' || r == 'super_admin' || r == 'superadmin') {
      return 'super_admin';
    }
    if (r == 'delivery' || r == 'delivery_driver') return 'delivery';
    if (r == 'vendor') return 'vendor';
    if (r == 'supplier') return 'supplier';
    if (r == 'affiliate') return 'affiliate';
    return 'buyer';
  }

  /// True when this login is a supplier account rather than staff on one.
  ///
  /// Owner rights are implied by holding the account, never granted by a
  /// `staffRole` value — otherwise a self-promotion bug hands over the account.
  bool get isAccountOwner =>
      userType == 'supplier' && staffRole == null && status != 'invited';

  /// True when this login has not been signed up yet and can do nothing.
  bool get isPendingInvite => status == 'invited';

  /// Whether the token granted [permission]. Optimistic only; see
  /// [permissions].
  bool can(String permission) =>
      isPendingInvite ? false : permissions.contains(permission.toUpperCase());
}

List<String> _strings(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry != null && '$entry'.trim().isNotEmpty) '$entry'.trim(),
  ];
}

DateTime? _dt(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

DateTime? parseDate(dynamic v) => _dt(v);

class AuthSession {
  AuthSession({required this.token, required this.user});
  final String token;
  final UserRecord user;
}
