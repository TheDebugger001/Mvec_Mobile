import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

final _signalsProvider = StateProvider<List<Map<String, dynamic>>>((ref) => const []);

class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  Widget _toggleChip(WidgetRef ref, Map<String, dynamic> signal) {
    final enabled = signal['enabled'] == true;
    final fg = enabled ? MvColors.successText : MvColors.neutralText;
    return InkWell(
      onTap: () {
        ref.read(_signalsProvider.notifier).state = [
          for (final s in ref.read(_signalsProvider))
            if (s['id'] == signal['id']) {...s, 'enabled': s['enabled'] != true} else s,
        ];
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: enabled ? MvColors.successBg : MvColors.neutralBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: fg.withValues(alpha: .35)),
        ),
        child: Text(
          enabled ? 'Enabled' : 'Disabled',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signals = ref.watch(_signalsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · INTELLIGENCE',
          title: 'Recommendations',
          subtitle: 'Signals powering personalised recommendations.',
        ),
        DataCard(
          child: InfoBox('These signals drive personalized product recommendations across the marketplace. Toggle a signal to enable or disable it.'),
        ),
        const SizedBox(height: 14),
        SmartTable(
          columns: const [
            MvColumn('Signal', 'Signal', bold: true),
            MvColumn('Source', 'Source'),
            MvColumn('Weight', 'Weight'),
            MvColumn('Enabled', 'Enabled'),
            MvColumn('Last updated', 'Last updated'),
          ],
          rows: [
            for (final s in signals)
              {
                'Signal': s['signal']?.toString() ?? '—',
                'Source': s['source']?.toString() ?? '—',
                'Weight': '${s['weight']}%',
                'Enabled': StatusChip(s['enabled'] == true ? 'ENABLED' : 'DISABLED', overrideColor: s['enabled'] == true ? MvColors.successText : MvColors.neutralText),
                'Last updated': s['updated']?.toString() ?? '—',
                '_s': s,
              },
          ],
          actionsLabel: 'Status',
          pageSize: 8,
          rowActions: (row) => _toggleChip(ref, row['_s'] as Map<String, dynamic>),
        ),
      ],
    );
  }
}