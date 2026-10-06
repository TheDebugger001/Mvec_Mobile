import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/api_config.dart';
import '../../core/utils.dart';
import '../../widgets/common.dart';

class VendorWorkspaceScreen extends ConsumerStatefulWidget {
  const VendorWorkspaceScreen({super.key, required this.path});
  final String path;

  static const paths = <String>[
    '/vendor/categories',
    '/vendor/inventory',
    '/vendor/shipping',
    '/vendor/purchases',
    '/vendor/customers',
    '/vendor/delivery',
    '/vendor/refunds',
    '/vendor/subscription',
    '/vendor/suppliers',
    '/vendor/affiliates',
    '/vendor/advertisements',
    '/vendor/promotions',
    '/vendor/reviews',
    '/vendor/reports',
    '/vendor/analytics',
    '/vendor/team',
    '/vendor/support',
  ];

  @override
  ConsumerState<VendorWorkspaceScreen> createState() => _VendorWorkspaceState();
}

class _VendorWorkspaceState extends ConsumerState<VendorWorkspaceScreen> {
  static const _titles = <String, String>{
    'categories': 'Categories',
    'inventory': 'Inventory',
    'shipping': 'Shipping',
    'stores': 'My Store',
    'purchases': 'Purchases',
    'customers': 'Customers',
    'delivery': 'Delivery & settlement',
    'refunds': 'Refunds & disputes',
    'subscription': 'Subscription',
    'suppliers': 'Find suppliers',
    'affiliates': 'Affiliate marketing',
    'advertisements': 'Advertisements',
    'promotions': 'Promotions',
    'reviews': 'Reviews',
    'reports': 'Reports',
    'analytics': 'Analytics',
    'team': 'Team / staff',
    'support': 'MVEC support',
    'messages': 'Messages',
  };

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  int _page = 1;
  bool _affiliateEnabled = true;
  final _ticket = TextEditingController();
  final _ticketReference = TextEditingController();
  final _deliveryOtp = <String, String>{};

