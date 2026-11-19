import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/auth_state.dart';
import '../../core/format.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../widgets/common.dart';

/// `/vendor/stores` — several storefronts under one seller account.
class SellerStoresPage extends StatefulWidget {
  const SellerStoresPage({super.key});

  @override
  State<SellerStoresPage> createState() => _SellerStoresPageState();
}

class _SellerStoresPageState extends State<SellerStoresPage> {
  late final _data = Loader(() => jget('/stores/mine'));
  List<Map<String, dynamic>> _categories = [];
  String _busy = '';

  @override
  void initState() {
    super.initState();
    jlist('/categories', 'categories').then((v) => mounted ? setState(() => _categories = v) : null).catchError((_) {});
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _edit(Map<String, dynamic>? s) async {
    final saved = await showFormSheet<Map<String, dynamic>>(
      context,
      title: s == null ? 'Register a store' : 'Edit ${s['storeName']}',
      subtitle: s == null ? 'Each store gets its own name, logo and contact details on Ikiguzi.' : 'Update how this storefront appears to buyers.',
      fields: [
        const FieldSpec('logo', 'Store logo', type: FieldType.image),
        const FieldSpec('storeName', 'Store name', required: true, hint: 'e.g. Kigali Tech Store'),
        FieldSpec(
          'businessCategory',
          'Business category',
          type: FieldType.select,
          placeholderOption: 'Select a category',
          options: [for (final c in _categories) (strOf(c['name']), strOf(c['name']))],
        ),
        const FieldSpec('city', 'City', hint: 'Kigali'),
        const FieldSpec('description', 'Description', type: FieldType.textarea, hint: 'Tell buyers what your store offers'),
        const FieldSpec('contactEmail', 'Contact email', type: FieldType.email, required: true),
        const FieldSpec('contactPhone', 'Contact phone', type: FieldType.phone, required: true, hint: '07xx xxx xxx'),
        const FieldSpec('businessAddress', 'Business address', hint: 'Street, building'),
        const FieldSpec('pickup', 'Pickup pin', type: FieldType.pin, help: 'Where Ikiguzi riders collect your parcels. At the store now? Use your location. Otherwise tap the exact spot.'),
        FieldSpec(
          'riderDelivery',
          'Deliver with Ikiguzi riders',
          type: FieldType.toggle,
          help: 'Buyers pay a fee by distance and the nearest rider collects each parcel. Needs the pickup pin.',
          visibleWhen: (v) => asMap(v['pickup']).isNotEmpty,
        ),
      ],
      initial:
          s == null
              // The business category was asked at sign-up: a new store starts with it.
              ? {'businessCategory': ProviderScope.containerOf(context, listen: false).read(authProvider).user?.category ?? ''}
              : {
                'storeName': strOf(s['storeName']),
                'businessCategory': strOf(s['businessCategory']),
                'description': strOf(s['description']),
                'contactEmail': strOf(s['contactEmail']),
                'contactPhone': strOf(s['contactPhone']),
                'city': strOf(asMap(s['address'])['city'], s['location'] is String ? s['location'] as String : ''),
                'businessAddress': strOf(s['businessAddress'] ?? asMap(s['address'])['street']),
                'logo': strOf(s['logo']),
                if (s['pickupLat'] != null) 'pickup': {'lat': s['pickupLat'], 'lng': s['pickupLng']},
                'riderDelivery': s['riderDelivery'] == true,
              },
      submitLabel: s == null ? 'Register store' : 'Save changes',
      onSubmit: (v) => s == null ? jpost('/stores', v) : jput('/stores/mine/${idOf(s)}', v),
    );
    if (saved != null && mounted) {
      toast(context, s == null ? '${asMap(saved['store'])['storeName'] ?? 'Store'} has been registered.' : 'Store details saved.');
      _data.reload();
    }
  }

  Future<void> _act(Map<String, dynamic> s, Future<dynamic> Function() fn) async {
    setState(() => _busy = idOf(s));
    final ok = await runAction(context, fn);
    if (mounted) setState(() => _busy = '');
    if (ok) _data.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView(
      loader: _data,
      page: true,
      builder: (d) {
        final stores = asMaps(d['stores']);
        final max = d['maxStores'];
        final atLimit = max != null && stores.length >= numOf(max);
        final register = GradientButton(label: 'Register store', icon: Icons.add_rounded, compact: true, onPressed: atLimit ? null : () => _edit(null));
        return PortalPage(
          eyebrow: 'Seller platform',
          title: 'My Stores',
          subtitle: 'Run several storefronts from one seller account. Your primary store is shown on your vendor profile.',
          onRefresh: _data.reload,
          action: register,
          children: [
            if (atLimit) Tiny('You can own up to $max stores.'),
            if (stores.isEmpty)
              EmptyState(icon: Icons.storefront_outlined, title: "You don't have a store yet", message: 'Register your first store to start listing products and receiving orders.', action: register)
            else ...[
              Tiny('${stores.length}${max != null ? ' of $max' : ''} stores'),
              for (final s in stores)
                RecordCard(
                  leading: ProductImage(src: strOf(s['logo']), size: 48, radius: 10),
                  title: strOf(s['storeName']),
                  badges: [if (s['isPrimary'] == true) const StatusChip('Primary', tone: StatusTone.good)],
                  subtitle: '/${s['slug'] ?? ''} · ${strOf(s['businessCategory'], '—')}',
                  lines: [
                    [
                      strOf(asMap(s['address'])['city'], s['location'] is String ? s['location'] as String : ''),
                      strOf(s['contactPhone']),
                      strOf(s['contactEmail']),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    '${numOf(s['productCount']).toInt()} products · since ${formatDate(s['createdAt'])}',
                  ],
                  status: Pill(s['status']),
                  actions: [
                    ActionChipBtn('Edit', icon: Icons.edit_outlined, busy: _busy == idOf(s), onPressed: () => _edit(s)),
                    if (s['isPrimary'] != true) ActionChipBtn('Make primary', busy: _busy == idOf(s), onPressed: () => _act(s, () => jpatch('/stores/mine/${idOf(s)}/primary'))),
                    if (s['isPrimary'] != true)
                      ActionChipBtn(
                        'Delete',
                        danger: true,
                        busy: _busy == idOf(s),
                        onPressed: () async {
                          if (await confirmDialog(context, 'Delete ${s['storeName']}? Its products, promotions and shipping zones move to your primary store.', confirm: 'Delete', danger: true)) {
                            await _act(s, () => jdelete('/stores/mine/${idOf(s)}'));
                          }
                        },
                      ),
                  ],
                ),
              const Tiny('Payouts, staff and your seller balance are shared across all your stores. Products without a store are listed under the primary store.'),
            ],
          ],
        );
      },
    );
  }
}

// ─── Settings ────────────────────────────────────────────────────────────────
