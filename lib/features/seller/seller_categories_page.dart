import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';

/// `/vendor/categories` — marketplace categories and how many of the
/// seller's products are in each.
class SellerCategoriesPage extends StatefulWidget {
  const SellerCategoriesPage({super.key});

  @override
  State<SellerCategoriesPage> createState() => _SellerCategoriesPageState();
}

class _SellerCategoriesPageState extends State<SellerCategoriesPage> {
  late final _data = Loader(() async {
    final r = await Future.wait([
      jlist('/categories', 'categories', {'withCounts': true}),
      vendorProducts().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return (categories: r[0], products: r[1]);
  });
  String _q = '';
  final _open = <String>{};

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _add(String parentId, List<CategoryNode> tree) async {
    final res = await showFormSheet<Map<String, dynamic>>(
      context,
      title: parentId.isEmpty ? 'Add category' : 'Add subcategory',
      subtitle: 'New categories are available to every seller right away. If it already exists, the existing one is used.',
      fields: [
        const FieldSpec('name', 'Category name', required: true, hint: 'e.g. Smartphones'),
        FieldSpec('parentId', 'Parent category', type: FieldType.select, placeholderOption: 'None (top-level category)', options: [for (final r in tree) (r.id, r.name)]),
        const FieldSpec('description', 'Description', type: FieldType.textarea, hint: 'Optional: what belongs in this category'),
      ],
      initial: {'parentId': parentId},
      submitLabel: 'Add category',
      onSubmit:
          (v) => jpost('/categories', {
            'name': v['name'],
            'parentId': '${v['parentId'] ?? ''}'.isEmpty ? null : v['parentId'],
            if ('${v['description'] ?? ''}'.isNotEmpty) 'description': v['description'],
          }),
    );
    if (res == null || !mounted) return;
    toast(context, res['alreadyExisted'] == true ? strOf(res['message']) : 'Category “${asMap(res['category'])['name']}” added.');
    _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final mine = <String, int>{};
        for (final p in d.products) {
          final k = idOf(p['category']);
          mine[k] = (mine[k] ?? 0) + 1;
        }
        final known = d.categories.map(idOf).toSet();
        final orphaned = d.products.where((p) => !known.contains(idOf(p['category']))).length;
        final tree = buildCategoryTree(d.categories);
        int mineOf(CategoryNode n) => (mine[n.id] ?? 0) + n.children.fold<int>(0, (s, c) => s + (mine[c.id] ?? 0));
        int marketOf(CategoryNode n) => numOf(n.data['productCount']).toInt() + n.children.fold<int>(0, (s, c) => s + numOf(c.data['productCount']).toInt());
        final shown = [
          for (final r in tree)
            if (matches(_q, [r.name]) || r.children.any((c) => matches(_q, [c.name]))) r,
        ];
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'Categories',
          subtitle: 'Marketplace categories your products can be listed in. Categories are shared across Ikiguzi; editing and removing them is handled by Ikiguzi admins.',
          onRefresh: _data.reload,
          action: GradientButton(label: 'Add category', icon: Icons.add_rounded, compact: true, onPressed: () => _add('', tree)),
          children: [
            MetricGrid(
              children: [
                MetricCard(label: 'Marketplace categories', value: '${d.categories.length}', icon: 'tag', sub: '${tree.length} top-level'),
                MetricCard(label: 'You sell in', value: '${mine.keys.where(known.contains).length}', icon: 'shop', sub: 'of ${d.categories.length} categories'),
                MetricCard(label: 'Need a category', value: '$orphaned', icon: 'bell', sub: orphaned > 0 ? 'Products in a disabled category' : 'All products categorized'),
              ],
            ),
            const SizedBox(height: 14),
            SearchBox(hint: 'Search categories and subcategories', onChanged: (v) => setState(() => _q = v)),
            if (tree.isEmpty) const EmptyState(icon: Icons.sell_outlined, title: 'No categories yet', message: 'Add the first category for your products.'),
            if (tree.isNotEmpty && shown.isEmpty) Tiny('No categories match “$_q”.'),
            for (final r in shown)
              DataCard(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: r.children.isEmpty ? null : () => setState(() => _open.contains(r.id) ? _open.remove(r.id) : _open.add(r.id)),
                      leading: Icon(r.children.isEmpty ? Icons.sell_outlined : (_open.contains(r.id) || _q.isNotEmpty ? Icons.expand_less_rounded : Icons.expand_more_rounded)),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Yours ${mineOf(r)} · On Ikiguzi ${marketOf(r)}${r.children.isNotEmpty ? ' · ${r.children.length} sub' : ''}', style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (mineOf(r) > 0)
                            IconButton(tooltip: 'View products', icon: const Icon(Icons.visibility_outlined, size: 20), onPressed: () => context.go('/vendor/products?category=${r.id}')),
                          IconButton(tooltip: 'Add a subcategory to ${r.name}', icon: const Icon(Icons.add_rounded, size: 20), onPressed: () => _add(r.id, tree)),
                        ],
                      ),
                    ),
                    if (_open.contains(r.id) || _q.isNotEmpty)
                      for (final c in r.children.where((c) => _q.isEmpty || matches(_q, [c.name]) || matches(_q, [r.name])))
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 40),
                          title: Text(c.name),
                          subtitle: Text('Yours ${mine[c.id] ?? 0} · On Ikiguzi ${numOf(c.data['productCount']).toInt()}'),
                          trailing:
                              (mine[c.id] ?? 0) > 0
                                  ? IconButton(tooltip: 'View products', icon: const Icon(Icons.visibility_outlined, size: 20), onPressed: () => context.go('/vendor/products?category=${c.id}'))
                                  : null,
                        ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