  String get _module => widget.path.split('/').last;
  String get _title => _titles[_module] ?? 'Vendor workspace';
  bool get _editable => const {
    'stores',
    'promotions',
    'shipping',
    'team',
    'advertisements',
    'settings',
  }.contains(_module);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticket.dispose();
    _ticketReference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _affiliateEnabled =
          prefs.getBool('mvec_vendor_affiliate_enabled') ?? true;
      _rows = await _fetchLive();
    } catch (error) {
      _error = friendlyError(error);
      _rows = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLive() async {
    final response = switch (_module) {
      'categories' => await ApiClient.instance.get(
        '/categories',
        query: {'tree': 'false'},
      ),
      'inventory' => await ApiClient.instance.get('/products/vendor/me'),
      'analytics' => await ApiClient.instance.get('/products/vendor/me'),
      'refunds' => await ApiClient.instance.get(
        '/disputes/mine',
        query: {'page': 1, 'limit': 100},
      ),
      'suppliers' => await ApiClient.instance.get(
        '/suppliers',
        query: {'page': 1, 'limit': 50},
      ),
      'purchases' => await ApiClient.instance.get('/wholesale/orders/mine'),
      'delivery' => await ApiClient.instance.get('/orders/deliverable'),
      'messages' => await ApiClient.instance.get('/conversations'),
      _ => <String, dynamic>{},
    };
    final keys = switch (_module) {
      'categories' => ['categories', 'data'],
      'inventory' => ['products', 'data'],
      'analytics' => ['products', 'data'],
      'refunds' => ['cases', 'disputes', 'data'],
      'suppliers' => ['suppliers', 'data'],
      'purchases' => ['orders', 'data'],
      'delivery' => ['orders', 'data'],
      'messages' => ['conversations', 'data'],
      _ => ['data'],
    };
    return listJson(response, keys);
  }

  Future<void> _save(List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mvec_vendor_mobile_$_module', jsonEncode(rows));
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    if (_module == 'affiliates') return _affiliates();
    if (_module == 'subscription') return _subscription();
    if (_module == 'support') return _support();
    final matches =
        _rows
            .where(
              (row) =>
                  jsonEncode(row).toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();
    final pages = (matches.length / 8).ceil().clamp(1, 9999);
    final page = _page.clamp(1, pages);
    final rows = matches.skip((page - 1) * 8).take(8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'VENDOR WORKSPACE',
          title: _title,
          subtitle: _subtitle,
        ),
        if (_error != null) ErrorState(message: _error!, onRetry: _load),
        if (_module == 'purchases' && !kDemoMode)
          const DataCard(
            title: 'Purchases',
            subtitle:
                'The backend does not currently expose a vendor wholesale order-history endpoint.',
            child: SizedBox(height: 4),
          ),
        if (_module == 'delivery' && !kDemoMode)
          const DataCard(
            title: 'Delivery & settlement',
            subtitle: 'Track delivery and settlement from each order detail.',
            child: SizedBox(height: 4),
          ),
        if (_module == 'reports' || _module == 'analytics')
          const DataCard(
            title: 'Live in Analytics',
            subtitle:
                'Sales & earnings and Inventory show the live vendor data available to this account.',
            child: SizedBox(height: 4),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged:
                    (value) => setState(() {
                      _search = value;
                      _page = 1;
                    }),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search',
                  isDense: true,
                ),
              ),
            ),
            if (_editable) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _edit,
                icon: const Icon(Icons.add),
                tooltip: 'Add item',
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const SizedBox(height: 160, child: LoadingState())
        else if (rows.isEmpty)
          EmptyState(
            message:
                _error == null
                    ? 'Nothing to show yet.'
                    : 'Could not load $_title.',
          )
        else
          for (final row in rows) _rowCard(row),
        if (matches.length > 8)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: page > 1 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$page / $pages'),
              IconButton(
                onPressed: page < pages ? () => setState(() => _page++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }

  String get _subtitle => switch (_module) {
    'categories' => 'Marketplace categories and product counts.',
    'inventory' => 'Stock on hand compared with each low-stock threshold.',
    'shipping' => 'Delivery zones, fees, ETA and service status.',
    'stores' => 'Store identity, operating status and policies.',
    'purchases' => 'Wholesale stock ordered from suppliers.',
    'customers' => 'Order count, total spend and last purchase.',
    'delivery' => 'Delivery and settlement progress for vendor orders.',
    'refunds' => 'Refund and dispute cases connected to your account.',
    'suppliers' => 'Verified wholesale suppliers, ratings and contact details.',
    'promotions' => 'Discount codes, status and end dates.',
    'reviews' => 'Product ratings and responses. Moderation stays with Admin.',
    'team' => 'Seller-level staff roles and permissions.',
    'advertisements' => 'Sponsored campaign budgets and performance.',
    'reports' => 'Sales, product and inventory reporting.',
    'analytics' => 'Live product and sales performance.',
    'messages' => 'Transaction-linked conversations with buyers and suppliers.',
    'settings' =>
      'Store, business, payout, shipping, notification and security settings.',
    _ => '',
  };

  Widget _rowCard(Map<String, dynamic> row) {
    final entries =
        row.entries
            .where(
              (entry) => entry.value != null && '${entry.value}'.isNotEmpty,
            )
            .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entries.isEmpty ? _title : '${entries.first.value}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_editable)
                  IconButton(
                    onPressed: () => _edit(existing: row),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                  ),
              ],
            ),
            for (final entry in entries.skip(1))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${entry.key}: ${entry.value}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (_module == 'inventory' &&
                (row['stockQuantity'] as num? ?? 0) <=
                    (row['lowStockThreshold'] as num? ?? 5))
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Chip(label: Text('Low stock')),
              ),
            if (_module == 'suppliers')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _startConversation(row),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Message supplier'),
                ),
              ),
            if (_module == 'reviews')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _respond(row),
                  icon: const Icon(Icons.reply, size: 16),
                  label: Text(
                    '${row['response'] ?? ''}'.isEmpty
                        ? 'Respond'
                        : 'Edit response',
                  ),
                ),
              ),
            if (_module == 'delivery') _deliveryControls(row),
          ],
        ),
      ),
    );
  }

  Widget _affiliates() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHead(
        eyebrow: 'VENDOR WORKSPACE',
        title: _title,
        subtitle: 'Affiliate program performance and activity.',
      ),
      SwitchListTile(
        title: const Text('Affiliate program'),
        value: _affiliateEnabled,
        onChanged: (value) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('mvec_vendor_affiliate_enabled', value);
          setState(() => _affiliateEnabled = value);
        },
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _Metric(label: 'Affiliates', value: '28'),
          _Metric(label: 'Orders', value: '64'),
          _Metric(label: 'Commission', value: 'RWF 128k'),
          _Metric(label: 'Attributed sales', value: 'RWF 6.4M'),
        ],
      ),
      const SizedBox(height: 14),
      const DataCard(
        title: 'Program timeline',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Program created'),
            Text('2. Recruit affiliates'),
            Text('3. Approve partners'),
            Text('4. Share product links'),
            Text('5. Track referred orders'),
            Text('6. Pay commissions'),
          ],
        ),
      ),
    ],
  );

  Widget _subscription() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHead(
        eyebrow: 'VENDOR WORKSPACE',
        title: _title,
        subtitle: 'Vendor Premium plan, price and renewal.',
      ),
      const DataCard(
        title: 'Vendor Premium',
        subtitle: 'Current plan',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RWF 25,000 / month',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text('Monthly billing · Renewal managed in your store account'),
            SizedBox(height: 8),
            Chip(label: Text('ACTIVE')),
          ],
        ),
      ),
    ],
  );

  Widget _support() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHead(
        eyebrow: 'VENDOR WORKSPACE',
        title: _title,
        subtitle: 'Submit a support request or contact MVEC by SMS.',
      ),
      TextField(
        controller: _ticket,
        minLines: 4,
        maxLines: 7,
        decoration: const InputDecoration(
          labelText: 'Message',
          hintText: 'Include an optional order or transaction reference.',
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _ticketReference,
        decoration: const InputDecoration(
          labelText: 'Order / transaction reference (optional)',
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _submitTicket,
        icon: const Icon(Icons.send),
        label: const Text('Submit ticket'),
      ),
      const SizedBox(height: 12),
      const SelectableText('SMS support: +250 788 000 000'),
    ],
  );

  Future<void> _submitTicket() async {
    final text = _ticket.text.trim();
    if (text.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final tickets = prefs.getStringList('mvec_vendor_support_tickets') ?? [];
    tickets.insert(
      0,
      '${DateTime.now().toIso8601String()} | ${_ticketReference.text.trim()} | $text',
    );
    await prefs.setStringList('mvec_vendor_support_tickets', tickets);
    _ticket.clear();
    _ticketReference.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support request saved on this device.')),
      );
    }
  }

  Widget _deliveryControls(Map<String, dynamic> order) {
    final id = '${order['id'] ?? order['_id'] ?? order['order'] ?? ''}';
    final canConfirm = id.isNotEmpty && (_deliveryOtp[id] ?? '').length == 6;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              keyboardType: TextInputType.number,
              maxLength: 6,
              onChanged: (value) => setState(() => _deliveryOtp[id] = value),
              decoration: const InputDecoration(
                labelText: 'Buyer delivery OTP',
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: canConfirm ? () => _confirmDelivery(id) : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelivery(String id) async {
    try {
      await ApiClient.instance.patch(
        '/orders/$id/deliver',
        body: {'deliveryOtp': _deliveryOtp[id]},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Delivery confirmed.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  Future<void> _startConversation(Map<String, dynamic> supplier) async {
    final user =
        supplier['userId'] ??
        (supplier['user'] is Map ? supplier['user']['_id'] : supplier['user']);
    if (user == null || '$user'.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier contact is unavailable.')),
      );
      return;
    }
    try {
      await ApiClient.instance.post(
        '/conversations',
        body: {'recipientId': user},
      );
      if (mounted) context.go('/vendor/messages');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    }
  }

  Future<void> _respond(Map<String, dynamic> review) async {
    final controller = TextEditingController(
      text: '${review['response'] ?? ''}',
    );
    final response = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Respond to review'),
            content: TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (response == null) return;
    await _save([
      for (final row in _rows)
        if (identical(row, review)) {...row, 'response': response} else row,
    ]);
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final fields = const <String>[];
    final controllers = {
      for (final field in fields)
        field: TextEditingController(text: '${existing?[field] ?? ''}'),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              existing == null
                  ? 'Add ${_title.toLowerCase()}'
                  : 'Edit ${_title.toLowerCase()}',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: TextField(
                        controller: controllers[field],
                        decoration: InputDecoration(labelText: field),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(context, {
                      for (final field in fields)
                        field: controllers[field]!.text.trim(),
                    }),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (result == null) return;
    final rows = [..._rows];
    if (existing == null) {
      rows.insert(0, result);
    } else {
      rows[rows.indexOf(existing)] = result;
    }
    await _save(rows);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 155,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}
