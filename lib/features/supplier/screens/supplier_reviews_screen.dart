import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../widgets/common.dart';
import '../models/supplier_insights.dart';
import '../supplier_dependencies.dart';
import '../widgets/supplier_finance_widgets.dart';

/// Buyer feedback on the supplier's business: the average rating, the star
/// distribution, and every review with the supplier's public reply.
class SupplierReviewsScreen extends ConsumerWidget {
  const SupplierReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(supplierReviewsProvider);
    final summaryAsync = ref.watch(supplierReviewSummaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'REVIEWS',
          title: 'Buyer feedback',
          subtitle:
              'What the vendors buying your wholesale catalogue say about you.',
        ),
        switch (summaryAsync) {
          AsyncLoading() => const SizedBox(height: 120, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierReviewsProvider),
          ),
          AsyncData(:final value) => _summaryCard(context, value),
          _ => const SizedBox(height: 120, child: LoadingState()),
        },
        const SizedBox(height: 14),
        switch (reviewsAsync) {
          AsyncLoading() => const SizedBox(height: 200, child: LoadingState()),
          AsyncError(:final error) => ErrorState(
            message: friendlyError(error),
            onRetry: () => ref.invalidate(supplierReviewsProvider),
          ),
          AsyncData(:final value) => DataCard(
            title: 'Reviews',
            subtitle:
                value.isEmpty
                    ? 'No buyer reviews yet.'
                    : '${plural(value.length, 'review')} · '
                        '${value.where((r) => r.hasReply).length} answered.',
            child:
                value.isEmpty
                    ? const EmptyState(
                      message:
                          'Vendors can review your business once an order is '
                          'delivered.',
                    )
                    : Column(
                      children: [
                        for (var i = 0; i < value.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: context.mv.border),
                          SupplierReviewTile(review: value[i]),
                        ],
                      ],
                    ),
          ),
          _ => const SizedBox(height: 200, child: LoadingState()),
        },
      ],
    );
  }

  Widget _summaryCard(BuildContext context, SupplierReviewSummary summary) {
    if (summary.total == 0) {
      return const DataCard(
        title: 'Rating',
        child: EmptyState(message: 'No ratings to average yet.'),
      );
    }

    return DataCard(
      title: 'Rating',
      subtitle:
          '${plural(summary.total, 'review')} · '
          '${(summary.positiveShare * 100).toStringAsFixed(0)}% rated 4 stars '
          'or higher',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final score = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary.average.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: context.mv.text,
                ),
              ),
              const SizedBox(height: 6),
              SupplierRatingStars(rating: summary.average.round(), size: 16),
              const SizedBox(height: 6),
              Text(
                'out of 5',
                style: TextStyle(fontSize: 11, color: context.mv.textMuted),
              ),
            ],
          );

          final bars = Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var stars = 5; stars >= 1; stars--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '$stars★',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.mv.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: summary.percentFor(stars) / 100,
                              minHeight: 7,
                              backgroundColor: context.mv.surfaceMuted,
                              valueColor: const AlwaysStoppedAnimation(
                                MvColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${summary.distribution[5 - stars]}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.mv.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

          if (constraints.maxWidth <= 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [score, const SizedBox(height: 16), bars],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [score, const SizedBox(width: 28), bars],
          );
        },
      ),
    );
  }
}
