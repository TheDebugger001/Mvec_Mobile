import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/app_theme.dart';
import '../../data/models/vendor_model.dart';
import '../providers/home_provider.dart';
import '../Widgets/vendor_card.dart';

/// Vendors tab: list of marketplace stores, with a detail sheet.
class VendorsScreen extends StatelessWidget {
  const VendorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    final vendors = provider.vendors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Vendors', style: AppTextStyles.headline(context)),
        ),
        Expanded(
          child: vendors.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: vendors.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final vendor = vendors[index];
                    return VendorCard(
                      width: double.infinity,
                      vendor: vendor,
                      onTap: () => _showVendorDetail(context, vendor),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showVendorDetail(BuildContext context, Vendor vendor) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _VendorDetailSheet(vendor: vendor),
    );
  }
}

class _VendorDetailSheet extends StatelessWidget {
  const _VendorDetailSheet({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final description =
        vendor.description.isEmpty ? 'No description provided.' : vendor.description;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: AppColors.primaryDeep, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    vendor.name,
                    style: AppTextStyles.title(context).copyWith(fontSize: 18),
                  ),
                ),
                if (vendor.isVerified)
                  const Icon(Icons.verified_rounded,
                      color: AppColors.primaryDeep, size: 20),
              ],
            ),
            const Divider(height: 24),
            Text(description,
                style: AppTextStyles.bodySecondary(context)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Stat(
                  icon: Icons.star_rounded,
                  label: 'Rating ${vendor.rating.toStringAsFixed(1)}',
                ),
                _Stat(
                  icon: Icons.chat_bubble_outline,
                  label: '${vendor.reviewCount} reviews',
                ),
                _Stat(
                  icon: Icons.inventory_2_outlined,
                  label: '${vendor.productCount} products',
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Store page coming soon')),
                  );
                },
                child: const Text('Visit Store'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primaryDeep),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption(context)),
      ],
    );
  }
}