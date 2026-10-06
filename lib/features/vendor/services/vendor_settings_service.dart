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
  ApiVendorSettingsService();

  Never _unsupported() => throw ApiException(
    'The backend does not expose vendor settings, staff management, or '
    'password-management APIs.',
  );

  @override
  bool get isDemo => false;

  @override
  Future<VendorStoreSettings> settings() async => _unsupported();

  @override
  Future<VendorStoreSettings> save(VendorStoreSettings settings) async =>
      _unsupported();

  @override
  Future<VendorStoreSettings> inviteStaff({
    required VendorStaffMember member,
    required String password,
  }) async => _unsupported();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => _unsupported();

  @override
  Future<VendorStoreSettings> setStaffActive(String id, bool active) async =>
      _unsupported();
}
