import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme.dart';
import '../../../../core/utils/app_theme.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/common.dart';
import '../../data/interest/interest_store.dart';
import '../../data/interest/new_product_notices.dart';
import '../../data/models/product_model.dart';
import '../providers/home_provider.dart';
import 'product_navigation.dart';

/// The shopper's notifications.
///
/// Personalised: once an account has a history, new arrivals in the categories
/// they buy from are listed here with the reason they were picked. A guest, or
/// an account with nothing recorded yet, sees a plain signed-out state — this
/// page is deliberately not a marketing surface for people with no account.
class ShopperNotificationsScreen extends ConsumerWidget {
  const ShopperNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(myInterestProvider);
    final home = context.watch<HomeProvider>();
    final mv = context.mv;

    if (user == null) return _signedOut(context);

    final catalogue = <Product>[
      ...home.featuredProducts,
      ...home.products,
      ...home.recommendedProducts,
    ];
    final notices = newProductNotices(
      catalogue: catalogue,
      profile: profile,
      now: DateTime.now(),
      categoryNames: <int, String>{
        for (final c in home.categories) c.id: c.name,
      },
    );

    if (notices.isEmpty) {
      return _noSuggestions(context, hasHistory: profile?.hasSignal ?? false);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.notifications_active_outlined,
              size: 18,
              color: mv.accentDeep,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'New in categories you buy from',
                style: AppTextStyles.title(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Picked from what you have browsed and bought. Sign out and these go away.',
          style: TextStyle(color: mv.textMuted, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        for (final notice in notices) ...<Widget>[
          _NoticeTile(
            notice: notice,
            onOpen: (product) {
              // Opening it is what counts as "already told them": marking the
              // whole list seen on render would empty the page the moment it
              // appeared.
              ref.read(interestStoreProvider.notifier).markSeen(<int>[
                product.id,
              ]);
              openProductDetails(context, product);
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _signedOut(BuildContext context) {
    final mv = context.mv;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none_rounded,
              size: 52,
              color: mv.accentDeep,
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in to get new-product alerts',
              style: AppTextStyles.title(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Tell us what you buy and we will tell you when something new '
              'lands in those categories. Nothing is tracked without an account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mv.textMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Sign in',
              icon: 'user',
              expanded: true,
              onPressed: () => context.go('/login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noSuggestions(BuildContext context, {required bool hasHistory}) {
    final mv = context.mv;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_none_rounded,
              size: 52,
              color: mv.accentDeep,
            ),
            const SizedBox(height: 12),
            Text(
              hasHistory ? 'Nothing new in your categories' : 'No alerts yet',
              style: AppTextStyles.title(context),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasHistory
                  ? 'You are up to date. We will let you know when the next '
                      'arrival lands.'
                  : 'Browse or buy a few things first and alerts will start '
                      'arriving here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mv.textMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// One alert: what arrived, which category, and why they were told.
class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notice, required this.onOpen});

  final NewProductNotice notice;
  final ValueChanged<Product> onOpen;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final product = notice.product;
    return InkWell(
      onTap: () => onOpen(product),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mv.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: mv.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  product.imageUrl.isEmpty
                      ? Container(
                        width: 52,
                        height: 52,
                        color: mv.soft,
                        child: Icon(
                          Icons.image_outlined,
                          size: 20,
                          color: mv.textMuted,
                        ),
                      )
                      : CachedNetworkImage(
                        imageUrl: product.imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder:
                            (_, _) => Container(
                              width: 52,
                              height: 52,
                              color: mv.soft,
                            ),
                        errorWidget:
                            (_, _, _) => Container(
                              width: 52,
                              height: 52,
                              color: mv.soft,
                              child: Icon(
                                Icons.image_outlined,
                                size: 20,
                                color: mv.textMuted,
                              ),
                            ),
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        notice.reason == NoticeReason.newInFamiliarCategory
                            ? Icons.local_mall_outlined
                            : Icons.fiber_new_rounded,
                        size: 13,
                        color: mv.accentDeep,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          notice.title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: mv.accentDeep,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: mv.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notice.body,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: mv.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\$${product.price.toStringAsFixed(2)}'
                    '${product.vendorName == null ? '' : ' · ${product.vendorName}'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: mv.accentDeep,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
