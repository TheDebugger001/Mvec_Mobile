import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class MatchingScreen extends ConsumerWidget {
  const MatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · INTELLIGENCE',
          title: 'Supplier Matching',
          subtitle: 'AI-ranked supplier matches for marketplace orders.',
        ),
        SmartTable(
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
          rows: const [],
          actionsLabel: 'Refresh',
          pageSize: 8,
          rowActions: (_) => TableActionBtn(
            icon: 'arrow',
            tooltip: 'Refresh match',
            onPressed: () => showMvSnack(context, 'Match score refreshed', success: true),
          ),
        ),
      ],
    );
  }
}