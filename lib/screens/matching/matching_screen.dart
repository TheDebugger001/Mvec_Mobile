import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json_fields.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/admin_intelligence_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class MatchingScreen extends ConsumerWidget {
  const MatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(supplierMatchesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · INTELLIGENCE',
          title: 'Supplier Matching',
          subtitle: 'AI-ranked supplier matches for marketplace orders.',
        ),
        switch (matchesAsync) {
          AsyncLoading() => const SizedBox(height: 160, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierMatchesProvider),
          ),
          AsyncData(:final value) =>
            value.isEmpty
                ? const EmptyState(message: 'No supplier matches yet')
                : SmartTable(
                  columns: const [
                    MvColumn('Supplier', 'Supplier', bold: true),
                    MvColumn('Category', 'Category'),
                    MvColumn('Score', 'Score'),
                    MvColumn('Price', 'Price'),
                    MvColumn('Stock', 'Stock'),
                    MvColumn('Reliability', 'Reliability'),
                    MvColumn('Distance', 'Distance'),
                    MvColumn('Status', 'Status'),
                  ],
                  rows: value.map(_matchRow).toList(),
                  actionsLabel: 'Refresh',
                  pageSize: 8,
                  rowActions: (_) => TableActionBtn(
                    icon: 'arrow',
                    tooltip: 'Refresh match',
                    onPressed: () => showMvSnack(context, 'Match score refreshed', success: true),
                  ),
                ),
          _ => const SizedBox(height: 160, child: LoadingState()),
        },
      ],
    );
  }

  /// Projects a match record onto the columns above. Percent columns omit the
  /// sign when the value is absent so a partial payload still reads cleanly.
  Map<String, dynamic> _matchRow(Map<String, dynamic> m) {
    final status =
        (stringField(m, spellings('status')) ?? 'PENDING').toUpperCase();
    return {
      'Supplier': cellText(m, ['supplier', ...spellings('supplierName'), ...spellings('name')]),
      'Category': cellText(m, spellings('category')),
      'Score': _percent(numField(m, ['score', ...spellings('matchScore')])),
      'Price': money(numField(m, ['price', ...spellings('unitPrice')])),
      'Stock': _stock(numField(m, [...spellings('stock'), ...spellings('quantity')])),
      'Reliability': _percent(
        numField(m, ['reliability', ...spellings('reliabilityScore')]),
      ),
      'Distance': cellText(m, ['distance', ...spellings('distanceKm')]),
      'Status': StatusChip(
        status,
        overrideColor: status == 'MATCHED' ? MvColors.successText : MvColors.warningText,
      ),
    };
  }

  String _percent(Object? raw) =>
      raw is num ? '${raw.round()}%' : (raw?.toString().isNotEmpty == true ? '$raw%' : '—');

  String _stock(Object? raw) =>
      raw is num ? raw.round().toString() : (raw?.toString().isNotEmpty == true ? raw.toString() : '—');
}
