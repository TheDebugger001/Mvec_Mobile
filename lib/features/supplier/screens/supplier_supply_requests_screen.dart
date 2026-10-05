import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../data/supplier_workspace.dart';
import '../models/supplier_operations.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_ops_widgets.dart';

/// Inbound stock requests, and the step-by-step flow behind them.
///
/// The guide at the top is the point of the page: a supplier can see exactly
/// what happens after they press submit, who is responsible at each step and how
/// long it normally takes. Below it, each request shows where it has got to and
/// offers the two lifecycle actions that still make sense — withdraw while MVEC
/// has not committed the goods, resubmit after a withdrawal.
class SupplierSupplyRequestsScreen extends ConsumerStatefulWidget {
  const SupplierSupplyRequestsScreen({super.key});

  @override
  ConsumerState<SupplierSupplyRequestsScreen> createState() =>
      _SupplierSupplyRequestsScreenState();
}

class _SupplierSupplyRequestsScreenState
    extends ConsumerState<SupplierSupplyRequestsScreen> {
  _RequestFilter _filter = _RequestFilter.open;

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(supplierSupplyRequestsProvider);
    final summaryAsync = ref.watch(supplierSupplySummaryProvider);
    final processAsync = ref.watch(supplierSupplyProcessProvider);
    final fallback = ref.watch(supplierOperationsModuleProvider).fallbackReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'OPERATIONS',
          title: 'Supply requests',
          subtitle:
              'Ask MVEC to source stock for your store, and follow it through '
              'every step.',
          actions: [
            FilledButton.icon(
              onPressed: () => _openCreate(context),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('New request'),
            ),
          ],
        ),
        if (fallback != null) ...[
          InfoBox(fallback, icon: 'bell'),
          const SizedBox(height: 14),
        ],
        switch (summaryAsync) {
          AsyncLoading() => const SizedBox(height: 110, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierSupplyRequestsProvider),
          ),
          AsyncData(:final value) => _metrics(context, value),
          _ => const SizedBox(height: 110, child: LoadingState()),
        },
        const SizedBox(height: 16),
        DataCard(
          title: 'How a supply request works',
          subtitle:
              '${kSupplyProcessSteps.length} steps · nothing is charged until '
              'you accept the quote',
          child: switch (processAsync) {
            AsyncLoading() => const SizedBox(
              height: 140,
              child: LoadingState(),
            ),
            AsyncError(:final error) => ErrorState(
              message: friendlyError(error),
              onRetry: () => ref.invalidate(supplierSupplyProcessProvider),
            ),
            AsyncData(:final value) => SupplyProcessTimeline(steps: value),
            _ => const SizedBox(height: 140, child: LoadingState()),
          },
        ),
        const SizedBox(height: 18),
        Text('Your requests', style: context.mvH1.copyWith(fontSize: 16)),
        const SizedBox(height: 10),
        _chips(context),
        const SizedBox(height: 12),
        switch (requestsAsync) {
          AsyncLoading() => const SizedBox(height: 170, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierSupplyRequestsProvider),
          ),
          AsyncData(:final value) => _requests(context, value),
          _ => const SizedBox(height: 170, child: LoadingState()),
        },
      ],
    );
  }

  Widget _metrics(BuildContext context, SupplyRequestSummary value) {
    return SupplierOpsMetricRow(
      metrics: [
        SupplierOpsMetric(
          label: 'Open requests',
          value: '${value.open}',
          icon: 'cart',
          caption:
              value.oldestOpenDays == 0
                  ? 'nothing waiting'
                  : 'oldest ${value.oldestOpenDays}d old',
        ),
        SupplierOpsMetric(
          label: 'Awaiting MVEC',
          value: '${value.awaitingAction}',
          icon: 'eye',
          caption: 'submitted or under review',
        ),
        SupplierOpsMetric(
          label: 'In progress',
          value: '${value.inProgress}',
          icon: 'box',
          caption: 'approved to in transit',
        ),
        SupplierOpsMetric(
          label: 'Open pipeline',
          value: money(value.pipelineValue),
          icon: 'wallet',
          caption: '${plural(value.closed, 'closed request')} to date',
        ),
      ],
    );
  }

  Widget _chips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in _RequestFilter.values)
          ChoiceChip(
            label: Text(option.label),
            selected: option == _filter,
            onSelected: (_) => setState(() => _filter = option),
            selectedColor: context.mv.accentDeep,
            labelStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _filter == option ? context.mv.onAccent : context.mv.text,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }

  Widget _requests(BuildContext context, List<SupplierSupplyRequest> requests) {
    final visible = requests.where(_filter.matches).toList();
    if (visible.isEmpty) {
      return DataCard(
        child: EmptyState(
          message:
              _filter == _RequestFilter.open
                  ? 'No open requests. Raise one and MVEC will source the '
                      'stock for you.'
                  : 'No requests in this view.',
        ),
      );
    }
    return Column(
      children: [
        for (final request in visible) ...[
          SupplyRequestCard(
            request: request,
            onTap: () => _openDetail(context, request),
            onCancel:
                request.canCancel
                    ? () => _confirmCancel(context, request)
                    : null,
            onResubmit:
                request.canResubmit ? () => _resubmit(context, request) : null,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ── actions ──────────────────────────────────────────────────────────────

  void _openCreate(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _SupplyRequestForm(),
    );
  }

  void _openDetail(BuildContext context, SupplierSupplyRequest request) {
    showMvDetailModal(
      context,
      title: '${request.reference} · ${request.status.label}',
      children: [
        StatusChip(request.status.slug),
        const SizedBox(height: 14),
        KeyValueGrid(
          entries: [
            MapEntry('Items', '${request.lines.length} line(s)'),
            MapEntry('Units', '${request.totalUnits}'),
            MapEntry('Value', money(request.totalValue)),
            MapEntry('Raised', shortDate(request.createdAt)),
            MapEntry(
              'Needed by',
              request.neededBy == null ? '—' : shortDate(request.neededBy!),
            ),
            if (request.updatedAt != null)
              MapEntry('Last update', shortDate(request.updatedAt!)),
          ],
        ),
        if (request.note != null) ...[
          const SizedBox(height: 16),
          Text('Your note', style: context.mvH1.copyWith(fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            request.note!,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: context.mv.text,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Items', style: context.mvH1.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        for (final line in request.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${line.product} · ${line.category}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.mv.text,
                    ),
                  ),
                ),
                Text(
                  '${line.units} ${line.unit} · ${money(line.lineTotal)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.mv.textMuted,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text('History', style: context.mvH1.copyWith(fontSize: 13)),
        const SizedBox(height: 10),
        SupplyRequestTimeline(request: request),
      ],
      footer:
          request.canResubmit
              ? GradientButton(
                label: 'Resubmit request',
                icon: 'plus',
                expanded: true,
                onPressed: () {
                  Navigator.pop(context);
                  _resubmit(context, request);
                },
              )
              : null,
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    SupplierSupplyRequest request,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _WithdrawDialog(),
    );
    if (reason == null || !context.mounted) return;

    try {
      await ref
          .read(supplierOperationsModuleProvider)
          .cancelSupplyRequest(request.id, reason);
      ref.invalidate(supplierSupplyRequestsProvider);
      if (context.mounted) {
        showMvSnack(context, '${request.reference} withdrawn', success: true);
      }
    } catch (error) {
      if (context.mounted) showMvSnack(context, friendlyError(error));
    }
  }

  Future<void> _resubmit(
    BuildContext context,
    SupplierSupplyRequest request,
  ) async {
    try {
      final next = await ref
          .read(supplierOperationsModuleProvider)
          .resubmitSupplyRequest(request.id);
      ref.invalidate(supplierSupplyRequestsProvider);
      if (context.mounted) {
        showMvSnack(context, 'Resubmitted as ${next.reference}', success: true);
      }
    } catch (error) {
      if (context.mounted) showMvSnack(context, friendlyError(error));
    }
  }
}

/// How the request list is narrowed.
enum _RequestFilter {
  open('Open'),
  all('All'),
  closed('Closed');

  const _RequestFilter(this.label);

  final String label;

  bool matches(SupplierSupplyRequest request) => switch (this) {
    _RequestFilter.open => request.isOpen,
    _RequestFilter.all => true,
    _RequestFilter.closed => !request.isOpen,
  };
}

/// The create form: add lines, pick a needed-by date, send it to MVEC.
///
/// Owns its controllers so nothing is disposed while the dialog is animating.
class _SupplyRequestForm extends ConsumerStatefulWidget {
  const _SupplyRequestForm();

  @override
  ConsumerState<_SupplyRequestForm> createState() => _SupplyRequestFormState();
}

class _SupplyRequestFormState extends ConsumerState<_SupplyRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _product = TextEditingController();
  final _category = TextEditingController();
  final _units = TextEditingController(text: '1');
  final _unitPrice = TextEditingController();
  final _note = TextEditingController();
  final _neededBy = TextEditingController();

  final List<SupplyRequestLine> _lines = [];
  bool _saving = false;

  /// Units the supplier can ask for, read from their own catalogue so the
  /// category and price fields prefill the way a real quote would.
  ///
  /// Empty until `/suppliers/me/products` answers, in which case the item
  /// dropdown is disabled and the supplier types the line in by hand.
  static Map<String, ({String category, num price, String unit})> _catalogueOf(
    List<SupplierProduct> products,
  ) => {
    for (final product in products)
      product.name: (
        category: product.category,
        price: product.price,
        unit: product.unit,
      ),
  };

  /// Catalogue lookup for event handlers, where `ref.watch` is not allowed.
  Map<String, ({String category, num price, String unit})> _readCatalogue() =>
      _catalogueOf(
        ref.read(supplierWorkspaceProvider).valueOrNull?.products ??
            const <SupplierProduct>[],
      );

  @override
  void initState() {
    super.initState();
    final soon = DateTime.now().add(const Duration(days: 14));
    _neededBy.text =
        '${soon.year}-${soon.month.toString().padLeft(2, '0')}-'
        '${soon.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _product.dispose();
    _category.dispose();
    _units.dispose();
    _unitPrice.dispose();
    _note.dispose();
    _neededBy.dispose();
    super.dispose();
  }

  void _addLine() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _product.text.trim();
    final entry = _readCatalogue()[name];
    setState(() {
      _lines.add(
        SupplyRequestLine(
          product: name,
          category:
              _category.text.trim().isEmpty
                  ? entry?.category ?? 'General'
                  : _category.text.trim(),
          units: int.parse(_units.text.trim()),
          unit: entry?.unit ?? 'kg',
          unitPrice: num.parse(_unitPrice.text.trim()),
        ),
      );
      _product.clear();
      _category.clear();
      _units.text = '1';
      _unitPrice.clear();
    });
    _formKey.currentState?.reset();
  }

  num get _total => _lines.fold<num>(0, (sum, line) => sum + line.lineTotal);

  int get _totalUnits => _lines.fold<int>(0, (sum, line) => sum + line.units);

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      showMvSnack(context, 'Add at least one item to the request');
      return;
    }
    final neededBy = DateTime.tryParse(_neededBy.text.trim());
    if (neededBy == null) {
      showMvSnack(context, 'Enter the date you need the stock (YYYY-MM-DD)');
      return;
    }

    setState(() => _saving = true);
    try {
      final request = await ref
          .read(supplierOperationsModuleProvider)
          .createSupplyRequest(
            lines: _lines,
            neededBy: neededBy,
            note: _note.text,
          );
      ref.invalidate(supplierSupplyRequestsProvider);
      if (mounted) {
        Navigator.pop(context);
        showMvSnack(
          context,
          '${request.reference} submitted — MVEC will review it today',
          success: true,
        );
      }
    } catch (error) {
      if (mounted) showMvSnack(context, friendlyError(error));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The item picker is seeded from the supplier's own catalogue rather than a
    // bundled list, so it stays empty until the API has products to offer.
    final catalogue = _catalogueOf(
      ref.watch(supplierWorkspaceProvider).valueOrNull?.products ??
          const <SupplierProduct>[],
    );
    return AlertDialog(
      title: const Text('New supply request'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const InfoBox(
                  'Nothing is charged until you accept the quote. Step 3 of the '
                  'flow explains how that works.',
                  icon: 'shield',
                ),
                const SizedBox(height: 14),
                Text('Add an item', style: context.mvH1.copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue:
                      catalogue.containsKey(_product.text.trim())
                          ? _product.text.trim()
                          : null,
                  decoration: InputDecoration(
                    labelText: 'Item',
                    border: const OutlineInputBorder(),
                    helperText:
                        catalogue.isEmpty
                            ? 'Your catalogue is empty — add products first.'
                            : null,
                  ),
                  items: [
                    for (final name in catalogue.keys)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged:
                      (value) => setState(() {
                        final entry = value == null ? null : catalogue[value];
                        _product.text = value ?? '';
                        if (entry != null) {
                          _category.text = entry.category;
                          _unitPrice.text = entry.price.toStringAsFixed(0);
                        }
                      }),
                  validator: (value) => value == null ? 'Choose an item' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _units,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          return parsed == null || parsed <= 0
                              ? 'Enter a quantity'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _unitPrice,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Unit price (RWF)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = num.tryParse(
                            value?.replaceAll(',', '').trim() ?? '',
                          );
                          return parsed == null || parsed <= 0
                              ? 'Enter a price'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlineMvButton(
                  label: 'Add to request',
                  icon: 'plus',
                  onPressed: _addLine,
                ),
                if (_lines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'On this request',
                    style: context.mvH1.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _lines.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_lines[i].units} ${_lines[i].unit} · '
                              '${_lines[i].product}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.mv.text,
                              ),
                            ),
                          ),
                          Text(
                            money(_lines[i].lineTotal),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: context.mv.textMuted,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _lines.removeAt(i)),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close,
                              size: 15,
                              color: MvColors.dangerIcon,
                            ),
                            tooltip: 'Remove ${_lines[i].product}',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${plural(_totalUnits, 'unit')} · ${money(_total)} total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: context.mv.accentDeep,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _neededBy,
                  decoration: const InputDecoration(
                    labelText: 'Needed by (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note for MVEC (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Submitting…' : 'Submit request'),
        ),
      ],
    );
  }
}

/// Asks for an optional reason before withdrawing a request.
class _WithdrawDialog extends StatefulWidget {
  const _WithdrawDialog();

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Withdraw this request?'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'MVEC stops reviewing it immediately. You can resubmit the same '
                'items later with a new reference.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Withdraw'),
        ),
      ],
    );
  }
}
