import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/user.dart';
import '../../portal/api.dart';
import '../../portal/kit.dart';
import '../../state/auth_state.dart';
import '../../widgets/common.dart';

// Seller helpers shared by the seller (and supplier) pages. Same rules as the
// web's pages/seller/shared.jsx.

const kDefaultCommission = 5.0;

double parsePercent(dynamic v) {
  final n = double.tryParse('${v ?? ''}'.replaceAll('%', '').trim());
  return n ?? kDefaultCommission;
}

// ─── Order flow (mirrors updateVendorOrderStatus in the backend) ─────────────

const orderFlow = ['PENDING', 'CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'];
const pickupFlow = ['PENDING', 'CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT', 'DELIVERED'];

bool isPickup(Map<String, dynamic> o) => o['shippingMethod'] == 'PICKUP';
List<String> orderFlowFor(Map<String, dynamic> o) => isPickup(o) ? pickupFlow : orderFlow;
int flowIndexOf(Map<String, dynamic> o) => orderFlowFor(o).indexOf(o['orderStatus'] == 'COMPLETED' ? 'DELIVERED' : '${o['orderStatus']}');

String flowStepLabel(Map<String, dynamic> o, String status) {
  if (isPickup(o) && status == 'READY_FOR_SHIPMENT') return 'Ready for pickup';
  if (isPickup(o) && status == 'DELIVERED') return 'Collected';
  return titleCase(status);
}

const _sellerNext = {
  'PENDING': ['CONFIRMED', 'CANCELLED'],
  'CONFIRMED': ['PROCESSING', 'CANCELLED'],
  'PROCESSING': ['READY_FOR_SHIPMENT', 'CANCELLED'],
  'READY_FOR_SHIPMENT': ['SHIPPED', 'CANCELLED'],
  'SHIPPED': ['OUT_FOR_DELIVERY'],
  'OUT_FOR_DELIVERY': <String>[],
};

bool sellerCollectsPayment(Map<String, dynamic> o) => o['source'] == 'MANUAL' && (o['paidOffline'] == true || o['paymentMethod'] == 'CASH_ON_DELIVERY');

/// What the seller can move this order to next.
List<String> sellerNextStatuses(Map<String, dynamic> o) {
  final status = '${o['orderStatus']}';
  final next = <String>[
    ...(isPickup(o) && status == 'READY_FOR_SHIPMENT' ? const ['CANCELLED'] : (_sellerNext[status] ?? const <String>[])),
  ];
  if (sellerCollectsPayment(o)) {
    final from = isPickup(o) ? const ['CONFIRMED', 'PROCESSING', 'READY_FOR_SHIPMENT'] : const ['READY_FOR_SHIPMENT', 'SHIPPED', 'OUT_FOR_DELIVERY'];
    if (from.contains(status)) next.add('DELIVERED');
  }
  return next.toSet().toList();
}

/// Cash-on-delivery manual orders: the seller records the cash received.
bool canRecordCash(Map<String, dynamic> o) =>
    o['source'] == 'MANUAL' && o['paymentMethod'] == 'CASH_ON_DELIVERY' && o['paymentStatus'] != 'PAID' && !['CANCELLED', 'REFUNDED'].contains(o['orderStatus']);

const _stepLabel = {
  'CONFIRMED': 'Accept order',
  'PROCESSING': 'Start preparing',
  'READY_FOR_SHIPMENT': 'Ready to ship',
  'SHIPPED': 'Mark shipped',
  'OUT_FOR_DELIVERY': 'Out for delivery',
  'DELIVERED': 'Mark delivered',
  'CANCELLED': 'Cancel order',
};

String stepLabelFor(Map<String, dynamic> o, String status) => isPickup(o) && status == 'READY_FOR_SHIPMENT' ? 'Ready for pickup' : (_stepLabel[status] ?? titleCase(status));

const orderTabs = <(String, String, List<String>?)>[
  ('all', 'All', null),
  ('new', 'New', ['PENDING', 'CONFIRMED']),
  ('preparing', 'Preparing', ['PROCESSING', 'READY_FOR_SHIPMENT']),
  ('shipping', 'On the way', ['SHIPPED', 'OUT_FOR_DELIVERY']),
  ('done', 'Completed', ['DELIVERED', 'COMPLETED']),
  ('closed', 'Cancelled', ['CANCELLED', 'REFUNDED', 'RETURNED', 'FAILED']),
];

const cancelReasons = ['Out of stock', 'Customer asked to cancel', 'Cannot deliver to this address', 'Pricing error', 'Other'];

const _countedOut = ['CANCELLED', 'REFUNDED', 'FAILED', 'RETURNED'];
bool isRevenueOrder(Map<String, dynamic> o) => !_countedOut.contains(o['orderStatus']);

