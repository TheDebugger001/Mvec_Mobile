import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../models/supplier_finance.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_finance_widgets.dart';

/// The supplier money ledger: every wholesale order, commission, escrow hold
/// and release, refund and withdrawal, filterable by kind and searchable by
/// order number.
class SupplierTransactionsScreen extends ConsumerStatefulWidget {
  const SupplierTransactionsScreen({super.key});

  @override
  ConsumerState<SupplierTransactionsScreen> createState() =>
      _SupplierTransactionsScreenState();
}

class _SupplierTransactionsScreenState
    extends ConsumerState<SupplierTransactionsScreen> {
  SupplierLedgerKind? _kind;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(supplierLedgerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'TRANSACTIONS',
          title: 'Money ledger',
          subtitle:
              'Every movement on your wholesale account, from order to payout.',
        ),
        switch (entriesAsync) {
          AsyncLoading() => const SizedBox(height: 220, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierLedgerProvider),
          ),
          AsyncData(:final value) => _ledger(context, _filter(value), value),
          _ => const SizedBox(height: 220, child: LoadingState()),
        },
      ],
    );
  }

  /// Applies the kind filter and the free-text search. An empty query with no
  /// kind selected returns the untouched list, so the common case costs nothing.
  List<SupplierLedgerEntry> _filter(List<SupplierLedgerEntry> entries) {
    final query = _query.trim().toLowerCase();
    return entries.where((entry) {
      if (_kind != null && entry.kind != _kind) return false;
      if (query.isEmpty) return true;
      return entry.description.toLowerCase().contains(query) ||
          (entry.orderNumber ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Widget _ledger(
    BuildContext context,
    List<SupplierLedgerEntry> rows,
    List<SupplierLedgerEntry> all,
  ) {
    final moneyIn = all
        .where((e) => e.isCredit)
        .fold<num>(0, (sum, e) => sum + e.amount);
    final moneyOut = all
        .where((e) => e.kind.sign < 0)
        .fold<num>(0, (sum, e) => sum + e.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DataCard(
          title: 'Ledger totals',
          subtitle: '${plural(all.length, 'entry')} on this account.',
          child: KeyValueGrid(
            entries: [
              MapEntry('Money in', money(moneyIn)),
              MapEntry('Money out', money(moneyOut)),
              MapEntry(
                'Held in escrow',
                money(
                  all
                      .where((e) => e.kind == SupplierLedgerKind.escrowHold)
                      .fold<num>(0, (sum, e) => sum + e.amount),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Filter',
          subtitle: 'Narrow the ledger by movement type or order number.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'All movements',
                    selected: _kind == null,
                    onTap: () => setState(() => _kind = null),
                  ),
                  for (final kind in SupplierLedgerKind.values)
                    _FilterChip(
                      label: kind.label,
                      selected: _kind == kind,
                      onTap: () => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Search by order number or description…',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Entries',
          subtitle:
              rows.length == all.length
                  ? '${plural(rows.length, 'movement')} shown.'
                  : '${rows.length} of ${all.length} movements match your filter.',
          child:
              rows.isEmpty
                  ? const EmptyState(message: 'No movements match this filter.')
                  : Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: context.mv.border),
                        SupplierLedgerTile(entry: rows[i]),
                      ],
                    ],
                  ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: context.mv.accentDeep,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: selected ? context.mv.onAccent : context.mv.text,
      ),
      showCheckmark: false,
    );
  }
}
