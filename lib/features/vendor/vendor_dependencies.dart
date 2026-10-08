import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'models/vendor_finance.dart';
import 'models/vendor_notification.dart';
import 'models/vendor_order.dart';
import 'models/vendor_settings.dart';
import 'models/vendor_team.dart';
import 'services/vendor_finance_service.dart';
import 'services/vendor_notification_service.dart';
import 'services/vendor_order_service.dart';
import 'services/vendor_settings_service.dart';
import 'services/vendor_team_service.dart';

/// Every vendor module is served by the platform API.
///
/// There is no bundled dataset behind these contracts any more: each service
/// parses whatever `/stores/mine/*` returns, so an unshipped endpoint surfaces
/// as an error state on the page and an empty one once the backend answers with
/// no rows.
final vendorOrderModuleProvider = Provider<VendorOrderService>(
  (ref) => ApiVendorOrderService(ref.watch(apiProvider)),
);

final vendorFinanceModuleProvider = Provider<VendorFinanceService>(
  (ref) => ApiVendorFinanceService(ref.watch(apiProvider)),
);

final vendorNotificationModuleProvider = Provider<VendorNotificationService>(
  (ref) => ApiVendorNotificationService(ref.watch(apiProvider)),
);

final vendorSettingsModuleProvider = Provider<VendorSettingsService>(
  (ref) => ApiVendorSettingsService(ref.watch(apiProvider)),
);

final vendorTeamServiceProvider = Provider<VendorTeamService>(
  (ref) => VendorTeamService(ref.watch(apiProvider)),
);

final vendorTeamProvider = FutureProvider.autoDispose<List<VendorTeamMember>>(
  (ref) => ref.watch(vendorTeamServiceProvider).members(),
);

final vendorOrdersPageProvider = FutureProvider.autoDispose.family<
  VendorOrderPage,
  VendorOrderStatus?
>((ref, status) => ref.watch(vendorOrderModuleProvider).orders(status: status));

final vendorFinanceSummaryProvider =
    FutureProvider.autoDispose<VendorFinanceSummary>(
      (ref) => ref.watch(vendorFinanceModuleProvider).summary(),
    );

final vendorLedgerProvider = FutureProvider.autoDispose<List<LedgerEntry>>(
  (ref) => ref.watch(vendorFinanceModuleProvider).ledger(),
);

final vendorPayoutsProvider = FutureProvider.autoDispose<List<PayoutRequest>>(
  (ref) => ref.watch(vendorFinanceModuleProvider).payouts(),
);

final vendorNotificationsProvider = FutureProvider.autoDispose
    .family<List<VendorNotification>, NotificationCategory?>(
      (ref, category) => ref
          .watch(vendorNotificationModuleProvider)
          .notifications(category: category),
    );

final vendorStoreSettingsProvider =
    FutureProvider.autoDispose<VendorStoreSettings>(
      (ref) => ref.watch(vendorSettingsModuleProvider).settings(),
    );
