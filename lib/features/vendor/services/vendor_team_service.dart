import '../../../core/api_client.dart';
import '../models/vendor_team.dart';

class VendorTeamService {
  VendorTeamService(this._api);

  final ApiClient _api;

  Future<List<VendorTeamMember>> members() async {
    final response = await _api.get('/staff');
    return listJson(response, ['staff', 'data'])
        .map(VendorTeamMember.fromJson)
        .toList();
  }

  /// Adds an existing MVEC account to this vendor's store.
  Future<void> addMember({
    required String email,
    required VendorTeamRole role,
  }) async {
    await _api.post(
      '/staff',
      body: {'email': email.trim(), 'role': role.apiValue, 'permissions': role.permissions},
    );
  }

  Future<void> updateMember(
    VendorTeamMember member, {
    VendorTeamRole? role,
    bool? active,
  }) async {
    final selectedRole = role ?? member.role;
    await _api.put(
      '/staff/${member.id}',
      body: {
        if (role != null) 'role': selectedRole.apiValue,
        if (role != null) 'permissions': selectedRole.permissions,
        if (active != null) 'status': active ? 'ACTIVE' : 'SUSPENDED',
      },
    );
  }

  Future<void> removeMember(String id) => _api.delete('/staff/$id');
}
