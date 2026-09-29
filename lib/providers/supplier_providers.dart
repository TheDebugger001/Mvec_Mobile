import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/supplier.dart';
import '../services/supplier_service.dart';

final supplierServiceProvider = Provider<SupplierService>(
  (ref) => SupplierService(ref.watch(apiProvider)),
);

/// The signed-in supplier's own profile.
///
/// `GET /suppliers/me/profile` 404s while the account has not been onboarded
/// yet, which is a normal first-run state rather than a failure — so the 404
/// is translated into `null` and the UI offers onboarding instead of an error.
final supplierProfileProvider = FutureProvider<SupplierDetail?>((ref) async {
  try {
    return await ref.watch(supplierServiceProvider).profile();
  } on ApiException catch (e) {
    if (e.statusCode == 404) return null;
    rethrow;
  }
});

/// The supplier's wholesale catalogue, unpaginated as the backend returns it.
final supplierProductsProvider = FutureProvider<List<SupplierProduct>>(
  (ref) => ref.watch(supplierServiceProvider).products(),
);

/// Dashboard counters derived from the catalogue — the backend exposes no
/// metrics endpoint.
final supplierMetricsProvider = FutureProvider<SupplierMetrics>(
  (ref) async => SupplierMetrics.fromCatalog(
    await ref.watch(supplierProductsProvider.future),
  ),
);

/// Invalidates everything a profile or catalogue edit can change.
void refreshSupplierData(WidgetRef ref) {
  ref.invalidate(supplierProfileProvider);
  ref.invalidate(supplierProductsProvider);
  ref.invalidate(supplierMetricsProvider);
}
