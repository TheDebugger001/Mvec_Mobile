import 'package:flutter/material.dart';
import '../../portal/kit.dart';
import 'verification_list.dart';

/// `/admin/vendors` — seller verification.
class AdminSellersPage extends StatelessWidget {
  const AdminSellersPage({super.key});

  @override
  Widget build(BuildContext context) => const PortalPage(
    eyebrow: 'People & stores',
    title: 'Sellers',
    subtitle: 'Verify sellers, see what is missing from their profile, and suspend or reactivate stores.',
    children: [VerificationList(kind: 'seller')],
  );
}

// ─── Suppliers: verification, wholesale, quotes, bank payouts ──────────────
