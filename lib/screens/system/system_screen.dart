import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../providers/admin_intelligence_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class SystemScreen extends ConsumerWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN',
          title: 'System Administration',
          subtitle: 'Runtime platform settings.',
        ),
        switch (settingsAsync) {
          AsyncLoading() => const SizedBox(height: 160, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(systemSettingsProvider),
          ),
          AsyncData(:final value) =>
            value.isEmpty
                ? const EmptyState(message: 'No runtime settings reported yet')
                : SmartTable(
                  columns: const [
                    MvColumn('setting', 'Setting', flex: 2),
                    MvColumn('value', 'Value', flex: 2),
                    MvColumn('scope', 'Scope'),
                    MvColumn('changed', 'Last changed'),
                    MvColumn('owner', 'Owner'),
                  ],
                  rows: value.map(_settingRow).toList(),
                  pageSize: 8,
                  actionsLabel: 'Actions',
                  rowActions: (row) => TableActionBtn(
                    icon: 'check',
                    tooltip: 'Apply',
                    onPressed: () {
                      showMvSnack(context, 'Applied “${row['setting']}”.', success: true);
                    },
                  ),
                ),
          _ => const SizedBox(height: 160, child: LoadingState()),
        },
      ],
    );
  }

  /// Projects a runtime setting onto the columns above. Absent fields render as
  /// a dash rather than a placeholder.
  Map<String, dynamic> _settingRow(Map<String, dynamic> s) {
    return {
      'setting': _text(s['setting'] ?? s['key'] ?? s['name']),
      'value': _text(s['value']),
      'scope': _text(s['scope']),
      'changed': _dateOf(s['changed'] ?? s['updatedAt'] ?? s['lastChanged']),
      'owner': _text(s['owner'] ?? s['team']),
    };
  }

  String _text(Object? raw) => raw == null || raw.toString().isEmpty ? '—' : raw.toString();

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