/// Asks for a cancellation reason and returns `reason` (or `reason: note`).
Future<String?> askCancelReason(BuildContext context, Map<String, dynamic> o) {
  final paid = o['paymentStatus'] == 'PAID' && o['paidOffline'] != true;
  return showFormSheet<String>(
    context,
    title: 'Cancel ${o['orderNumber'] ?? 'order'}?',
    subtitle: paid ? 'The buyer paid through MVEC: they get a full refund, and your items go back into stock.' : 'Your items go back into stock. The customer is notified.',
    fields: [
      FieldSpec('reason', 'Reason', type: FieldType.select, required: true, options: [for (final r in cancelReasons) (r, r)]),
      const FieldSpec('note', 'Note for the customer', hint: 'Optional'),
    ],
    initial: {'reason': cancelReasons.first, 'note': ''},
    submitLabel: 'Cancel order',
    danger: true,
    onSubmit: (v) async {
      final note = '${v['note'] ?? ''}'.trim();
      return note.isEmpty ? '${v['reason']}' : '${v['reason']}: $note';
    },
  );
}

// ─── Sales summaries (Analytics / Reports) ──────────────────────────────────

class SalesSummary {
  SalesSummary({
    required this.orders,
    required this.countedOrders,
    required this.gross,
    required this.paidGross,
    required this.paidOrders,
    required this.commission,
    required this.net,
    required this.averageOrder,
    required this.customers,
    required this.byStatus,
    required this.topProducts,
  });

  final int orders, countedOrders, paidOrders, customers;
  final num gross, paidGross, commission, net, averageOrder;
  final Map<String, int> byStatus;
  final List<({String name, int units, num revenue})> topProducts;
}

SalesSummary summarizeOrders(List<Map<String, dynamic>> orders, [double commissionPercent = kDefaultCommission]) {
  final counted = orders.where(isRevenueOrder).toList();
  final gross = counted.fold<num>(0, (s, o) => s + numOf(o['vendorSubtotal']));
  final paid = counted.where((o) => o['paymentStatus'] == 'PAID').toList();
  final paidGross = paid.fold<num>(0, (s, o) => s + numOf(o['vendorSubtotal']));
  final byStatus = <String, int>{};
  for (final o in orders) {
    final k = '${o['orderStatus']}';
    byStatus[k] = (byStatus[k] ?? 0) + 1;
  }
  final products = <String, ({String name, int units, num revenue})>{};
  for (final o in counted) {
    for (final it in asMaps(o['items'])) {
      final key = '${it['product'] ?? it['name']}';
      final cur = products[key] ?? (name: strOf(it['name']), units: 0, revenue: 0);
      products[key] = (name: cur.name, units: cur.units + numOf(it['quantity']).toInt(), revenue: cur.revenue + numOf(it['price']) * numOf(it['quantity']));
    }
  }
  final customers = counted.map((o) => o['user'] is Map ? idOf(o['user']) : strOf(o['user'])).where((x) => x.isNotEmpty).toSet();
  final commission = paidGross * commissionPercent / 100;
  return SalesSummary(
    orders: orders.length,
    countedOrders: counted.length,
    gross: gross,
    paidGross: paidGross,
    paidOrders: paid.length,
    commission: commission,
    net: paidGross - commission,
    averageOrder: counted.isEmpty ? 0 : gross / counted.length,
    customers: customers.length,
    byStatus: byStatus,
    topProducts: products.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue)),
  );
}

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Revenue per calendar month for the last [months] months, oldest first.
List<(String, num)> monthlyRevenue(List<Map<String, dynamic>> orders, {int months = 6, String amountKey = 'vendorSubtotal'}) {
  final now = DateTime.now();
  final buckets = <(int, int)>[for (var i = months - 1; i >= 0; i--) _monthBack(now, i)];
  final values = List<num>.filled(months, 0);
  for (final o in orders.where(isRevenueOrder)) {
    final d = parseDate(o['createdAt']);
    if (d == null) continue;
    final i = buckets.indexOf((d.year, d.month));
    if (i >= 0) values[i] += numOf(o[amountKey]);
  }
  return [for (var i = 0; i < months; i++) (_monthNames[buckets[i].$2 - 1], values[i])];
}

(int, int) _monthBack(DateTime now, int back) {
  var y = now.year, m = now.month - back;
  while (m <= 0) {
    m += 12;
    y -= 1;
  }
  return (y, m);
}

/// Horizontal share bar with label and value (`.progress-row`).
class ProgressRow extends StatelessWidget {
  const ProgressRow({super.key, required this.label, required this.fraction, required this.value});
  final String label;
  final double fraction;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: fraction.isNaN ? 0 : fraction.clamp(0, 1), minHeight: 8))),
          const SizedBox(width: 8),
          SizedBox(width: 44, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        ],
      ),
    );
  }
}

// ─── Categories ──────────────────────────────────────────────────────────────

class CategoryNode {
  CategoryNode(this.data, this.children);
  final Map<String, dynamic> data;
  final List<CategoryNode> children;
  String get id => idOf(data);
  String get name => strOf(data['name']);
}

/// Flat category list -> roots with their children, keeping API order.
List<CategoryNode> buildCategoryTree(List<Map<String, dynamic>> categories) {
  final byId = {for (final c in categories) idOf(c): CategoryNode(c, [])};
  final roots = <CategoryNode>[];
  for (final c in categories) {
    final parent = byId[idOf(c['parentId'])];
    if (parent != null && idOf(c['parentId']).isNotEmpty) {
      parent.children.add(byId[idOf(c)]!);
    } else {
      roots.add(byId[idOf(c)]!);
    }
  }
  return roots;
}

