import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme.dart';
import '../../../../core/utils/app_theme.dart';
import '../../data/interest/interest_profile.dart';
import '../../data/interest/interest_store.dart';
import '../../data/models/product_model.dart';
import '../providers/home_provider.dart';
import '../Widgets/product_card.dart';
import 'product_navigation.dart';

/// For You tab: personalized recommendations plus products the user
/// recently viewed.
///
/// For a signed-in account the recommendations are the catalogue ranked by
/// what they actually buy, strongest match first. A guest sees the same list
/// the feed has always shipped with.
class ForYouScreen extends ConsumerWidget {
  const ForYouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = context.watch<HomeProvider>();
    final profile = ref.watch(myInterestProvider);
    final now = DateTime.now();
    // The personalised block replaces the static recommendations only when
    // there is a real history behind it; otherwise the authored list stands.
    final matched =
        rankByInterest(provider.products, profile)
            .where((p) => (profile?.scoreOf(p.categoryId, now) ?? 0) > 0)
            .take(12)
            .toList();
    final recommended =
        matched.isNotEmpty ? matched : provider.recommendedProducts;
    final recent = provider.recentlyViewed;
    final personalised = matched.isNotEmpty;

    if (recommended.isEmpty && recent.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                color: context.mv.accentDeep,
                size: 56,
              ),
              const SizedBox(height: 12),
              Text(
                'Nothing personalized for you yet',
                style: AppTextStyles.title(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Open a few products to build your feed.',
                style: AppTextStyles.bodySecondary(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('For You', style: AppTextStyles.headline(context)),
        const SizedBox(height: 16),
        if (recent.isNotEmpty) ...<Widget>[
          _Header('Recently Viewed'),
          const SizedBox(height: 10),
          _Grid(products: recent),
          const SizedBox(height: 20),
        ],
        if (recommended.isNotEmpty) ...<Widget>[
          _Header(
            personalised ? 'Matched to what you buy' : 'Recommended for You',
          ),
          const SizedBox(height: 10),
          _Grid(products: recommended),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTextStyles.sectionTitle(context));
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductCard(
          width: double.infinity,
          product: product,
          onTap: () {
            context.read<HomeProvider>().addRecentlyViewed(product);
            openProductDetails(context, product);
          },
        );
      },
    );
  }
}
