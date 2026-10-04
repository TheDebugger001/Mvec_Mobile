import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../models/supplier_finance.dart';
import '../services/supplier_finance_service.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_finance_widgets.dart';

/// Supplier earnings, escrow, payout history and withdrawal requests.
///
/// Mirrors the vendor "Sales & earnings" screen (`VendorSalesScreen`) so both
/// portals read the same way: headline balances, an earnings chart, the money
/// ledger and the payout list, with the request form reachable from the page
/// head.
class SupplierPaymentsScreen extends ConsumerWidget {
  const SupplierPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(supplierFinanceSummaryProvider);
    final ledgerAsync = ref.watch(supplierLedgerProvider);
    final payoutsAsync = ref.watch(supplierPayoutsProvider);
    final fallback = ref.watch(supplierFinanceModuleProvider).fallbackReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'PAYMENTS',
          title: 'Earnings & payouts',
          subtitle:
              'Withdraw what MVEC has cleared for you, and follow every order '
              'from escrow to your bank.',
          actions: [
            FilledButton.icon(
              onPressed:
                  summaryAsync.valueOrNull == null
                      ? null
                      : () => _requestPayout(
                        context,
                        ref,
                        summaryAsync.valueOrNull!,
                      ),
              icon: const Icon(Icons.south_west, size: 17),
              label: const Text('Request payout'),
            ),
          ],
        ),
        if (fallback != null) ...[
          InfoBox(fallback, icon: 'bell'),
          const SizedBox(height: 14),
        ],
        switch (summaryAsync) {
          AsyncLoading() => const SizedBox(height: 170, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierFinanceSummaryProvider),
          ),
          AsyncData(:final value) => _summary(context, value),
          _ => const SizedBox(height: 170, child: LoadingState()),
        },
        const SizedBox(height: 14),
        switch (ledgerAsync) {
          AsyncLoading() => const SizedBox(height: 170, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierLedgerProvider),
          ),
          AsyncData(:final value) => DataCard(
            title: 'Recent money movements',
            subtitle:
                'Wholesale orders, commission, escrow holds and releases, and '
                'withdrawals.',
            child:
                value.isEmpty
                    ? const EmptyState(message: 'No transactions to show yet.')
                    : Column(
                      children: [
                        for (var i = 0; i < value.length && i < 6; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: context.mv.border),
                          SupplierLedgerTile(entry: value[i]),
                        ],
                      ],
                    ),
          ),
          _ => const SizedBox(height: 170, child: LoadingState()),
        },
        const SizedBox(height: 14),
        switch (payoutsAsync) {
          AsyncLoading() => const SizedBox(height: 100, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierPayoutsProvider),
          ),
          AsyncData(:final value) => DataCard(
            title: 'Payout requests',
            subtitle:
                'Pending requests are reserved from your available balance.',
            child:
                value.isEmpty
                    ? const EmptyState(
                      message:
                          'No payout requests yet. Request one to move your '
                          'cleared earnings.',
                    )
                    : Column(
                      children: [
                        for (final payout in value)
                          SupplierPayoutRow(payout: payout),
                      ],
                    ),
          ),
          _ => const SizedBox(height: 100, child: LoadingState()),
        },
      ],
    );
  }

  Widget _summary(BuildContext context, SupplierFinanceSummary value) {
    final metrics = [
      SupplierFinanceMetric(
        label: 'Gross sales',
        amount: value.grossSales,
        icon: 'chart',
      ),
      SupplierFinanceMetric(
        label: 'Net earnings',
        amount: value.netEarnings,
        icon: 'wallet',
      ),
      SupplierFinanceMetric(
        label: 'Held in escrow',
        amount: value.escrowHeld,
        icon: 'shield',
      ),
      SupplierFinanceMetric(
        label: 'Available to withdraw',
        amount: value.availablePayout,
        icon: 'arrow',
        emphasis: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 720 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: metric),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        DataCard(
          title: 'Net earnings · last 30 days',
          subtitle:
              'Commission deducted: ${money(value.commission)} · '
              '${(value.commissionRate * 100).toStringAsFixed(0)}% wholesale rate',
          trailing: Text(
            supplierDelta(value.earningsDelta),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: supplierDeltaColor(value.earningsDelta),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SupplierEarningsChart(series: value.series),
              if (value.lastPayoutAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Last payout landed ${shortDateTime(value.lastPayoutAt)} · '
                  '${money(value.pendingPayouts)} still processing',
                  style: TextStyle(fontSize: 11, color: context.mv.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const InfoBox(
          'MVEC holds each order in escrow until delivery is confirmed. Only '
          'the released amount can be withdrawn, and a pending request is '
          'reserved so it cannot be requested twice.',
          icon: 'shield',
        ),
      ],
    );
  }

  Future<void> _requestPayout(
    BuildContext context,
    WidgetRef ref,
    SupplierFinanceSummary summary,
  ) async {
    // Nothing cleared yet: the form would reject every amount, so say why
    // instead of opening a dialog the supplier cannot complete.
    if (summary.availablePayout < kMinSupplierPayoutAmount) {
      showMvSnack(
        context,
        'You have ${money(summary.availablePayout)} available. MVEC clears '
        'funds once an order is delivered.',
      );
      return;
    }

    final request = await showDialog<_PayoutFormResult>(
      context: context,
      builder: (_) => _PayoutRequestDialog(summary: summary),
    );
    if (request == null || !context.mounted) return;

    try {
      await ref
          .read(supplierFinanceModuleProvider)
          .requestPayout(
            amount: request.amount,
            method: request.method,
            destination: request.destination,
            note: request.note,
          );
      ref.invalidate(supplierFinanceSummaryProvider);
      ref.invalidate(supplierLedgerProvider);
      ref.invalidate(supplierPayoutsProvider);
      if (context.mounted) {
        showMvSnack(context, 'Payout request submitted', success: true);
      }
    } catch (error) {
      if (context.mounted) showMvSnack(context, friendlyError(error));
    }
  }
}

/// What the payout form hands back on submit.
typedef _PayoutFormResult =
    ({
      num amount,
      SupplierPayoutMethod method,
      String destination,
      String note,
    });

/// The withdrawal form.
///
/// A stateful dialog rather than a `StatefulBuilder` so it owns its controllers
/// and disposes them with the route, instead of the page disposing them while
/// the dialog is still animating out.
class _PayoutRequestDialog extends StatefulWidget {
  const _PayoutRequestDialog({required this.summary});

  final SupplierFinanceSummary summary;

  @override
  State<_PayoutRequestDialog> createState() => _PayoutRequestDialogState();
}

class _PayoutRequestDialogState extends State<_PayoutRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _destination = TextEditingController();
  final _note = TextEditingController();
  SupplierPayoutMethod _method = SupplierPayoutMethod.mtnMomo;

  double get _available => widget.summary.availablePayout.toDouble();

  @override
  void dispose() {
    _amount.dispose();
    _destination.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(context, (
      amount: num.parse(_amount.text.replaceAll(',', '').trim()),
      method: _method,
      destination: _destination.text.trim(),
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request a payout'),
      content: SizedBox(
        width: 420,
        // Scrollable so the form still fits a short phone viewport.
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Available: ${money(_available)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${money(widget.summary.pendingPayouts)} is reserved by '
                  'requests already processing.',
                  style: TextStyle(fontSize: 11, color: context.mv.textMuted),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount (RWF)',
                    helperText: 'Use "max" to withdraw it all',
                    border: const OutlineInputBorder(),
                    suffixIcon: TextButton(
                      onPressed:
                          () => _amount.text = _available.toStringAsFixed(0),
                      child: const Text('Max'),
                    ),
                  ),
                  validator: (value) {
                    final parsed = num.tryParse(
                      value?.replaceAll(',', '').trim() ?? '',
                    );
                    if (parsed == null || parsed < kMinSupplierPayoutAmount) {
                      return 'Minimum payout is '
                          '${money(kMinSupplierPayoutAmount)}';
                    }
                    if (parsed > _available) {
                      return 'Amount exceeds your available balance';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<SupplierPayoutMethod>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Payout method',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final option in SupplierPayoutMethod.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged:
                      (value) => setState(() => _method = value ?? _method),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _destination,
                  decoration: InputDecoration(
                    labelText:
                        _method == SupplierPayoutMethod.bankTransfer
                            ? 'Bank account / IBAN'
                            : 'Mobile Money phone number',
                    helperText: _method.hint,
                    border: const OutlineInputBorder(),
                  ),
                  validator:
                      (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a payout destination'
                              : null,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _method.settlementNote,
                  style: TextStyle(fontSize: 11, color: context.mv.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Submit request')),
      ],
    );
  }
}
