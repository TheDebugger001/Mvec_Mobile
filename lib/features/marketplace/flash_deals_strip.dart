import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/catalog_api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../widgets/common.dart';
import 'product_extras.dart';

/// On the Deals tab: flash deals on now (ending soonest first) and those
/// starting within a day, each with its countdown.
class FlashDealsStrip extends StatefulWidget {
  const FlashDealsStrip({super.key});

  @override
  State<FlashDealsStrip> createState() => _FlashDealsStripState();
}

class _FlashDealsStripState extends State<FlashDealsStrip> {
  List<Product> _deals = const [];

  @override
  void initState() {
    super.initState();
    CatalogApi.deals().then((d) {
      if (mounted) setState(() => _deals = [...d.live, ...d.upcoming]);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_deals.isEmpty) return const SizedBox.shrink();
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text('Flash deals', style: context.mvH1.copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _deals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = _deals[i];
                return GestureDetector(
                  onTap: () => context.push('/product/${p.id}'),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: mv.surface, border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(MvRadius.card)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(height: 84, width: double.infinity, child: ProductImage(src: p.image))),
                        const SizedBox(height: 6),
                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: mv.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        Text(money(p.deal?.price ?? p.price), style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w800, fontSize: 13)),
                        if (p.deal != null) DealTag(deal: p.deal!, compact: true),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
