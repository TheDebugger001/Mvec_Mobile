import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class SystemScreen extends ConsumerWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN',
          title: 'System Administration',
          subtitle: 'Runtime platform settings.',
        ),
        SmartTable(
          columns: const [
            MvColumn('setting', 'Setting', flex: 2),
            MvColumn('value', 'Value', flex: 2),
            MvColumn('scope', 'Scope'),
            MvColumn('changed', 'Last changed'),
            MvColumn('owner', 'Owner'),
          ],
          rows: const [],
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
      ],
    );
  }
}