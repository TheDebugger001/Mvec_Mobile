import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class AuditLogsScreen extends ConsumerWidget {
  const AuditLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        SmartTable(
          columns: const [
            MvColumn('id', 'ID'),
            MvColumn('actor', 'Actor', flex: 2),
            MvColumn('action', 'Action', flex: 2),
            MvColumn('entity', 'Entity', flex: 2),
            MvColumn('date', 'Date'),
          ],
          rows: const [],
          pageSize: 8,
          actionsLabel: 'Category',
          rowActions: (row) => StatusChip(row['category']?.toString()),
        ),
      ],
    );
  }
}