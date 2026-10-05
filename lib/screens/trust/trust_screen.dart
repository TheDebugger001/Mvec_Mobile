import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class TrustScreen extends ConsumerWidget {
  const TrustScreen({super.key});

  Future<void> _showDetail(BuildContext context, Map<String, dynamic> t) async {
    await showMvDetailModal(
      context,
      title: 'TRUST PROFILE',
      children: [
        KeyValueGrid(entries: [
          MapEntry('Party', t['party'].toString()),
          MapEntry('Type', t['type'].toString()),
          MapEntry('Trust score', '${t['score']}/100'),
          MapEntry('Order completion', '${t['completion']}%'),
          MapEntry('Refund rate', '${t['refundRate']}%'),
          MapEntry('Dispute rate', '${t['disputeRate']}%'),
          MapEntry('Rating', '★ ${t['rating']}'),
          MapEntry('Trend', t['trend'].toString()),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · INTELLIGENCE',
          title: 'Trust Scores',
          subtitle: 'Trustworthiness metrics for marketplace parties.',
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: MetricCard(label: 'Avg trust score', value: '87', icon: 'shield')),
            const SizedBox(width: 12),
            Expanded(child: MetricCard(label: 'Low trust', value: '12', icon: 'users')),
            const SizedBox(width: 12),
            Expanded(child: MetricCard(label: 'High risk', value: '4', icon: 'bell')),
          ],
        ),
        const SizedBox(height: 14),
        SmartTable(
          columns: const [
            MvColumn('Party', 'Party', bold: true),
            MvColumn('Type', 'Type'),
            MvColumn('Score', 'Score'),
            MvColumn('Completion', 'Completion'),
            MvColumn('Refund rate', 'Refund rate'),
            MvColumn('Dispute rate', 'Dispute rate'),
            MvColumn('Rating', 'Rating'),
            MvColumn('Trend', 'Trend'),
          ],
          rows: const [],
          actionsLabel: 'Details',
          pageSize: 8,
          rowActions: (row) => TableActionBtn(
            icon: 'eye',
            tooltip: 'View profile',
            onPressed: () => _showDetail(context, row['_t'] as Map<String, dynamic>),
          ),
        ),
      ],
    );
  }
}