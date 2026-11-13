import 'package:flutter/material.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';
import 'seller_common.dart';

String stars(num n) => '${'★' * n.clamp(0, 5).toInt()}${'☆' * (5 - n.clamp(0, 5).toInt())}';

/// `/vendor/reviews` (and the supplier's) — ratings and public replies.
class SellerReviewsPage extends StatefulWidget {
  const SellerReviewsPage({super.key, this.endpoint = '/reviews/vendor/mine', this.canReply = true, this.eyebrow = 'Seller platform'});
  final String endpoint;
  final bool canReply;
  final String eyebrow;

  @override
  State<SellerReviewsPage> createState() => _SellerReviewsPageState();
}

class _SellerReviewsPageState extends State<SellerReviewsPage> {
  late final _data = Loader(() => jlist(widget.endpoint, 'data'));
  String _tab = 'ALL';

  static final _tabs = <(String, String, bool Function(Map<String, dynamic>))>[
    ('ALL', 'All', (_) => true),
    ('AWAITING', 'Needs reply', (r) => strOf(r['vendorReply']).isEmpty),
    ('LOW', '1–2 stars', (r) => numOf(r['rating']) <= 2),
    ('MID', '3 stars', (r) => numOf(r['rating']) == 3),
    ('HIGH', '4–5 stars', (r) => numOf(r['rating']) >= 4),
  ];

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      eyebrow: widget.eyebrow,
      title: 'Reviews',
      subtitle: 'See what buyers say about your products and reply publicly. Your reply shows under the review on the product page and the buyer is notified. Moderation stays with Ikiguzi.',
      onRefresh: _data.reload,
      children: [
        LoadView(
          loader: _data,
          builder: (rows) {
            final total = rows.length;
            final avg = total == 0 ? 0 : rows.fold<num>(0, (s, r) => s + numOf(r['rating'])) / total;
            final dist = [
              for (final n in [5, 4, 3, 2, 1]) (n, rows.where((r) => numOf(r['rating']) == n).length),
            ];
            final replied = rows.where((r) => strOf(r['vendorReply']).isNotEmpty).length;
            final byProduct = <String, ({String name, int count, num sum, int low})>{};
            for (final r in rows) {
              final k = '${r['productId'] ?? r['product']}';
              final p = byProduct[k] ?? (name: strOf(r['product']), count: 0, sum: 0, low: 0);
              byProduct[k] = (name: p.name, count: p.count + 1, sum: p.sum + numOf(r['rating']), low: p.low + (numOf(r['rating']) <= 2 ? 1 : 0));
            }
            final products = byProduct.values.toList()..sort((a, b) => (a.sum / a.count).compareTo(b.sum / b.count));
            final filter = _tabs.firstWhere((t) => t.$1 == _tab).$3;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetricGrid(
                  children: [
                    MetricCard(label: 'Average rating', value: total > 0 ? '${avg.toStringAsFixed(1)} / 5' : '—', icon: 'heart', sub: '$total reviews'),
                    MetricCard(label: 'Awaiting reply', value: '${total - replied}', icon: 'bell', sub: 'Reviews without your response'),
                    MetricCard(label: 'Reply rate', value: '${total == 0 ? 0 : (replied / total * 100).round()}%', icon: 'users', sub: 'Buyers see your replies on the product page'),
                    MetricCard(label: 'Low ratings', value: '${dist[3].$2 + dist[4].$2}', icon: 'shield', sub: '1–2 star reviews'),
                  ],
                ),
                const SizedBox(height: 14),
                if (total > 0) ...[
                  Section(title: 'Rating breakdown', subtitle: 'All your products', children: [for (final (n, c) in dist) ProgressRow(label: '$n ★', fraction: c / total, value: '$c')]),
                  Section(
                    title: 'By product',
                    subtitle: 'Lowest rated first',
                    children: [
                      for (final p in products.take(5))
                        RecordCard(title: p.name, subtitle: '${p.count} review${p.count == 1 ? '' : 's'}${p.low > 0 ? ' · ${p.low} low' : ''}', amount: '${(p.sum / p.count).toStringAsFixed(1)} ★'),
                    ],
                  ),
                ],
                TabChips(tabs: [for (final t in _tabs) (t.$1, t.$2)], value: _tab, counts: {for (final t in _tabs) t.$1: rows.where(t.$3).length}, onChanged: (v) => setState(() => _tab = v)),
                Paged<Map<String, dynamic>>(
                  items: rows.where(filter).toList(),
                  empty: const EmptyState(icon: Icons.star_outline_rounded, title: 'No reviews here', message: 'They appear once buyers rate your products.'),
                  itemBuilder:
                      (r) => RecordCard(
                        title: strOf(r['product']),
                        subtitle: '${strOf(r['reviewer'], 'Buyer')}${r['isVerifiedPurchase'] == true ? ' · Verified purchase' : ''} · ${formatDate(r['date'])}',
                        lines: [stars(numOf(r['rating'])), strOf(r['comment'], '—'), if (strOf(r['vendorReply']).isNotEmpty) 'Your reply: ${r['vendorReply']}'],
                        actions: [
                          if (widget.canReply)
                            ActionChipBtn(
                              strOf(r['vendorReply']).isEmpty ? 'Reply' : 'Edit reply',
                              onPressed: () async {
                                final ok = await showFormSheet<bool>(
                                  context,
                                  title: 'Reply to review',
                                  subtitle: '${strOf(r['reviewer'], 'Buyer')} on ${r['product']}: “${r['comment'] ?? ''}”',
                                  fields: const [FieldSpec('reply', 'Your public reply', type: FieldType.textarea, required: true, lines: 4)],
                                  initial: {'reply': strOf(r['vendorReply'])},
                                  submitLabel: 'Post reply',
                                  onSubmit: (v) async {
                                    await jpost('/reviews/${r['id']}/reply', {'reply': v['reply']});
                                    return true;
                                  },
                                );
                                if (ok == true && context.mounted) {
                                  toast(context, 'Reply posted.');
                                  _data.reload();
                                }
                              },
                            ),
                        ],
                      ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Analytics & Reports ─────────────────────────────────────────────────────
