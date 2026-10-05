import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/party.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/smart_table.dart';

class AcquisitionScreen extends ConsumerWidget {
  const AcquisitionScreen({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVendor = type == 'vendor';
    final query = const PartyQuery(page: 1);
    final pipelineAsync =
        isVendor
            ? ref.watch(vendorsProvider(query))
            : ref.watch(suppliersProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'MVEC GROWTH',
          title: isVendor ? 'Vendor Acquisition' : 'Supplier Acquisition',
          subtitle: 'Value proposition and acquisition pipeline.',
          actions: const [GradientButton(label: 'Export pipeline', icon: 'arrow')],
        ),
        DataCard(
          title: 'Value proposition',
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Step('1', 'Register & onboard'),
              _Step('2', 'Get verified'),
              _Step('3', 'List your catalog'),
              _Step('4', 'Start selling'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DataCard(
          title: 'Acquisition pipeline',
          child: switch (pipelineAsync) {
            AsyncLoading() => const SizedBox(height: 120, child: LoadingState()),
            AsyncError(:final error) => ErrorState(
              message: friendlyError(error),
              onRetry:
                  isVendor
                      ? () => ref.invalidate(vendorsProvider(query))
                      : () => ref.invalidate(suppliersProvider(query)),
            ),
            AsyncData(:final value) =>
              value.items.isEmpty
                  ? const EmptyState(message: 'No pipeline records found')
                  : SmartTable(
                      columns: const [
                        MvColumn('business', 'Business', bold: true),
                        MvColumn('contact', 'Contact'),
                        MvColumn('category', 'Category'),
                        MvColumn('stage', 'Stage'),
                        MvColumn('next', 'Next step'),
                      ],
                      rows: _rows(value.items),
                      actionsLabel: '',
                      csvFileName:
                          isVendor ? 'vendor-pipeline' : 'supplier-pipeline',
                    ),
            _ => const SizedBox(height: 120, child: LoadingState()),
          },
        ),
      ],
    );
  }

  /// Maps the API's party records onto the pipeline columns. The "next step" is
  /// derived from the same verification status the API reports, so the column can
  /// never disagree with the stage beside it.
  static List<Map<String, dynamic>> _rows(List<PartyRecord> parties) =>
      parties.map((party) {
        final verification = party.verificationStatus ?? '';
        final stage = verification.isEmpty ? 'Invited' : _titleCase(verification);
        return <String, dynamic>{
          'business': party.name ?? '—',
          'contact': party.email ?? party.phone ?? '—',
          'category': party.category ?? 'General',
          'stage': StatusChip(stage),
          'next': _nextStep(stage),
        };
      }).toList();

  static String _titleCase(String value) {
    final lower = value.toLowerCase();
    if (lower.isEmpty) return lower;
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  static String _nextStep(String stage) => switch (stage.toUpperCase()) {
    'VERIFIED' => 'Onboard catalog',
    'ONBOARDING' || 'PENDING' => 'Complete verification',
    'APPLIED' => 'Schedule verification',
    'REJECTED' => 'Review documents',
    _ => 'Send intro call',
  };
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.label);

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MvColors.metricIconBg, shape: BoxShape.circle),
            child: Text(
              number,
              style: const TextStyle(fontFamily: 'Manrope', fontSize: 11, fontWeight: FontWeight.w800, color: MvColors.primaryDeep),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}