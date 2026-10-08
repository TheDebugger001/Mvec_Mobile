import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../providers/admin_intelligence_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class AuditLogsScreen extends ConsumerWidget {
  const AuditLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN',
          title: 'Audit Logs',
          subtitle: 'Platform security audit trail.',
          actions: [
            OutlineMvButton(
              label: 'Download report',
              icon: 'arrow',
              onPressed: () => showMvSnack(context, 'Audit log export queued.', success: true),
            ),
          ],
        ),
        switch (logsAsync) {
          AsyncLoading() => const SizedBox(height: 160, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(auditLogsProvider),
          ),
          AsyncData(:final value) =>
            value.isEmpty
                ? const EmptyState(message: 'No audit activity recorded yet')
                : SmartTable(
                  columns: const [
                    MvColumn('id', 'ID'),
                    MvColumn('actor', 'Actor', flex: 2),
                    MvColumn('action', 'Action', flex: 2),
                    MvColumn('entity', 'Entity', flex: 2),
                    MvColumn('date', 'Date'),
                  ],
                  rows: value.map(_logRow).toList(),
                  pageSize: 8,
                  actionsLabel: 'Category',
                  rowActions: (row) => StatusChip(row['category']?.toString()),
                ),
          _ => const SizedBox(height: 160, child: LoadingState()),
        },
      ],
    );
  }

  /// Projects an audit record onto the columns above. Absent fields render as a
  /// dash rather than a placeholder value.
  Map<String, dynamic> _logRow(Map<String, dynamic> log) {
    final actor = log['actor'] ?? log['performedBy'] ?? log['user'] ?? log['admin'];
    return {
      'id': (log['id'] ?? log['eventId'] ?? '—').toString(),
      'actor': actor == null ? '—' : _nameOf(actor),
      'action': (log['action'] ?? log['event'] ?? '—').toString(),
      'entity': (log['entity'] ?? log['target'] ?? log['resource'] ?? '—').toString(),
      'category': (log['category'] ?? log['type'] ?? 'SYSTEM').toString().toUpperCase(),
      'date': _dateOf(log['createdAt'] ?? log['date'] ?? log['timestamp']),
    };
  }

  String _nameOf(Object? actor) =>
      actor is Map ? (actor['name'] ?? actor['email'] ?? '—').toString() : actor.toString();

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