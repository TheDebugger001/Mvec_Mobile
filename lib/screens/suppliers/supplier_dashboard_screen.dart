import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/supplier.dart';
import '../../providers/auth_provider.dart';
import '../../providers/supplier_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/mv_icon.dart';
import 'supplier_shell.dart';

/// Landing page for a signed-in supplier: KPI summary, verification state and
/// shortcuts into the profile and inventory screens.
class SupplierDashboardScreen extends ConsumerWidget {
  const SupplierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final profileAsync = ref.watch(supplierProfileProvider);
    final metricsAsync = ref.watch(supplierMetricsProvider);

    final firstName = (user?.display ?? '').split(' ').first;
    final name = firstName.isEmpty ? 'there' : firstName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'SUPPLIER DASHBOARD',
          title: 'Good day, $name 👋',
          subtitle: 'Track your catalogue, stock levels and verification status.',
          actions: [
            GradientButton(
              label: 'Add product',
              icon: 'plus',
              onPressed: () => context.go('/supplier/products'),
            ),
          ],
        ),
        _VerificationCard(
          profileAsync: profileAsync,
          onRetry: () => ref.invalidate(supplierProfileProvider),
        ),
        const SizedBox(height: 16),
        _metricRow(metricsAsync, ref),
        const SizedBox(height: 16),
        _lowerRow(metricsAsync, profileAsync, ref),
      ],
    );
  }

  Widget _metricRow(AsyncValue<SupplierMetrics> metricsAsync, WidgetRef ref) {
    return switch (metricsAsync) {
      AsyncLoading() => const LoadingState(),
      AsyncError(:final error) => ErrorState(
          message: friendlyError(error),
          onRetry: () => ref.invalidate(supplierMetricsProvider),
        ),
      AsyncData(:final value) => LayoutBuilder(
          builder: (context, constraints) {
            final cards = <Widget>[
              MetricCard(label: 'Products', value: numFmt(value.totalProducts), icon: 'box'),
              MetricCard(label: 'Active', value: numFmt(value.activeProducts), icon: 'check'),
              MetricCard(label: 'Low stock', value: numFmt(value.lowStockProducts), icon: 'bell'),
              MetricCard(label: 'Out of stock', value: numFmt(value.outOfStockProducts), icon: 'trash'),
            ];
            if (constraints.maxWidth >= 860) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < cards.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: cards[i]),
                      const SizedBox(width: 14),
                      Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      _ => const LoadingState(),
    };
  }

  Widget _lowerRow(
    AsyncValue<SupplierMetrics> metricsAsync,
    AsyncValue<SupplierDetail?> profileAsync,
    WidgetRef ref,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final performance = _performanceCard(metricsAsync, ref);
          final profile = _profileCard(context, profileAsync, ref);
        if (constraints.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: performance),
              const SizedBox(width: 16),
              Expanded(child: profile),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [performance, const SizedBox(height: 16), profile],
        );
      },
    );
  }

  Widget _performanceCard(AsyncValue<SupplierMetrics> metricsAsync, WidgetRef ref) {
    return DataCard(
      title: 'Stock overview',
      subtitle: 'Derived from your catalogue',
      child: switch (metricsAsync) {
        AsyncData(:final value) => Column(
            children: [
              _StatRow('Units in stock', numFmt(value.totalUnitsInStock)),
              _StatRow('Catalog value', money(value.totalCatalogValue)),
              _StatRow('Low stock', numFmt(value.lowStockProducts)),
              _StatRow('Out of stock', numFmt(value.outOfStockProducts)),
            ],
          ),
        AsyncLoading() => const LoadingState(),
        AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierMetricsProvider),
          ),
        _ => const LoadingState(),
      },
    );
  }

  Widget _profileCard(BuildContext context, AsyncValue<SupplierDetail?> profileAsync, WidgetRef ref) {
    return DataCard(
      title: 'Business profile',
      subtitle: 'Keep your details current for faster verification',
      trailing: OutlineMvButton(
        label: 'Edit',
        icon: 'edit',
        onPressed: () => context.go('/supplier/profile'),
      ),
      child: switch (profileAsync) {
        // No profile yet — the verification card already prompts for onboarding.
        AsyncData(value: null) => const InfoBox(
            'No business profile yet. Set one up so buyers can find your catalogue.',
            icon: 'edit',
          ),
        AsyncData(:final value?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyValueGrid(entries: profileEntries(value)),
              const SizedBox(height: 16),
              GradientButton(
                label: 'Manage products',
                icon: 'box',
                expanded: true,
                onPressed: () => context.go('/supplier/products'),
              ),
            ],
          ),
        AsyncLoading() => const LoadingState(),
        AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierProfileProvider),
          ),
        _ => const LoadingState(),
      },
    );
  }
}

List<MapEntry<String, String>> profileEntries(SupplierDetail s) => [
      MapEntry('Business', s.businessName ?? '—'),
      MapEntry('Email', s.email ?? '—'),
      MapEntry('Phone', s.phone ?? '—'),
      MapEntry('Rating', s.ratingAvg == null ? '—' : '★ ${s.ratingAvg!.toStringAsFixed(1)}'),
      if (s.publicId != null) MapEntry('Supplier ID', s.publicId!),
    ];

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
          ),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Verification / status card. Shows where the supplier sits in the review
/// pipeline and what to do next.
class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.profileAsync, required this.onRetry});

  final AsyncValue<SupplierDetail?> profileAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (profileAsync) {
      // A null profile is the not-yet-onboarded state, not a failure.
      AsyncData(value: null) => const InfoBox(
          'Set up your business profile to start selling on MVEC.',
          icon: 'shield',
        ),
      AsyncData(:final value?) => _card(context, value),
      AsyncLoading() => const InfoBox('Loading your verification status…', icon: 'shield'),
      AsyncError(:final error) => ErrorState(message: friendlyError(error), onRetry: onRetry),
      _ => const InfoBox('Loading your verification status…', icon: 'shield'),
    };
  }

  Widget _card(BuildContext context, SupplierDetail s) {
    final (label, message, action) = switch (s.verificationStatus?.toUpperCase()) {
      'VERIFIED' => (
          'Verified',
          'Your business is verified. You can list products and receive orders.',
          null,
        ),
      'PENDING' || 'UNDER_REVIEW' => (
          'In review',
          'Your documents are with the MVEC team. We will notify you once reviewed.',
          null,
        ),
      'REJECTED' => (
          'Rejected',
          'Your verification was rejected. Correct the details below and contact support to ask for a review.',
          'Update profile',
        ),
      _ => (
          'Action required',
          'Complete your business information and submit for verification to start selling.',
          'Set up profile',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MvColors.infoBoxBg,
        border: Border.all(color: MvColors.infoBoxBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MvIcon('shield', size: 22, color: MvColors.primaryDeep),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    StatusPill(status: s.verificationStatus, label: titleCase(s.effectiveStatus)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(message, style: const TextStyle(fontSize: 12.5, color: MvColors.infoBoxText, height: 1.45)),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  GradientButton(
                    label: action,
                    icon: 'arrow',
                    onPressed: () => context.go('/supplier/profile'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
