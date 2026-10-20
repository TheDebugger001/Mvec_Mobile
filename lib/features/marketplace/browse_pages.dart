import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/catalog_api.dart';
import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../state/auth_state.dart';
import '../../state/cart_state.dart';
import '../../state/catalog_state.dart';
import '../../state/compare_state.dart';
import '../../widgets/common.dart';
import 'home_page.dart';
import 'product_card.dart';

/// `/buyer/recommendations` — "For You" (`BuyerRecommendations`).
class RecommendationsPage extends StatefulWidget {
  const RecommendationsPage({super.key});

  @override
  State<RecommendationsPage> createState() => _RecommendationsPageState();
}

class _RecommendationsPageState extends State<RecommendationsPage> {
  List<Product> _products = const [];
  bool _personalized = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await CatalogApi.recommendations(limit: 12);
      if (mounted) {
        setState(() {
          _products = r.products;
          _personalized = r.personalized;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            sliver: SliverToBoxAdapter(
              child: PageTitle(
                eyebrow: 'For you',
                title: 'Recommended for you',
                subtitle:
                    _personalized
                        ? "Based on categories you've bought from before."
                        : 'Popular and top-rated products across the marketplace.',
              ),
            ),
          ),
          if (_loading) const SliverToBoxAdapter(child: LoadingState()),
          if (_error != null)
            SliverToBoxAdapter(
              child: ErrorState(error: _error!, onRetry: _load),
            ),
          if (!_loading && _error == null && _products.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                title: 'No recommendations yet',
                message:
                    'Browse the shop to see personalized picks appear here.',
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            sliver: ProductGridSliver(products: _products),
          ),
        ],
      ),
    );
  }
}

/// `/vendors` — every store (`pages/Vendors.jsx`).
class StoresPage extends ConsumerWidget {
  const StoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          const PageTitle(
            eyebrow: 'Marketplace stores',
            title: 'Stores',
            subtitle:
                'Every store selling on MVEC. Sellers checked by MVEC carry a Verified badge; every order is protected by MVEC either way.',
          ),
          AsyncBody<Catalog>(
            value: catalog,
            onRetry: () => ref.invalidate(catalogProvider),
            data:
                (c) =>
                    c.stores.isEmpty
                        ? const EmptyState(
                          title: 'No vendors yet',
                          message:
                              'Stores appear here once they have products for sale.',
                        )
                        : Column(
                          children: [
                            for (final s in c.stores)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: StoreTile(store: s),
                              ),
                          ],
                        ),
          ),
        ],
      ),
    );
  }
}

/// `/vendors/:id` — one store, its products and follow (`pages/VendorDetail.jsx`).
class StoreDetailPage extends ConsumerStatefulWidget {
  const StoreDetailPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<StoreDetailPage> createState() => _StoreDetailPageState();
}

