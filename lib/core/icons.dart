import 'package:flutter/material.dart';

/// The icon vocabulary of `Mvec_frontend/src/components/Icon.jsx`, mapped to
/// Material icons so the navigation tuples can be copied across unchanged.
IconData mvIcon(String name) {
  switch (name) {
    case 'home':
      return Icons.home_outlined;
    case 'grid':
      return Icons.grid_view_rounded;
    case 'shop':
      return Icons.storefront_outlined;
    case 'tag':
      return Icons.sell_outlined;
    case 'cart':
      return Icons.shopping_cart_outlined;
    case 'heart':
      return Icons.favorite_border_rounded;
    case 'user':
      return Icons.person_outline_rounded;
    case 'search':
      return Icons.search_rounded;
    case 'menu':
      return Icons.menu_rounded;
    case 'bell':
      return Icons.notifications_none_rounded;
    case 'settings':
      return Icons.settings_outlined;
    case 'box':
      return Icons.inventory_2_outlined;
    case 'users':
      return Icons.group_outlined;
    case 'wallet':
      return Icons.account_balance_wallet_outlined;
    case 'chart':
      return Icons.bar_chart_rounded;
    case 'plus':
      return Icons.add_rounded;
    case 'edit':
      return Icons.edit_outlined;
    case 'trash':
      return Icons.delete_outline_rounded;
    case 'arrow':
      return Icons.arrow_forward_rounded;
    case 'logout':
      return Icons.logout_rounded;
    case 'eye':
      return Icons.visibility_outlined;
    case 'check':
      return Icons.check_rounded;
    case 'sun':
      return Icons.light_mode_outlined;
    case 'moon':
      return Icons.dark_mode_outlined;
    case 'shield':
      return Icons.shield_outlined;
    case 'receipt':
      return Icons.receipt_long_outlined;
    case 'copy':
      return Icons.copy_rounded;
    default:
      return Icons.circle_outlined;
  }
}
