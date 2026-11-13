import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'wholesale_shared.dart';

num wholesaleUnitPrice(Map<String, dynamic> p) => numOf(p['wholesalePrice']) * (1 - numOf(p['bulkDiscount']) / 100);

/// A supplier's wholesale catalog and the order being built (`CatalogModal`).
class SupplierCatalogPage extends StatefulWidget {
  const SupplierCatalogPage({super.key, required this.supplier});
  final Map<String, dynamic> supplier;

  @override
  State<SupplierCatalogPage> createState() => _SupplierCatalogPageState();
}

class _SupplierCatalogPageState extends State<SupplierCatalogPage> {
  late final _data = Loader(() => jlist('/suppliers/${idOf(widget.supplier)}/products', 'products'));
  final _qty = <String, int>{};
  String _q = '';
  bool _placing = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  String _lineError(Map<String, dynamic> p, int q) {
    final moq = numOf(p['moq'], 1);
    if (q < moq) return 'Minimum order is $moq ${p['unit']}${moq == 1 ? '' : 's'}.';
    if (q > numOf(p['stockQuantity'])) return 'Only ${p['stockQuantity']} in stock.';
    return '';
  }

  Future<void> _place(List<(Map<String, dynamic>, int)> lines) async {
    setState(() => _placing = true);
    try {
      await jpost('/wholesale/orders', {
        'supplierId': idOf(widget.supplier),
        'items': [
          for (final (p, q) in lines) {'productId': idOf(p), 'productName': p['name'], 'quantity': q},
        ],
      });
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go('/vendor/purchases?notice=${Uri.encodeQueryComponent('Order placed and stock reserved. Pay now (within 48 hours) to confirm it.')}');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e), error: true);
        setState(() => _placing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;
    return Scaffold(
      appBar: AppBar(
        title: Text(strOf(s['businessName'], 'Catalog')),
        actions: [IconButton(tooltip: 'Message supplier', icon: const Icon(Icons.chat_bubble_outline_rounded), onPressed: () => messageSupplier(context, s, fromCatalog: true))],
      ),
      body: SafeArea(
        child: LoadView(
          loader: _data,
          page: true,
          loadingLabel: 'Loading catalog…',
          builder: (products) {
            final lines = [
              for (final p in products)
                if ((_qty[idOf(p)] ?? 0) > 0) (p, _qty[idOf(p)]!),
            ];
            final total = lines.fold<num>(0, (n, l) => n + wholesaleUnitPrice(l.$1) * l.$2);
            final invalid = lines.any((l) => _lineError(l.$1, l.$2).isNotEmpty);
            final shown = products.where((p) => matches(_q, [p['name'], p['category']])).toList();
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    children: [
                      Row(
                        children: [
                          Avatar(name: strOf(s['businessName'], '?'), url: strOf(s['logoUrl']), radius: 24),
                          const SizedBox(width: 10),
                          Expanded(child: Tiny('${numOf(s['ratingAvg']) > 0 ? '★ ${numOf(s['ratingAvg']).toStringAsFixed(1)}' : 'New'} · ${locationOf(s)} · Verified ✓')),
                        ],
                      ),
                      if (strOf(s['description']).isNotEmpty) Tiny(strOf(s['description'])),
                      const SizedBox(height: 8),
                      if (products.length > 4) SearchBox(hint: 'Search this catalog…', onChanged: (v) => setState(() => _q = v)),
                      if (products.isEmpty) const EmptyState(icon: Icons.inventory_2_outlined, title: 'No wholesale products yet', message: 'Message this supplier to ask what they can supply.'),
                      for (final p in shown)
                        Builder(
                          builder: (_) {
                            final id = idOf(p);
                            final n = _qty[id] ?? 0;
                            final moq = numOf(p['moq'], 1).toInt();
                            final out = numOf(p['stockQuantity']) < moq;
                            return RecordCard(
                              selected: n > 0,
                              leading: ProductImage(src: strOf(asMap(p['media'])['mainImage']), size: 52, radius: 8),
                              title: strOf(p['name']),
                              subtitle: '${p['category'] ?? ''} · MOQ $moq ${p['unit']}${moq == 1 ? '' : 's'} · ${p['stockQuantity']} in stock',
                              lines: [
                                '${money(wholesaleUnitPrice(p))}/${p['unit']}${numOf(p['bulkDiscount']) > 0 ? ' (was ${money(p['wholesalePrice'])}, -${p['bulkDiscount']}%)' : ''}',
                                if (n > 0 && _lineError(p, n).isNotEmpty) _lineError(p, n),
                              ],
                              status: out ? const StatusChip('Out of stock', tone: StatusTone.bad) : null,
                              actions:
                                  out
                                      ? const []
                                      : n > 0
                                      ? [QtyStepper(value: n, min: 0, max: numOf(p['stockQuantity']).toInt(), onChanged: (v) => setState(() => _qty[id] = v < moq ? 0 : v))]
                                      : [ActionChipBtn('Add $moq', icon: Icons.add_rounded, onPressed: () => setState(() => _qty[id] = moq))],
                            );
                          },
                        ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: context.mv.surface, border: Border(top: BorderSide(color: context.mv.border))),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (lines.isEmpty)
                        const Tiny("Add products to build a wholesale order. Quantities start at each product's minimum order.")
                      else
                        KV('${lines.length} product${lines.length == 1 ? '' : 's'}', money(total), bold: true),
                      const SizedBox(height: 6),
                      GradientButton(label: 'Place wholesale order', loading: _placing, onPressed: lines.isEmpty || invalid ? null : () => _place(lines)),
                      const Tiny('Your payment is held in escrow and only released to the supplier after you confirm delivery.'),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