class _StoreDetailPageState extends ConsumerState<StoreDetailPage> {
  Map<String, dynamic>? _vendor;
  List<Product> _products = const [];
  bool _loading = true;
  String _error = '';
  bool _following = false;
  int _followers = 0;
  bool _busy = false;
  String _followError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await CatalogApi.store(widget.id);
      List<Product> products = const [];
      if (strOf(v['userId']).isNotEmpty) {
        products = await CatalogApi.products(query: {'vendorId': v['userId']});
      }
      if (mounted) {
        setState(() {
          _vendor = v;
          _products = products;
          _following = v['following'] == true;
          _followers = numOf(v['followers']).toInt();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (ref.read(authProvider).user == null) {
      context.push(
        '/login?next=${Uri.encodeQueryComponent('/vendors/${widget.id}')}',
      );
      return;
    }
    setState(() {
      _busy = true;
      _followError = '';
    });
    try {
      final r = await CatalogApi.follow(
        strOf(_vendor!['id']),
        follow: !_following,
      );
      setState(() {
        _following = r.following;
        _followers = r.followers;
      });
    } catch (e) {
      setState(() => _followError = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    if (_loading) return const LoadingState(label: 'Loading store…');
    final v = _vendor;
    if (v == null) return EmptyState(title: 'Store not found', message: _error);
    final name = strOf(v['businessName'], 'Store');
    final loc = v['location'];
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(14),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(name: name, url: strOf(v['logoUrl']), radius: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v['verificationStatus'] == 'VERIFIED'
                                ? 'VERIFIED STORE'
                                : 'STORE',
                            style: context.mvEyebrow,
                          ),
                          Text(
                            name,
                            style: context.mvH1.copyWith(fontSize: 18),
                          ),
                          Text(
                            '★ ${numOf(v['ratingAvg']).toStringAsFixed(1)} · ${_products.length} products · $_followers ${_followers == 1 ? 'follower' : 'followers'}',
                            style: TextStyle(color: mv.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_followError.isNotEmpty) Notice(text: _followError),
                _following
                    ? OutlineBtn(
                      label: 'Following',
                      compact: true,
                      expand: true,
                      onPressed: _busy ? null : _toggleFollow,
                    )
                    : GradientButton(
                      label: 'Follow store',
                      compact: true,
                      expand: true,
                      loading: _busy,
                      onPressed: _toggleFollow,
                    ),
                const SizedBox(height: 12),
                InfoBox(
                  title:
                      '${strOf(v['category'], 'Business')} · ${loc is String ? loc : strOf(asMap(loc)['city'], 'Rwanda')}',
                  text: strOf(
                    v['description'],
                    'This business has not added a description yet.',
                  ),
                ),
                const SectionHeading(title: 'Store products'),
                if (_products.isEmpty)
                  const EmptyState(title: 'No products listed yet'),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          sliver: ProductGridSliver(products: _products),
        ),
      ],
    );
  }
}

/// `/buyer/compare` — side-by-side comparison of up to four products.
class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({super.key});

  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  List<Product> _products = const [];
  bool _loading = true;
  String _loadedFor = '';

  Future<void> _load(List<String> ids) async {
    _loadedFor = ids.join(',');
    final results = await Future.wait(
      ids.map(
        (id) => CatalogApi.product(id).then<Product?>((p) => p).catchError((e) {
          if (statusOf(e) == 404) ref.read(compareProvider.notifier).remove(id);
          return null;
        }),
      ),
    );
    if (mounted) {
      setState(() {
        _products = results.whereType<Product>().toList();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final ids = ref.watch(compareProvider);
    if (ids.join(',') != _loadedFor) {
      _loading = ids.isNotEmpty;
      Future.microtask(() => _load(ids));
    }
    final best =
        _products.length > 1
            ? _products.map((p) => p.price).reduce((a, b) => a < b ? a : b)
            : null;
    Widget row(String label, Widget Function(Product) cell) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(color: mv.textMuted, fontSize: 11.5),
            ),
          ),
          for (final p in _products)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: cell(p),
              ),
            ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const PageTitle(
          eyebrow: 'Buyer',
          title: 'Compare products',
          subtitle:
              'Compare price, rating, stock and seller before you buy. Add products with the Compare button on any product page.',
        ),
        if (_loading) const LoadingState(),
        if (!_loading && _products.isEmpty)
          EmptyState(
            icon: Icons.compare_arrows_rounded,
            title: 'Nothing to compare yet',
            message: 'Open a product and press Compare.',
            action: GradientButton(
              label: 'Browse products',
              compact: true,
              onPressed: () => context.go('/shop'),
            ),
          ),
        if (!_loading && _products.isNotEmpty)
          DataCard(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 62),
                    for (final p in _products)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () => context.push('/product/${p.id}'),
                                child: SizedBox(
                                  height: 64,
                                  width: 64,
                                  child: ProductImage(src: p.image, radius: 8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed:
                                    () => ref
                                        .read(compareProvider.notifier)
                                        .remove(p.id),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 24),
                                ),
                                child: const Text(
                                  'Remove',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 8),
                row(
                  'Price',
                  (p) => Text(
                    '${money(p.price)}${p.price == best ? '\nlowest' : ''}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: p.price == best ? MvColors.successText : mv.text,
                    ),
                  ),
                ),
                row(
                  'Rating',
                  (p) => Text(
                    p.rating > 0 ? '★ ${p.rating.toStringAsFixed(1)}' : 'New',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                row(
                  'Stock',
                  (p) => Text(
                    p.stock > 0 ? '${p.stock} available' : 'Out of stock',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: p.stock > 0 ? null : MvColors.errorText,
                    ),
                  ),
                ),
                row(
                  'Seller',
                  (p) => Text(p.vendor, style: const TextStyle(fontSize: 11.5)),
                ),
                row(
                  'Category',
                  (p) =>
                      Text(p.category, style: const TextStyle(fontSize: 11.5)),
                ),
                if (_products.length < 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Add at least one more product to compare.',
                      style: TextStyle(color: mv.textMuted, fontSize: 12),
                    ),
                  ),
                TextButton(
                  onPressed: () => ref.read(compareProvider.notifier).clear(),
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// `/buyer/support` — help and common questions (`BuyerModule` support).
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _faq = [
    (
      'How do I track my order?',
      'Open My orders and choose the order. You see each step (paid, preparing, shipped, on the way) and get a notification when it changes.',
    ),
    (
      'How are delivery fees calculated?',
      'Each seller sets fees for your district. You see the exact fee for every parcel at checkout, before you pay.',
    ),
    (
      'How do refunds work?',
      "You can cancel within 30 minutes of paying for a full refund. After that, use Report a problem on the order; MVEC holds the seller's payment while it reviews. Refunds go back to the mobile money number or card you paid with.",
    ),
    (
      'When does the seller get my money?',
      'MVEC holds your payment until you give the courier your 6-digit delivery code. Only give the code when the items are in your hands.',
    ),
    (
      'How can I contact a seller?',
      'Open Messages and search for the store, or use the Messages link on the order.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        const PageTitle(
          eyebrow: 'Buyer',
          title: 'Help & Support',
          subtitle: 'Get help with orders, payments, delivery and refunds.',
        ),
        DataCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order problem',
                style: TextStyle(fontWeight: FontWeight.w600, color: mv.text),
              ),
              const SizedBox(height: 4),
              Text(
                'Something went wrong with an order? Open the order and choose Report a problem.',
                style: TextStyle(color: mv.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              GradientButton(
                label: 'View my orders',
                compact: true,
                onPressed: () => context.go('/orders'),
              ),
            ],
          ),
        ),
        DataCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contact MVEC',
                style: TextStyle(fontWeight: FontWeight.w600, color: mv.text),
              ),
              const SizedBox(height: 4),
              Text(
                'Questions about a payment, a delivery or your account? Send MVEC a request and follow the replies here.',
                style: TextStyle(color: mv.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              OutlineBtn(
                label: 'Send a request',
                compact: true,
                onPressed: () => context.push('/buyer/support/requests'),
              ),
            ],
          ),
        ),
        DataCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Common questions',
                style: TextStyle(fontWeight: FontWeight.w600, color: mv.text),
              ),
              for (final f in _faq)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 10),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(
                    f.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        f.$2,
                        style: TextStyle(
                          color: mv.textMuted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Used by `ProductCard` consumers that need the cart count badge elsewhere.
int cartCountOf(WidgetRef ref) =>
    ref.watch(cartProvider.select((c) => c.count));
