import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'supplier_catalog_page.dart';
import 'wholesale_shared.dart';

/// `/vendor/suppliers` — verified suppliers and their wholesale catalogs.
class FindSuppliersPage extends StatefulWidget {
  const FindSuppliersPage({super.key});

  @override
  State<FindSuppliersPage> createState() => _FindSuppliersPageState();
}

class _FindSuppliersPageState extends State<FindSuppliersPage> {
  late final _data = Loader(() => jlist('/suppliers', 'data', {'pageSize': 100}));
  String _q = '';
  String _sort = 'rating';

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: 'B2B marketplace',
      title: 'Find suppliers',
      subtitle: 'Browse verified suppliers, compare wholesale prices and order stock in bulk, protected by escrow.',
      onRefresh: _data.reload,
      children: [
        SearchBox(hint: 'Search by supplier, location or what they sell…', onChanged: (v) => setState(() => _q = v)),
        FilterSelect(label: 'Sort', value: _sort, options: const [('rating', 'Top rated'), ('name', 'Name A–Z')], onChanged: (v) => setState(() => _sort = v)),
        const SizedBox(height: 12),
        LoadView(
          loader: _data,
          builder: (all) {
            final list =
                all.where((s) => matches(_q, [s['businessName'], locationOf(s), s['description']])).toList()
                  ..sort((a, b) => _sort == 'name' ? strOf(a['businessName']).compareTo(strOf(b['businessName'])) : numOf(b['ratingAvg']).compareTo(numOf(a['ratingAvg'])));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tiny('${list.length} supplier${list.length == 1 ? '' : 's'}'),
                Paged<Map<String, dynamic>>(
                  items: list,
                  perPage: 9,
                  empty: EmptyState(
                    icon: Icons.storefront_outlined,
                    title: _q.isNotEmpty ? 'No suppliers match your search' : 'No verified suppliers yet',
                    message: _q.isNotEmpty ? 'Try a different name or location.' : 'Verified suppliers will appear here as they join Ikiguzi.',
                  ),
                  itemBuilder:
                      (s) => RecordCard(
                        leading: Avatar(name: strOf(s['businessName'], '?'), url: strOf(s['logoUrl']), radius: 22),
                        title: strOf(s['businessName']),
                        badges: const [StatusChip('Verified ✓', tone: StatusTone.good)],
                        subtitle: '${locationOf(s)} · ${numOf(s['ratingAvg']) > 0 ? '★ ${numOf(s['ratingAvg']).toStringAsFixed(1)}' : 'New'}',
                        lines: [strOf(s['description'], 'Wholesale supplier on Ikiguzi.')],
                        actions: [
                          ActionChipBtn(
                            'View catalog',
                            icon: Icons.inventory_2_outlined,
                            primary: true,
                            onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => SupplierCatalogPage(supplier: s))),
                          ),
                          ActionChipBtn('Message', icon: Icons.chat_bubble_outline_rounded, onPressed: () => messageSupplier(context, s)),
                        ],
                      ),
                ),
                const InfoBox(
                  title: '✓ B2B trust',
                  text: 'Every supplier here is verified by Ikiguzi. Minimum order quantities and stock are checked when you order, and your payment stays in escrow until you confirm the delivery.',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
