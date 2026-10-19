import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/catalog_state.dart';
import '../../widgets/common.dart';
import 'product_card.dart';

/// `/` — popular products, deals and top stores (`pages/Home.jsx`).
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final mv = context.mv;
    return RefreshIndicator(
      onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: MvColors.gradient, borderRadius: BorderRadius.circular(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MVEC MARKETPLACE', style: context.mvEyebrow.copyWith(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 6),
                    Text('Shop. Sell.\nGrow together.', style: context.mvH1.copyWith(color: Colors.white, fontSize: 28, height: 1.1)),
                    const SizedBox(height: 8),
                    const Text('Products from trusted sellers across Rwanda.', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 14, runSpacing: 4, children: const [
                      Text('✓ Local sellers', style: TextStyle(color: Colors.white, fontSize: 12)),
                      Text('✓ Payment held until delivery', style: TextStyle(color: Colors.white, fontSize: 12)),
                      Text('✓ Mobile money', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
                    const SizedBox(height: 14),
                    SolidButton(label: 'Shop now', icon: Icons.arrow_forward_rounded, compact: true, onPressed: () => context.go('/shop')),
                  ],
                ),
              ),
            ),
          ),
          ...catalog.when(
            loading: () => [const SliverToBoxAdapter(child: LoadingState(label: 'Loading the marketplace…'))],
            error: (e, _) => [SliverToBoxAdapter(child: ErrorState(error: e, onRetry: () => ref.invalidate(catalogProvider)))],
            data: (c) => [
              if (c.error)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Notice(text: 'We could not load the marketplace right now. Check your connection and try again.', onClose: () => ref.read(catalogProvider.notifier).refresh()),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                sliver: SliverToBoxAdapter(
                  child: SectionHeading(title: 'Popular products', eyebrow: 'TRENDING NOW', actionLabel: 'View all', onAction: () => context.go('/shop')),
                ),
              ),
              if (c.products.isEmpty && !c.error)
                const SliverToBoxAdapter(child: EmptyState(title: 'No products yet', message: 'Sellers are setting up their stores. Check back soon.'))
              else
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 14), sliver: ProductGridSliver(products: c.popular.take(8).toList())),
              if (c.deals.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: mv.soft, borderRadius: BorderRadius.circular(16), border: Border.all(color: mv.border)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MVEC DEAL DAYS', style: context.mvEyebrow.copyWith(fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('More products. Less searching.', style: context.mvH1.copyWith(fontSize: 20)),
                          const SizedBox(height: 6),
                          Text('${c.deals.length} product${c.deals.length == 1 ? " is" : "s are"} on sale right now.', style: TextStyle(color: mv.textMuted)),
                          const SizedBox(height: 12),
                          GradientButton(label: 'Shop deals', compact: true, onPressed: () => context.go('/shop?deal=true')),
                        ],
                      ),
                    ),
                  ),
                ),
              if (c.stores.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeading(title: 'Trusted vendors', eyebrow: 'TOP STORES', actionLabel: 'View all', onAction: () => context.push('/vendors')),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverList.separated(
                    itemCount: c.stores.take(4).length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = c.stores[i];
                      return Material(
                        color: mv.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => context.push('/vendors/${s.id}'),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(border: Border.all(color: mv.border), borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Avatar(name: s.name, url: s.logoUrl, radius: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: TextStyle(fontWeight: FontWeight.w800, color: mv.text)),
                                      Text(s.category, style: TextStyle(color: mv.textMuted, fontSize: 12)),
                                      Text('★ ${ratingLabel(s.rating)} · ${s.products} product${s.products == 1 ? "" : "s"}', style: TextStyle(color: mv.textMuted, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_rounded, color: mv.textMuted, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
