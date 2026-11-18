import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// One size/colour in the editor.
class VariantRow {
  VariantRow({this.id, Map<String, String>? values, String price = '', String stock = '0'})
      : values = values ?? {},
        price = TextEditingController(text: price),
        stock = TextEditingController(text: stock);
  final String? id;
  final Map<String, String> values;
  final TextEditingController price;
  final TextEditingController stock;

  void dispose() {
    price.dispose();
    stock.dispose();
  }
}

/// The product editor's sizes/colours and flash deal, as on the website
/// (`components/vendor/VariantDealEditor.jsx`).
class VariantDealState {
  VariantDealState(Map<String, dynamic> product) {
    final list = asMaps(product['variants']);
    for (final v in list) {
      for (final n in asMap(v['options']).keys) {
        if (!names.contains(n)) names.add(n);
      }
    }
    if (names.isEmpty) names.add('Size');
    while (names.length < 2) {
      names.add('');
    }
    nameCtl = [for (final n in names.take(2)) TextEditingController(text: n)];
    rows = [
      for (final v in list)
        VariantRow(
          id: strOf(v['id']),
          values: {for (final e in asMap(v['options']).entries) e.key: '${e.value}'},
          price: v['ownPrice'] == null ? '' : '${numOf(v['ownPrice']).round()}',
          stock: '${numOf(v['stockQuantity']).toInt()}',
        ),
    ];
    hadVariants = rows.isNotEmpty;
    dealPrice = TextEditingController(text: product['dealPrice'] == null ? '' : '${numOf(product['dealPrice']).round()}');
    dealUnits = TextEditingController(text: product['dealQuantity'] == null ? '' : '${numOf(product['dealQuantity']).toInt()}');
    dealStarts = parseDate(product['dealStartsAt'])?.toLocal();
    dealEnds = parseDate(product['dealEndsAt'])?.toLocal();
    hadDeal = product['dealPrice'] != null;
  }

  final names = <String>[];
  late final List<TextEditingController> nameCtl;
  late List<VariantRow> rows;
  late final bool hadVariants;
  late final TextEditingController dealPrice;
  late final TextEditingController dealUnits;
  DateTime? dealStarts;
  DateTime? dealEnds;
  late final bool hadDeal;

  List<String> get optionNames => [for (final c in nameCtl) if (c.text.trim().isNotEmpty) c.text.trim()];
  bool get hasVariants => rows.isNotEmpty;
  int get totalStock => rows.fold(0, (n, r) => n + (int.tryParse(r.stock.text) ?? 0));

  /// For `PUT /products/:id/variants`; null when variants were never used.
  List<Map<String, dynamic>>? variantsPayload() => !hasVariants && !hadVariants
      ? null
      : [
          for (final r in rows)
            {
              if (r.id != null && r.id!.isNotEmpty) 'id': r.id,
              'options': {for (final n in optionNames) n: r.values[n] ?? ''},
              'price': r.price.text.trim().isEmpty ? null : num.tryParse(r.price.text.trim()),
              'stockQuantity': int.tryParse(r.stock.text.trim()) ?? 0,
            },
        ];

  /// Deal fields for the product payload ({} when nothing changes).
  Map<String, dynamic> dealPayload() {
    if (dealPrice.text.trim().isEmpty) return hadDeal ? {'dealPrice': null} : {};
    return {
      'dealPrice': num.tryParse(dealPrice.text.trim()),
      'dealStartsAt': (dealStarts ?? DateTime.now()).toUtc().toIso8601String(),
      'dealEndsAt': dealEnds?.toUtc().toIso8601String() ?? '',
      'dealQuantity': dealUnits.text.trim().isEmpty ? null : int.tryParse(dealUnits.text.trim()),
    };
  }

  void dispose() {
    for (final c in nameCtl) {
      c.dispose();
    }
    for (final r in rows) {
      r.dispose();
    }
    dealPrice.dispose();
    dealUnits.dispose();
  }
}

class VariantEditor extends StatelessWidget {
  const VariantEditor({super.key, required this.state, required this.onChanged});
  final VariantDealState state;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final names = state.optionNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Tiny('Sell one product in several sizes or colours, each with its own stock (and price, if it differs). Leave empty if it has none.'),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: TextField(controller: state.nameCtl[i], decoration: InputDecoration(labelText: i == 0 ? 'First option' : 'Second option', hintText: i == 0 ? 'Size' : 'Color', isDense: true), onChanged: (_) => onChanged())),
          ],
        ]),
        const SizedBox(height: 8),
        for (final (i, r) in state.rows.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Row(children: [
                for (final (j, n) in names.indexed) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(child: TextFormField(initialValue: r.values[n] ?? '', decoration: InputDecoration(labelText: n, isDense: true), onChanged: (v) => r.values[n] = v.trim())),
                ],
                IconButton(tooltip: 'Remove option', icon: const Icon(Icons.close_rounded), onPressed: () {
                  state.rows.removeAt(i).dispose();
                  onChanged();
                }),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: r.price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Own price', hintText: 'Same', isDense: true))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: r.stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock', isDense: true), onChanged: (_) => onChanged())),
              ]),
            ]),
          ),
        Row(children: [
          OutlineBtn(label: 'Add a size/colour', icon: Icons.add_rounded, compact: true, onPressed: () {
            state.rows.add(VariantRow());
            onChanged();
          }),
          const SizedBox(width: 10),
          if (state.hasVariants) Tiny('Total stock: ${state.totalStock}'),
        ]),
      ],
    );
  }
}

class DealEditor extends StatelessWidget {
  const DealEditor({super.key, required this.state, required this.onChanged});
  final VariantDealState state;
  final VoidCallback onChanged;

  Future<DateTime?> _pick(BuildContext context, DateTime? current) async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: current ?? now, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 60)));
    if (day == null || !context.mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  String _when(DateTime? d) => d == null ? 'Choose' : '${formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Tiny('A lower price for a short time (up to 14 days), optionally for a limited number of units. It shows on the Deals page with a countdown.'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(controller: state.dealPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Deal price (RWF)', hintText: 'No deal', isDense: true), onChanged: (_) => onChanged())),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: state.dealUnits, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Units at this price', hintText: 'No limit', isDense: true))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlineBtn(label: 'Starts: ${_when(state.dealStarts)}', compact: true, onPressed: () async {
          final d = await _pick(context, state.dealStarts);
          if (d != null) {
            state.dealStarts = d;
            onChanged();
          }
        })),
        const SizedBox(width: 8),
        Expanded(child: OutlineBtn(label: 'Ends: ${_when(state.dealEnds)}', compact: true, onPressed: () async {
          final d = await _pick(context, state.dealEnds);
          if (d != null) {
            state.dealEnds = d;
            onChanged();
          }
        })),
      ]),
      if (state.hadDeal)
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () {
          state.dealPrice.clear();
          state.dealUnits.clear();
          onChanged();
        }, child: const Text('End the deal'))),
    ]);
  }
}
