import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'models/supplier_finance.dart';
import 'models/supplier_insights.dart';
import 'models/supplier_operations.dart';
import 'models/supplier_team.dart';
import 'services/supplier_finance_service.dart';
import 'services/supplier_operations_service.dart';
import 'services/supplier_team_service.dart';

/// One wiring point keeps every Finance & Insights module on the same data
/// source, mirroring `vendor_dependencies.dart`.
///
/// Supplier finance always comes from the authenticated backend API.
final supplierFinanceModuleProvider = Provider<SupplierFinanceService>(
  (ref) => ApiSupplierFinanceService(ref.watch(apiProvider)),
);

/// Headline balances for the Payments page.
final supplierFinanceSummaryProvider =
    FutureProvider.autoDispose<SupplierFinanceSummary>(
      (ref) => ref.watch(supplierFinanceModuleProvider).summary(),
    );

/// The money ledger behind Transactions and the Payments page preview.
final supplierLedgerProvider =
    FutureProvider.autoDispose<List<SupplierLedgerEntry>>(
      (ref) => ref.watch(supplierFinanceModuleProvider).ledger(),
    );

/// Withdrawal requests behind the payout form and history list.
final supplierPayoutsProvider =
    FutureProvider.autoDispose<List<SupplierPayoutRequest>>(
      (ref) => ref.watch(supplierFinanceModuleProvider).payouts(),
    );

/// Trend aggregates for one period, shared by Analytics and Reports.
final supplierAnalyticsProvider = FutureProvider.autoDispose
    .family<SupplierAnalyticsSnapshot, SupplierReportRange>(
      (ref, range) => ref.watch(supplierFinanceModuleProvider).analytics(range),
    );

/// Buyer reviews of the supplier's business.
final supplierReviewsProvider =
    FutureProvider.autoDispose<List<SupplierReview>>(
      (ref) => ref.watch(supplierFinanceModuleProvider).reviews(),
    );

/// The Reviews page header, derived from the same list the tiles render so the
/// average and the distribution can never disagree with the reviews below.
final supplierReviewSummaryProvider =
    Provider.autoDispose<AsyncValue<SupplierReviewSummary>>(
      (ref) => ref
          .watch(supplierReviewsProvider)
          .whenData(SupplierReviewSummary.fromReviews),
    );

// ── operations: delivery, settlement and supply ─────────────────────────────

/// Delivery, settlement, and supply requests always come from the backend API.
final supplierOperationsModuleProvider = Provider<SupplierOperationsService>(
  (ref) => ApiSupplierOperationsService(ref.watch(apiProvider)),
);

/// Consignments on the road, behind the Delivery page milestone tracks.
final supplierShipmentsProvider =
    FutureProvider.autoDispose<List<SupplierShipment>>(
      (ref) => ref.watch(supplierOperationsModuleProvider).shipments(),
    );

/// The settlement schedule behind the Delivery & Settlement ledger.
final supplierSettlementsProvider =
    FutureProvider.autoDispose<List<SupplierSettlementEvent>>(
      (ref) => ref.watch(supplierOperationsModuleProvider).settlements(),
    );

/// Counters for the Delivery & Settlement header.
final supplierDeliverySummaryProvider =
    FutureProvider.autoDispose<DeliverySettlementSummary>(
      (ref) => ref.watch(supplierOperationsModuleProvider).deliverySummary(),
    );

/// Supply requests behind the Supply Requests page.
final supplierSupplyRequestsProvider =
    FutureProvider.autoDispose<List<SupplierSupplyRequest>>(
      (ref) => ref.watch(supplierOperationsModuleProvider).supplyRequests(),
    );

/// The step-by-step supply flow shown at the top of the Supply Requests page.
final supplierSupplyProcessProvider =
    FutureProvider.autoDispose<List<SupplyProcessStep>>(
      (ref) => ref.watch(supplierOperationsModuleProvider).supplyProcess(),
    );

/// The Supply Requests header strip, derived from the same list the cards render
/// so the counts can never drift from the requests below them.
final supplierSupplySummaryProvider =
    Provider.autoDispose<AsyncValue<SupplyRequestSummary>>(
      (ref) => ref
          .watch(supplierSupplyRequestsProvider)
          .whenData(SupplyRequestSummary.fromRequests),
    );

// ── team & staff ───────────────────────────────────────────────────────────

/// Supplier staff records always come from the authenticated backend API.
final supplierTeamModuleProvider = Provider<SupplierTeamService>(
  (ref) => ApiSupplierTeamService(ref.watch(apiProvider)),
);

/// Everyone on the account, owners first.
final supplierTeamProvider = FutureProvider.autoDispose<List<TeamMember>>(
  (ref) => ref.watch(supplierTeamModuleProvider).members(),
);

/// Counters and per-permission coverage, derived from [supplierTeamProvider] so
/// the coverage panel always describes the roster on screen.
final supplierTeamSummaryProvider =
    Provider.autoDispose<AsyncValue<TeamSummary>>(
      (ref) =>
          ref.watch(supplierTeamProvider).whenData(TeamSummary.fromMembers),
    );
