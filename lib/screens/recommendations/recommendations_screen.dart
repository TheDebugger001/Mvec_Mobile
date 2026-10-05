import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/admin_intelligence_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> signal,
  ) async {
    final id = (signal['id'] ?? '').toString();
    if (id.isEmpty) return;
    final next = signal['enabled'] != true;
    try {
      await ref.read(recommendationSignalToggleProvider)(id, enabled: next);
      if (context.mounted) {
        showMvSnack(context, 'Signal ${next ? 'enabled' : 'disabled'}.', success: true);
      }
    } catch (e) {
      if (context.mounted) showMvSnack(context, friendlyError(e));
    }
  }

  Widget _statusChip(bool enabled) {
    return StatusChip(
      enabled ? 'ENABLED' : 'DISABLED',
      overrideColor: enabled ? MvColors.successText : MvColors.neutralText,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signalsAsync = ref.watch(recommendationSignalsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · INTELLIGENCE',
          title: 'Recommendations',
          subtitle: 'Signals powering personalised recommendations.',
        ),
        DataCard(
          child: InfoBox(
            'These signals drive personalized product recommendations across the '
            'marketplace. Toggle a signal to enable or disable it.',
          ),
        ),
        const SizedBox(height: 14),
        switch (signalsAsync) {
          AsyncLoading() => const SizedBox(height: 160, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(recommendationSignalsProvider),
          ),
          AsyncData(:final value) =>
            value.isEmpty
                ? const EmptyState(message: 'No recommendation signals configured')
                : SmartTable(
                  columns: const [
                    MvColumn('Signal', 'Signal', bold: true),
                    MvColumn('Source', 'Source'),
                    MvColumn('Weight', 'Weight'),
                    MvColumn('Enabled', 'Enabled'),
                    MvColumn('Last updated', 'Last updated'),
                  ],
                  rows: value.map(_signalRow).toList(),
                  actionsLabel: 'Status',
                  pageSize: 8,
                  rowActions: (row) => TableActionBtn(
                    icon: 'check',
                    tooltip: 'Toggle signal',
                    onPressed: () => _toggle(
                      context,
                      ref,
                      row['_s'] as Map<String, dynamic>,
                    ),
                  ),
                ),
          _ => const SizedBox(height: 160, child: LoadingState()),
        },
      ],
    );
  }

  /// Projects a signal onto the columns above. Absent fields render as a dash.
  Map<String, dynamic> _signalRow(Map<String, dynamic> s) {
    return {
      'Signal': (s['signal'] ?? s['name'] ?? '—').toString(),
      'Source': (s['source'] ?? '—').toString(),
      'Weight': _weight(s['weight']),
      'Enabled': _statusChip(s['enabled'] == true),
      'Last updated': _dateOf(s['updated'] ?? s['updatedAt']),
      '_s': s,
    };
  }

  String _weight(Object? raw) {
    if (raw is num) return '${raw.round()}%';
    if (raw is String && raw.isNotEmpty) return raw;
    return '—';
  }

  String _dateOf(Object? raw) {
    if (raw is DateTime) return shortDate(raw);
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return shortDate(parsed);
      if (raw.isNotEmpty) return raw;
    }
    return '—';
  }
}