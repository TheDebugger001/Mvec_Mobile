import '../../../core/api_client.dart';
import '../models/vendor_settings.dart';

/// Contract for reading and changing the vendor's store configuration.
abstract class VendorSettingsService {
  bool get isDemo;

  Future<VendorStoreSettings> settings();
  Future<VendorStoreSettings> save(VendorStoreSettings settings);
  Future<VendorStoreSettings> inviteStaff({
    required VendorStaffMember member,
    required String password,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<VendorStoreSettings> setStaffActive(String id, bool active);
}

/// Live adapter for the vendor settings endpoints.
class ApiVendorSettingsService implements VendorSettingsService {
  ApiVendorSettingsService(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<VendorStoreSettings> settings() async {
    final responses = await Future.wait([
      _api.get('/stores/mine'),
      _api.get('/staff'),
      _api.get('/auth/me'),
    ]);
    final store = singleJson(responses[0], ['store']);
    final staff = listJson(responses[1], ['staff']);
    final user = singleJson(responses[2], ['user']);
    final address = store['address'];
    return VendorStoreSettings.fromJson({
      ...store,
      'storeSlug': store['slug'] ?? store['storeSlug'],
      'logoUrl': store['logo'] ?? store['logoUrl'],
      'phone': store['contactPhone'] ?? store['phone'],
      'supportEmail': store['contactEmail'] ?? store['supportEmail'],
      'businessAddress':
          store['businessAddress'] ??
          (address is Map ? address['street'] : address),
      'staff': staff,
      'lastPasswordChangeAt': user['lastPasswordChangeAt'],
    });
  }

  @override
  Future<VendorStoreSettings> save(VendorStoreSettings settings) async {
    final body = settings.toJson()..remove('staff');
    await _api.put('/stores/mine', body: body);

    for (final member in settings.staff.where((member) => !member.isOwner)) {
      await _api.put(
        '/staff/${member.id}',
        body: {
          'role': member.role == StaffRole.manager ? 'manager' : 'staff',
          'permissions': member.permissions.map((permission) => permission.slug).toList(),
          'active': member.active,
        },
      );
    }
    return this.settings();
  }

  @override
  Future<VendorStoreSettings> inviteStaff({
    required VendorStaffMember member,
    required String password,
  }) async {
    await _api.post(
      '/staff',
      body: {
        'name': member.name,
        'email': member.email,
        'password': password,
        'role': member.role == StaffRole.manager ? 'manager' : 'staff',
        'permissions': member.permissions.map((permission) => permission.slug).toList(),
      },
    );
    return settings();
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  @override
  Future<VendorStoreSettings> setStaffActive(String id, bool active) async {
    await _api.put(
      '/staff/$id',
      body: {'active': active},
    );
    return settings();
  }
}