/// Category options for a select: parents, then their children indented.
List<(String, String)> categoryOptions(List<Map<String, dynamic>> categories) => [
  for (final r in buildCategoryTree(categories)) ...[(r.id, r.children.isEmpty ? r.name : '${r.name} (general)'), for (final ch in r.children) (ch.id, '   ${ch.name}')],
];

// ─── Plans (PremiumGate) ─────────────────────────────────────────────────────

/// `/plans/me`, loaded once per sign-in.
final planProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authProvider.select((a) => a.user?.id));
  try {
    return await jget('/plans/me');
  } catch (_) {
    return {'failed': true};
  }
});

/// Shows [child] when the account may use [feature]. While MVEC's paid plans
/// are off everyone may use everything; the server still checks.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({super.key, required this.feature, required this.title, required this.child, this.base = '/vendor'});
  final String feature;
  final String title;
  final Widget child;
  final String base;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider);
    return plan.when(
      loading: () => const LoadingState(),
      error: (_, __) => child,
      data: (p) {
        final allowed = asMap(asMap(p['entitlements'])['features'])[feature];
        if (p['failed'] == true || allowed != false) return child;
        final name = strOf(asMap(p['premiumFeatures'])[feature], 'This tool');
        return EmptyState(
          icon: Icons.workspace_premium_outlined,
          title: title,
          message: '$name is part of Seller Premium.',
          action: GradientButton(label: 'See plans', compact: true, onPressed: () => context.go('$base/subscription')),
        );
      },
    );
  }
}

// ─── Onboarding (RestrictedOverview + OnboardingModal) ──────────────────────

bool needsOnboarding(AppUser? u) => (u?.role == 'vendor' || u?.role == 'supplier') && u?.isOnboarded == false;

/// Banner shown above the seller/supplier overview while onboarding is
/// incomplete, or when MVEC asked for changes to the profile.
class OnboardingBanner extends ConsumerWidget {
  const OnboardingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((a) => a.user));
    if (user?.role == 'vendor' && user?.verificationStatus == 'REJECTED' && !needsOnboarding(user)) {
      return Notice(
        text: 'MVEC asked you to update your store profile',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tiny('${user!.verificationNote.isEmpty ? 'Check your business details.' : user.verificationNote} Saving your profile sends it back for review.'),
            ActionChipBtn('Fix my profile', primary: true, onPressed: () => context.go('/vendor/settings')),
          ],
        ),
      );
    }
    if (!needsOnboarding(user)) return const SizedBox.shrink();
    return Notice(
      info: true,
      text: 'Onboarding incomplete',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Tiny('Complete your business profile and wait for MVEC verification before publishing products, creating a store, or placing supply orders.'),
          ActionChipBtn('Complete onboarding', primary: true, onPressed: () => showOnboarding(context, ref)),
        ],
      ),
    );
  }
}

Future<void> showOnboarding(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authProvider).user;
  if (user == null) return;
  final categories = await jlist('/categories', 'categories').catchError((_) => <Map<String, dynamic>>[]);
  if (!context.mounted) return;
  await showFormSheet<void>(
    context,
    title: 'Complete onboarding',
    subtitle: 'Submit your complete business profile. MVEC will review it before marketplace actions are enabled.',
    fields: [
      const FieldSpec('businessName', 'Business name', required: true),
      FieldSpec('category', 'Category', type: FieldType.select, required: true, placeholderOption: 'Select a category', options: [for (final c in categories) (strOf(c['name']), strOf(c['name']))]),
      const FieldSpec('email', 'Email', type: FieldType.email, required: true),
      const FieldSpec('phone', 'Phone', type: FieldType.phone, required: true),
      const FieldSpec('location', 'Location', required: true, hint: 'City, district, or address'),
      const FieldSpec('description', 'Business description', type: FieldType.textarea, required: true),
      const FieldSpec('logoUrl', 'Business logo', type: FieldType.image, required: true),
    ],
    initial: {
      'businessName': user.businessName.isNotEmpty ? user.businessName : user.companyName,
      'category': user.category,
      'email': user.email,
      'phone': user.telephone,
      'location': '',
      'description': user.description,
      'logoUrl': user.logoUrl,
    },
    submitLabel: 'Submit for review',
    onSubmit: (v) async {
      await jpost(user.role == 'supplier' ? '/suppliers/onboard' : '/vendors/onboard', v);
      await ref.read(authProvider.notifier).refresh();
    },
  );
}

/// Picks a logo from the gallery, uploads it and returns its URL.
Future<String?> uploadOneImage(BuildContext context) async {
  try {
    final urls = await pickAndUploadImages(multiple: false);
    return urls.isEmpty ? null : urls.first;
  } catch (e) {
    if (context.mounted) toast(context, errorText(e), error: true);
    return null;
  }
}
