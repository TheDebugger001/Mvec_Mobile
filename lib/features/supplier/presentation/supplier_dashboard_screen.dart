import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_config.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../models/user.dart';
import '../../../providers/auth_provider.dart';
import '../data/supplier_workspace.dart';

class SupplierDashboardScreen extends ConsumerStatefulWidget {
  const SupplierDashboardScreen({super.key});

  @override
  ConsumerState<SupplierDashboardScreen> createState() =>
      _SupplierDashboardScreenState();
}

class _SupplierDashboardScreenState
    extends ConsumerState<SupplierDashboardScreen> {
  static const _pages = [
    ('Dashboard', Icons.dashboard_outlined),
    ('Wholesale Products', Icons.inventory_2_outlined),
    ('Inventory', Icons.warehouse_outlined),
    ('Vendor Orders', Icons.receipt_long_outlined),
    ('Notifications', Icons.notifications_none),
    ('Settings', Icons.settings_outlined),
  ];

  int _selectedPage = 0;

  void _selectPage(int index) => setState(() => _selectedPage = index);

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(supplierWorkspaceProvider);
    final user = ref.watch(currentUserProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      backgroundColor: MvColors.page,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading:
            isWide
                ? const SizedBox.shrink()
                : Builder(
                  builder:
                      (context) => IconButton(
                        tooltip: 'Open supplier navigation',
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                ),
        title: Text(_pages[_selectedPage].$1),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => _selectPage(4),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      drawer:
          isWide
              ? null
              : Drawer(
                child: _SupplierNavigation(
                  pages: _pages,
                  selectedPage: _selectedPage,
                  user: user,
                  onSelect: _selectPage,
                  onSignOut: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ),
      body: SafeArea(
        top: false,
        child: Row(
          children: [
            if (isWide)
              SizedBox(
                width: 260,
                child: _SupplierNavigation(
                  pages: _pages,
                  selectedPage: _selectedPage,
                  user: user,
                  onSelect: _selectPage,
                  onSignOut: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ),
            Expanded(
              child: workspace.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_outlined, size: 42),
                            const SizedBox(height: 12),
                            Text(
                              friendlyError(error),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  () =>
                                      ref.invalidate(supplierWorkspaceProvider),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                data:
                    (data) => _SupplierPage(
                      index: _selectedPage,
                      data: data,
                      user: user,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierNavigation extends StatelessWidget {
  const _SupplierNavigation({
    required this.pages,
    required this.selectedPage,
    required this.user,
    required this.onSelect,
    required this.onSignOut,
  });

  final List<(String, IconData)> pages;
  final int selectedPage;
  final UserRecord? user;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: MvColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MVEC',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: MvColors.primaryDeep,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'SUPPLIER PLATFORM',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: MvColors.muted,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: MvColors.soft,
                    foregroundColor: MvColors.primaryDeep,
                    child: Text(initials(user?.display ?? 'Supplier')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.display ?? 'Supplier',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'Supplier account',
                          style: TextStyle(fontSize: 11, color: MvColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final page = pages[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ListTile(
                  selected: selectedPage == index,
                  selectedTileColor: MvColors.soft,
                  selectedColor: MvColors.primaryDeep,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: Icon(page.$2, size: 20),
                  title: Text(
                    page.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    onSelect(index);
                    if (Scaffold.of(context).isDrawerOpen) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('View marketplace'),
          onTap: () => context.go('/home'),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: MvColors.dangerIcon),
          title: const Text('Sign out'),
          onTap: onSignOut,
        ),
      ],
    ),
  );
}

class _SupplierPage extends StatelessWidget {
  const _SupplierPage({
    required this.index,
    required this.data,
    required this.user,
  });
  final int index;
  final SupplierWorkspaceData data;
  final UserRecord? user;

  @override
  Widget build(BuildContext context) {
    return switch (index) {
      0 => _OverviewTab(data: data, user: user),
      1 => _ProductsTab(products: data.products),
      2 => _InventoryTab(products: data.products),
      3 => _OrdersTab(orders: data.orders),
      4 => _NotificationsTab(notifications: data.notifications),
      _ => _AccountTab(profile: data.profile),
    };
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.data, required this.user});
  final SupplierWorkspaceData data;
  final UserRecord? user;

  @override
  Widget build(BuildContext context) {
    final monthlySales = data.orders
        .where((order) => order.status == 'Completed')
        .fold<double>(0, (sum, order) => sum + order.total);
    final protectedFunds = data.orders
        .where(
          (order) => order.status != 'Pending' && order.status != 'Completed',
        )
        .fold<double>(0, (sum, order) => sum + order.total);
    final lowStock =
        data.products.where((product) => product.stock <= 15).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const _PageHeading(
              eyebrow: 'SUPPLIER PLATFORM',
              title: 'Supplier dashboard',
              subtitle: 'Supply verified MVEC vendors with wholesale products.',
            ),
            if (kDemoMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MvColors.infoBoxBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'DEMO DATA  ·  Changes stay on this device for this session',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MvColors.infoBoxText,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _Metric(
                    label: 'Wholesale products',
                    value: '${data.products.length}',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _Metric(
                    label: 'Vendor orders',
                    value: '${data.orders.length}',
                    icon: Icons.shopping_cart_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _Metric(
                    label: 'Sales',
                    value: money(monthlySales),
                    icon: Icons.bar_chart_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _Metric(
                    label: 'Protected funds',
                    value: money(protectedFunds),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: MvColors.infoBoxBg,
                border: Border.all(color: MvColors.infoBoxBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MVEC protected settlement',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: MvColors.infoBoxText,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Paid supply orders remain held until fulfillment and vendor receipt confirmation. Update the order status as supply moves through delivery.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: MvColors.infoBoxText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Metric(
              label: 'Products needing restock',
              value: '$lowStock',
              icon: Icons.warning_amber_rounded,
            ),
          ],
        );
      },
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
          color: MvColors.primaryDeep,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(color: Theme.of(context).hintColor)),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: MvColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: MvColors.primaryDeep),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({required this.products});
  final List<SupplierProduct> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PageHeading(
              eyebrow: 'SUPPLIER PLATFORM',
              title: 'Wholesale products',
              subtitle: 'Manage products that vendors can buy in bulk.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _editProduct(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add wholesale product'),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(height: 9),
          itemBuilder:
              (context, index) => _ProductTile(product: products[index]),
        ),
      ),
    ],
  );
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});
  final SupplierProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: MvColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: MvColors.soft,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child:
              product.imageUrl.isEmpty
                  ? const Icon(
                    Icons.image_outlined,
                    color: MvColors.primaryDeep,
                  )
                  : Image.network(
                    product.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, _, _) => const Icon(
                          Icons.image_not_supported_outlined,
                          color: MvColors.primaryDeep,
                        ),
                  ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit product',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        () => _editProduct(context, ref, product: product),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
              Text(
                '${product.category}  ·  MOQ ${product.minimumOrderQuantity}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${money(product.price)} wholesale  ·  ${product.stock} in stock',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (product.bulkDiscount > 0) ...[
                const SizedBox(height: 3),
                Text(
                  '${product.bulkDiscount}% bulk discount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: MvColors.successText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (product.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  product.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> _editProduct(
  BuildContext context,
  WidgetRef ref, {
  SupplierProduct? product,
}) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: product?.name ?? '');
  final category = TextEditingController(text: product?.category ?? '');
  final description = TextEditingController(text: product?.description ?? '');
  final imageUrl = TextEditingController(text: product?.imageUrl ?? '');
  final price = TextEditingController(text: product?.price.toString() ?? '');
  final stock = TextEditingController(text: product?.stock.toString() ?? '');
  final moq = TextEditingController(
    text: product?.minimumOrderQuantity.toString() ?? '1',
  );
  final bulkDiscount = TextEditingController(
    text: product?.bulkDiscount.toString() ?? '0',
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder:
        (sheetContext) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product == null
                        ? 'Add wholesale product'
                        : 'Edit wholesale product',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  _input(name, 'Product name', required: true),
                  const SizedBox(height: 10),
                  _input(category, 'Category', required: true),
                  const SizedBox(height: 10),
                  _input(description, 'Description', maxLines: 3),
                  const SizedBox(height: 10),
                  _input(
                    imageUrl,
                    'Product image URL',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _input(
                          price,
                          'Wholesale price (RWF)',
                          numeric: true,
                          required: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _input(
                          stock,
                          'Available stock',
                          numeric: true,
                          required: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _input(
                          moq,
                          'Minimum order quantity',
                          numeric: true,
                          required: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _input(
                          bulkDiscount,
                          'Bulk discount (%)',
                          numeric: true,
                          required: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      await ref
                          .read(supplierWorkspaceProvider.notifier)
                          .saveProduct(
                            SupplierProduct(
                              id: product?.id ?? '',
                              name: name.text.trim(),
                              category: category.text.trim(),
                              description: description.text.trim(),
                              imageUrl: imageUrl.text.trim(),
                              price: double.parse(price.text),
                              stock: int.parse(stock.text),
                              status: product?.status ?? 'ACTIVE',
                              minimumOrderQuantity: int.parse(moq.text),
                              bulkDiscount: double.parse(bulkDiscount.text),
                            ),
                          );
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      product == null ? 'Save product' : 'Save changes',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
  name.dispose();
  category.dispose();
  description.dispose();
  imageUrl.dispose();
  price.dispose();
  stock.dispose();
  moq.dispose();
  bulkDiscount.dispose();
}

Widget _input(
  TextEditingController controller,
  String label, {
  bool required = false,
  bool numeric = false,
  int maxLines = 1,
  TextInputType? keyboardType,
}) => TextFormField(
  controller: controller,
  maxLines: maxLines,
  keyboardType:
      keyboardType ??
      (numeric ? const TextInputType.numberWithOptions(decimal: true) : null),
  decoration: InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
  ),
  validator: (value) {
    if (required && (value == null || value.trim().isEmpty)) return 'Required';
    if (numeric &&
        value != null &&
        value.isNotEmpty &&
        num.tryParse(value) == null) {
      return 'Enter a valid number';
    }
    if ((label == 'Available stock' || label == 'Minimum order quantity') &&
        int.tryParse(value ?? '') == null) {
      return 'Use a whole number';
    }
    return null;
  },
);

class _InventoryTab extends ConsumerWidget {
  const _InventoryTab({required this.products});
  final List<SupplierProduct> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sorted = [...products]..sort((a, b) => a.stock.compareTo(b.stock));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const _PageHeading(
          eyebrow: 'INVENTORY',
          title: 'Inventory',
          subtitle: 'Monitor wholesale stock levels and restocking needs.',
        ),
        const SizedBox(height: 12),
        Text(
          'Update available quantities. Low stock is 15 units or fewer.',
          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final product in sorted) ...[
          _StockTile(product: product),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _StockTile extends ConsumerWidget {
  const _StockTile({required this.product});
  final SupplierProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: MvColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                product.stock == 0
                    ? 'Out of stock'
                    : product.stock <= 15
                    ? 'Low stock'
                    : 'In stock',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      product.stock <= 15
                          ? MvColors.warningText
                          : MvColors.successText,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Decrease stock',
          onPressed:
              product.stock == 0
                  ? null
                  : () => ref
                      .read(supplierWorkspaceProvider.notifier)
                      .updateStock(product.id, product.stock - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${product.stock}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'Increase stock',
          onPressed:
              () => ref
                  .read(supplierWorkspaceProvider.notifier)
                  .updateStock(product.id, product.stock + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.orders});
  final List<SupplierOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: _PageHeading(
          eyebrow: 'B2B ORDERS',
          title: 'Vendor orders',
          subtitle: 'Manage wholesale orders and supply fulfillment.',
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            final order = orders[index];
            final next = _nextOrderStatus(order.status);
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: MvColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.id,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _StatusLabel(order.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    order.buyer,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${order.quantity} × ${order.product}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${money(order.total)}  ·  ${DateFormat('d MMM yyyy').format(order.requestedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (next != null)
                        TextButton.icon(
                          onPressed:
                              () => ref
                                  .read(supplierWorkspaceProvider.notifier)
                                  .updateOrderStatus(order.id, next),
                          icon: const Icon(
                            Icons.local_shipping_outlined,
                            size: 16,
                          ),
                          label: Text(_actionFor(next)),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
}

String? _nextOrderStatus(String status) => switch (status.toLowerCase()) {
  'pending' => 'Confirmed',
  'confirmed' => 'Ready to ship',
  'ready to ship' => 'Shipped',
  'shipped' => 'Completed',
  _ => null,
};

String _actionFor(String next) => switch (next) {
  'Confirmed' => 'Confirm order',
  'Ready to ship' => 'Mark ready',
  'Shipped' => 'Mark shipped',
  _ => 'Complete order',
};

class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color =
        status.toLowerCase() == 'completed'
            ? MvColors.successText
            : status.toLowerCase() == 'pending'
            ? MvColors.warningText
            : MvColors.primaryDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _NotificationsTab extends ConsumerWidget {
  const _NotificationsTab({required this.notifications});
  final List<SupplierNotice> notifications;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const _PageHeading(
        eyebrow: 'COMMUNICATION',
        title: 'Notifications',
        subtitle: 'Track supplier order and inventory updates.',
      ),
      const SizedBox(height: 10),
      for (final notice in notifications) ...[
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          tileColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: MvColors.border),
          ),
          leading: Icon(
            notice.read
                ? Icons.notifications_none
                : Icons.notifications_active_outlined,
            color: notice.read ? MvColors.muted : MvColors.primaryDeep,
          ),
          title: Text(
            notice.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${notice.message}\n${DateFormat('d MMM, HH:mm').format(notice.createdAt)}',
          ),
          isThreeLine: true,
          trailing:
              notice.read
                  ? const Icon(Icons.check, size: 18)
                  : IconButton(
                    tooltip: 'Mark as read',
                    onPressed:
                        () => ref
                            .read(supplierWorkspaceProvider.notifier)
                            .markNotificationRead(notice.id),
                    icon: const Icon(Icons.done, size: 19),
                  ),
        ),
        const SizedBox(height: 8),
      ],
    ],
  );
}

class _AccountTab extends ConsumerStatefulWidget {
  const _AccountTab({required this.profile});
  final SupplierProfile profile;

  @override
  ConsumerState<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends ConsumerState<_AccountTab> {
  late final _business = TextEditingController(
    text: widget.profile.businessName,
  );
  late final _email = TextEditingController(text: widget.profile.email);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _address = TextEditingController(text: widget.profile.address);
  late bool _orderNotifications = widget.profile.orderNotifications;
  late bool _stockNotifications = widget.profile.stockNotifications;

  @override
  void dispose() {
    _business.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const _PageHeading(
        eyebrow: 'SETTINGS',
        title: 'Settings',
        subtitle: 'Manage supplier profile and marketplace preferences.',
      ),
      const SizedBox(height: 12),
      _input(_business, 'Business name', required: true),
      const SizedBox(height: 10),
      _input(_email, 'Contact email', keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 10),
      _input(_phone, 'Telephone', keyboardType: TextInputType.phone),
      const SizedBox(height: 10),
      _input(_address, 'Business address', maxLines: 2),
      const SizedBox(height: 10),
      SwitchListTile(
        value: _orderNotifications,
        contentPadding: EdgeInsets.zero,
        title: const Text('Order notifications'),
        onChanged: (value) => setState(() => _orderNotifications = value),
      ),
      SwitchListTile(
        value: _stockNotifications,
        contentPadding: EdgeInsets.zero,
        title: const Text('Low-stock notifications'),
        onChanged: (value) => setState(() => _stockNotifications = value),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () async {
          await ref
              .read(supplierWorkspaceProvider.notifier)
              .saveProfile(
                SupplierProfile(
                  businessName: _business.text.trim(),
                  email: _email.text.trim(),
                  phone: _phone.text.trim(),
                  address: _address.text.trim(),
                  orderNotifications: _orderNotifications,
                  stockNotifications: _stockNotifications,
                ),
              );
          if (context.mounted) {
            showMvSnack(context, 'Supplier account updated', success: true);
          }
        },
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save account settings'),
      ),
    ],
  );
}
