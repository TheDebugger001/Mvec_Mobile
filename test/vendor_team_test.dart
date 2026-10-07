import 'package:flutter_test/flutter_test.dart';
import 'package:mvec_mobile/features/vendor/models/vendor_team.dart';
import 'package:mvec_mobile/features/vendor/services/vendor_team_service.dart';

import 'helpers/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(restoreApiTransport);

  group('vendor staff roles', () {
    test('roles map to backend permission flags', () {
      expect(VendorTeamRole.storeManager.permissions, {
        'canManageProducts': true,
        'canManageOrders': true,
        'canViewAnalytics': true,
        'canManageSettings': false,
      });
      expect(VendorTeamRole.orderManager.permissions, {
        'canManageProducts': false,
        'canManageOrders': true,
        'canViewAnalytics': false,
        'canManageSettings': false,
      });
      expect(VendorTeamRole.catalogManager.permissions, {
        'canManageProducts': true,
        'canManageOrders': false,
        'canViewAnalytics': false,
        'canManageSettings': false,
      });
    });

    test('rejects roles that are not defined by the backend', () {
      expect(() => VendorTeamRole.parse('OWNER'), throwsFormatException);
    });
  });

  test('loads and maps staff from the vendor staff endpoint', () async {
    final api = fakeApi([
      FakeRoute(
        'GET',
        '/staff',
        body: {
          'staff': [
            {
              '_id': 'staff-1',
              'user': {
                'Fullname': 'Aline Mukamana',
                'email': 'aline@example.rw',
              },
              'role': 'CATALOG_MANAGER',
              'status': 'ACTIVE',
              'permissions': {
                'canManageProducts': true,
                'canManageOrders': false,
                'canViewAnalytics': false,
                'canManageSettings': false,
              },
            },
          ],
        },
      ),
    ]);

    final members = await VendorTeamService(api.client).members();

    expect(api.recorded.single.path, '/staff');
    expect(members, hasLength(1));
    expect(members.single.name, 'Aline Mukamana');
    expect(members.single.email, 'aline@example.rw');
    expect(members.single.role, VendorTeamRole.catalogManager);
    expect(members.single.grantedPermissions, ['Manage products']);
  });
}
