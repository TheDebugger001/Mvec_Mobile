import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/utils/app_theme.dart';

/// Orders tab: current (active) and previous orders.
///
/// The app intentionally shows empty states until the real orders API is wired
/// in; no bundled sample orders ship with the app.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Orders', style: AppTextStyles.headline(context)),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Past'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _OrdersList(activeOnly: true),
                _OrdersList(activeOnly: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.activeOnly});

  final bool activeOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: context.mv.textMuted,
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(
            activeOnly ? 'No active orders' : 'No past orders yet',
            style: AppTextStyles.title(context),
          ),
        ],
      ),
    );
  }
}
