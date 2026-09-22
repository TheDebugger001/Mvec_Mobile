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
      );

  Map<String, dynamic> toJson() => {
        if (id != null) '_id': id,
        if (fullname != null) 'Fullname': fullname,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (role != null) 'role': role,
        if (status != null) 'status': status,
      };

  String get display => fullname ?? email ?? phone ?? 'Unknown';
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