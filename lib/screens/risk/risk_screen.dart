import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

String _shortId(String? id) {
  if (id == null || id.isEmpty) return '—';
  return id.length <= 8 ? id.toUpperCase() : '${id.substring(0, 8).toUpperCase()}…';
}

Color _riskColor(Object? risk) {
  switch ((risk ?? '').toString().toUpperCase()) {
    case 'HIGH':
      return MvColors.errorText;
    case 'MEDIUM':
      return MvColors.warningText;
    case 'LOW':
      return MvColors.successText;
    default:
      return MvColors.neutralText;
  }
}

class RiskScreen extends ConsumerWidget {
  const RiskScreen({super.key});

  Future<void> _showDetail(BuildContext context, WidgetRef ref, Map<String, dynamic> report) async {
    await showMvDetailModal(
      context,
      title: 'RISK REPORT',
      children: [
        KeyValueGrid(entries: [
          MapEntry('Risk ID', _shortId(report['id']?.toString())),
          MapEntry('Area', report['area']?.toString() ?? '—'),
          MapEntry('Party', report['party']?.toString() ?? '—'),
          MapEntry('Signal', report['signal']?.toString() ?? '—'),
          MapEntry('Risk', report['risk']?.toString() ?? '—'),
          MapEntry('Status', report['status']?.toString() ?? '—'),
          MapEntry('Submitted', report['submitted']?.toString() ?? '—'),
        ]),
      ],
      footer: _ResolveFooter(
        ref: ref,
        report: report,
        onResolved: () {
          if (context.mounted) Navigator.pop(context);
          if (context.mounted) showMvSnack(context, 'Report marked as resolved', success: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(abuseReportsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPER ADMIN · SAFETY',
          title: 'Risk & Abuse Reports',
          subtitle: 'Monitor suspicious activity across the platform.',
        ),
        reportsAsync.when(
          data: (list) {
            final reports = list;
            final highRisk = reports.where((r) => (r['risk'] ?? '').toString().toUpperCase() == 'HIGH').length;
            final underReview = reports
                .where((r) => {'REVIEW', 'UNDER_REVIEW', 'INVESTIGATE', 'PENDING', 'OPEN'}.contains((r['status'] ?? '').toString().toUpperCase()))
                .length;
            final monitoring =
                reports.where((r) => (r['status'] ?? '').toString().toUpperCase() == 'MONITORING').length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: MetricCard(label: 'High risk', value: '$highRisk', icon: 'bell')),
                    const SizedBox(width: 12),
                    Expanded(child: MetricCard(label: 'Under review', value: '$underReview', icon: 'eye')),
                    const SizedBox(width: 12),
                    Expanded(child: MetricCard(label: 'Monitoring', value: '$monitoring', icon: 'chart')),
                  ],
                ),
                const SizedBox(height: 14),
                SmartTable(
                  columns: const [
                    MvColumn('Risk ID', 'Risk ID', bold: true),
                    MvColumn('Area', 'Area'),
                    MvColumn('Party', 'Party'),
                    MvColumn('Signal', 'Signal'),
                    MvColumn('Risk', 'Risk'),
                    MvColumn('Status', 'Status'),
                  ],
                  rows: [
                    for (final r in reports)
                      {
                        'Risk ID': _shortId(r['id']?.toString()),
                        'Area': r['area']?.toString() ?? '—',
                        'Party': r['party']?.toString() ?? '—',
                        'Signal': r['signal']?.toString() ?? '—',
                        'Risk': StatusChip(r['risk']?.toString(), overrideColor: _riskColor(r['risk'])),
                        'Status': StatusChip(r['status']?.toString()),
                        '_r': r,
                      },
                  ],
                  actionsLabel: 'Details',
                  pageSize: 8,
                  rowActions: (row) => TableActionBtn(
                    icon: 'eye',
                    tooltip: 'View report',
                    onPressed: () => _showDetail(context, ref, row['_r'] as Map<String, dynamic>),
                  ),
                ),
              ],
            );
          },
          error: (e, _) => ErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(abuseReportsProvider)),
          loading: () => const LoadingState(),
        ),
      ],
    );
  }
}

class _ResolveFooter extends StatefulWidget {
  const _ResolveFooter({required this.ref, required this.report, required this.onResolved});
  final WidgetRef ref;
  final Map<String, dynamic> report;
  final VoidCallback onResolved;

  @override
  State<_ResolveFooter> createState() => _ResolveFooterState();
}

class _ResolveFooterState extends State<_ResolveFooter> {
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() => _busy = true);
    try {
      await widget.ref.read(platformServiceProvider).patchAbuseReport(
            widget.report['id'].toString(),
            'RESOLVED',
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      widget.ref.invalidate(abuseReportsProvider);
      widget.onResolved();
    } catch (e) {
      if (mounted) showMvSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _notes,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'Admin notes (optional)…'),
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: _busy ? 'Resolving…' : 'Mark resolved',
          icon: 'check',
          expanded: true,
          onPressed: _busy ? null : _resolve,
        ),
      ],
    );
  }
}