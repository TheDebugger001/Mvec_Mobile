import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_intelligence_service.dart';

/// Providers for the admin intelligence screens.
///
/// Split from `admin_providers.dart` for the same reason as the service: one
/// file per feature area, so unrelated admin work does not collide here.
///
/// Every list degrades to empty while its route is unshipped, so the screen
/// renders its empty state rather than an error.
final auditLogsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(adminIntelligenceServiceProvider).auditLogs(),
);

final supplierMatchesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(adminIntelligenceServiceProvider).supplierMatches(),
);

final trustScoresProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(adminIntelligenceServiceProvider).trustScores(),
);

final systemSettingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(adminIntelligenceServiceProvider).systemSettings(),
);

final recommendationSignalsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref.watch(adminIntelligenceServiceProvider).recommendationSignals(),
    );

/// Flips one recommendation signal and refreshes the list it came from.
final recommendationSignalToggleProvider =
    Provider<Future<void> Function(String id, {required bool enabled})>(
      (ref) => (String id, {required bool enabled}) async {
        await ref
            .read(adminIntelligenceServiceProvider)
            .patchRecommendationSignal(id, enabled: enabled);
        ref.invalidate(recommendationSignalsProvider);
      },
    );