import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json_fields.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/admin_intelligence_providers.dart';
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
          MapEntry('Party', _text(stringField(t, ['party', ...spellings('name')]))),
          MapEntry('Type', _text(stringField(t, spellings('type')))),
          MapEntry('Trust score', _text(stringField(t, ['score', ...spellings('trustScore')]))),
          MapEntry('Order completion', _text(stringField(t, ['completion', ...spellings('completionRate')]))),
          MapEntry('Refund rate', _text(stringField(t, spellings('refundRate')))),
          MapEntry('Dispute rate', _text(stringField(t, spellings('disputeRate')))),
          MapEntry('Rating', _text(stringField(t, spellings('rating')))),
          MapEntry('Trend', _text(stringField(t, spellings('trend')))),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoresAsync = ref.watch(trustScoresProvider);
    final body = switch (scoresAsync) {
      AsyncData(:final value) => _body(context, value),
      AsyncError(:final error) => [
        ErrorState(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(trustScoresProvider),
        ),
      ],
      _ => const [SizedBox(height: 180, child: LoadingState())],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · INTELLIGENCE',
          title: 'Trust Scores',
          subtitle: 'Trustworthiness metrics for marketplace parties.',
        ),
        const SizedBox(height: 4),
        ...body,
      ],
    );
  }

  /// The headline metrics are derived from the loaded rows so the cards can never
  /// contradict the table beneath them.
  List<Widget> _body(BuildContext context, List<Map<String, dynamic>> scores) {
    if (scores.isEmpty) {
      return [
        MetricCard(label: 'Avg trust score', value: '—', icon: 'shield'),
        MetricCard(label: 'Low trust', value: '—', icon: 'users'),
        MetricCard(label: 'High risk', value: '—', icon: 'bell'),
        const SizedBox(height: 14),
        const EmptyState(message: 'No trust scores calculated yet'),
      ];
    }
    final values = scores
        .map((t) => _number(t['score'] ?? t['trustScore']))
        .whereType<num>()
        .toList();
    final average = values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
    final lowTrust = values.where((v) => v < 70).length;
    final highRisk = scores.where((t) => (t['trend']).toString().toUpperCase() == 'NEGATIVE').length;

    return [
      Row(
        children: [
          Expanded(
            child: MetricCard(
              label: 'Avg trust score',
              value: average == null ? '—' : average.toStringAsFixed(1),
              icon: 'shield',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: MetricCard(label: 'Low trust', value: '$lowTrust', icon: 'users')),
          const SizedBox(width: 12),
          Expanded(child: MetricCard(label: 'High risk', value: '$highRisk', icon: 'bell')),
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
        rows: scores.map(_trustRow).toList(),
        actionsLabel: 'Details',
        pageSize: 8,
        rowActions: (row) => TableActionBtn(
          icon: 'eye',
          tooltip: 'View profile',
          onPressed: () => _showDetail(context, row['_t'] as Map<String, dynamic>),
        ),
      ),
    ];
  }

  /// Projects a trust record onto the columns above. Absent metrics show a dash.
  Map<String, dynamic> _trustRow(Map<String, dynamic> t) {
    final trend = stringField(t, spellings('trend'))?.toUpperCase() ?? 'NEUTRAL';
    return {
      'Party': _text(stringField(t, ['party', ...spellings('name')])),
      'Type': _text(stringField(t, spellings('type')) ?? stringField(t, spellings('role'))),
      'Score': _plain(numField(t, ['score', ...spellings('trustScore')])),
      'Completion': _percent(
        numField(t, ['completion', ...spellings('completionRate')]),
      ),
      'Refund rate': _percent(numField(t, spellings('refundRate'))),
      'Dispute rate': _percent(numField(t, spellings('disputeRate'))),
      'Rating': _rating(numField(t, spellings('rating'))),
      'Trend': StatusChip(
        trend,
        overrideColor: trend == 'POSITIVE' ? MvColors.successText : MvColors.errorText,
      ),
      '_t': t,
    };
  }

  num? _number(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw);
    return null;
  }

  String _text(Object? raw) => raw == null || raw.toString().isEmpty ? '—' : raw.toString();

  String _plain(Object? raw) {
    final value = _number(raw);
    return value == null ? _text(raw) : value.round().toString();
  }

  String _percent(Object? raw) {
    final value = _number(raw);
    return value == null ? '—' : '${value.round()}%';
  }

  String _rating(Object? raw) {
    final value = _number(raw);
    return value == null ? '—' : '★ ${value.toStringAsFixed(1)}';
  }
}
