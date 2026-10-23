import 'package:flutter/material.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/animated_number.dart';
import 'package:revenuecat/widgets/delta_badge.dart';
import 'package:revenuecat/widgets/pressable_scale.dart';
import 'package:revenuecat/widgets/split_bar.dart';

/// e.g. `After 15% store commission` or `After 15% / 12% store commission` when rates differ.
String afterStoreCommissionTitle(CommissionSettings commission) {
  String fmt(double p) {
    final v = p.clamp(0.0, 100.0);
    if ((v - v.round()).abs() < 1e-6) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  final a = commission.appleCommissionPercent;
  final g = commission.googleCommissionPercent;
  final pct = (a - g).abs() < 0.05 ? '${fmt(a)}%' : '${fmt(a)}% / ${fmt(g)}%';
  return 'After $pct store commission';
}

class DayTxnCounts {
  final int trials;
  final int conversions;
  final int renewals;
  final int purchases;
  final int refunds;
  final int cancelled;

  DayTxnCounts({
    required this.trials,
    required this.conversions,
    required this.renewals,
    required this.purchases,
    required this.refunds,
    required this.cancelled,
  });
}

DayTxnCounts aggregateDayCounts(List<RcTransaction> transactions) {
  var trials = 0;
  var conversions = 0;
  var renewals = 0;
  var purchases = 0;
  var refunds = 0;
  var cancelled = 0;
  for (final tx in transactions) {
    if (tx.type == RcTransactionType.refund) {
      refunds++;
    } else if (tx.isCancelledSummaryBadge) {
      cancelled++;
    }
    switch (tx.type) {
      case RcTransactionType.trial:
        trials++;
        break;
      case RcTransactionType.conversion:
        conversions++;
        break;
      case RcTransactionType.renewal:
        renewals++;
        break;
      case RcTransactionType.newSubscription:
      case RcTransactionType.oneTimePurchase:
        purchases++;
        break;
      case RcTransactionType.refund:
      case RcTransactionType.unknown:
        break;
    }
  }
  return DayTxnCounts(
    trials: trials,
    conversions: conversions,
    renewals: renewals,
    purchases: purchases,
    refunds: refunds,
    cancelled: cancelled,
  );
}

Color daySummaryPillAccent(
  BuildContext context,
  TransactionDaySectionFilter filter,
) {
  final colors = context.appColors;
  return switch (filter) {
    TransactionDaySectionFilter.trial => colors.trial,
    TransactionDaySectionFilter.conversion => colors.conversion,
    TransactionDaySectionFilter.renewal => colors.renewal,
    TransactionDaySectionFilter.subscription => colors.purchase,
    TransactionDaySectionFilter.refunded => colors.refund,
    TransactionDaySectionFilter.cancelled => colors.cancelled,
  };
}

bool sectionCountHigherIsBetter(TransactionDaySectionFilter filter) {
  return filter != TransactionDaySectionFilter.refunded &&
      filter != TransactionDaySectionFilter.cancelled;
}

Color daySummaryPlatformDistColor(
  BuildContext context,
  TransactionDaySummaryPlatform p,
) {
  final colors = context.appColors;
  return switch (p) {
    TransactionDaySummaryPlatform.apple => colors.apple,
    TransactionDaySummaryPlatform.google => colors.google,
    TransactionDaySummaryPlatform.web => colors.web,
    TransactionDaySummaryPlatform.other => colors.otherStore,
  };
}

String daySummaryPlatformLabel(TransactionDaySummaryPlatform p) {
  return switch (p) {
    TransactionDaySummaryPlatform.apple => 'App Store',
    TransactionDaySummaryPlatform.google => 'Google Play',
    TransactionDaySummaryPlatform.web => 'Web',
    TransactionDaySummaryPlatform.other => 'Other',
  };
}

/// Short tile label (fits a third of a phone width).
String daySummaryTileLabel(TransactionDaySectionFilter filter) {
  return switch (filter) {
    TransactionDaySectionFilter.cancelled => 'Cancelled',
    _ => transactionDaySectionGridLabel(filter),
  };
}

/// Six category tiles (two rows of three). Tapping a tile reports its filter.
class DayTypeCountSummary extends StatelessWidget {
  final List<RcTransaction> transactions;
  final List<RcTransaction>? previousDayTransactions;
  final Set<TransactionDaySectionFilter> selectedFilters;
  final void Function(TransactionDaySectionFilter filter) onFilterCellTap;
  final bool enableFilterTaps;

  const DayTypeCountSummary({
    super.key,
    required this.transactions,
    required this.previousDayTransactions,
    required this.selectedFilters,
    required this.onFilterCellTap,
    this.enableFilterTaps = true,
  });

  @override
  Widget build(BuildContext context) {
    final n = aggregateDayCounts(transactions);
    final p = previousDayTransactions != null
        ? aggregateDayCounts(previousDayTransactions!)
        : null;
    final platformBySection = platformCountsByDaySection(transactions);

    int countFor(DayTxnCounts c, TransactionDaySectionFilter f) => switch (f) {
      TransactionDaySectionFilter.trial => c.trials,
      TransactionDaySectionFilter.conversion => c.conversions,
      TransactionDaySectionFilter.renewal => c.renewals,
      TransactionDaySectionFilter.subscription => c.purchases,
      TransactionDaySectionFilter.refunded => c.refunds,
      TransactionDaySectionFilter.cancelled => c.cancelled,
    };

    Widget cell(TransactionDaySectionFilter f) => DaySummaryStatCell(
      label: daySummaryTileLabel(f),
      count: countFor(n, f),
      previousCount: p == null ? null : countFor(p, f),
      filter: f,
      selected: selectedFilters.contains(f),
      allowTap: enableFilterTaps,
      onTap: onFilterCellTap,
      platformCounts: platformBySection[f]!,
    );

    Widget row(List<TransactionDaySectionFilter> filters) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.xs),
            Expanded(child: cell(filters[i])),
          ],
        ],
      ),
    );

    const f = TransactionDaySectionFilter.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(f.sublist(0, 3)),
        const SizedBox(height: AppSpace.xs),
        row(f.sublist(3, 6)),
      ],
    );
  }
}

class DaySummaryStatCell extends StatelessWidget {
  const DaySummaryStatCell({
    super.key,
    required this.label,
    required this.count,
    required this.previousCount,
    required this.filter,
    required this.selected,
    required this.allowTap,
    required this.onTap,
    required this.platformCounts,
  });

  final String label;
  final int count;
  final int? previousCount;
  final TransactionDaySectionFilter filter;
  final bool selected;
  final bool allowTap;
  final void Function(TransactionDaySectionFilter filter) onTap;
  final Map<TransactionDaySummaryPlatform, int> platformCounts;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final colors = context.appColors;
    final accent = daySummaryPillAccent(context, filter);
    final base = scheme.surfaceContainerLow;
    final fill = selected
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.12), base)
        : base;
    final prev = previousCount;
    final delta = prev == null
        ? null
        : DeltaBadge.count(
            current: count,
            previous: prev,
            higherIsBetter: sectionCountHigherIsBetter(filter),
          );
    final segments = [
      for (final p in TransactionDaySummaryPlatform.values)
        if ((platformCounts[p] ?? 0) > 0)
          SplitSegment(
            value: platformCounts[p]!.toDouble(),
            color: daySummaryPlatformDistColor(context, p),
            label: daySummaryPlatformLabel(p),
          ),
    ];
    final radius = BorderRadius.circular(AppRadius.tile);

    return Semantics(
      button: allowTap,
      selected: selected,
      label: [
        '$label $count',
        if (delta != null) delta.semanticsLabel,
      ].join(', '),
      excludeSemantics: true,
      child: PressableScale(
        enabled: allowTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: allowTap ? () => onTap(filter) : null,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.fast),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: radius,
                color: fill,
                border: Border.all(
                  color: selected ? scheme.primary : colors.hairline,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Wraps the delta under the count when text is large.
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      AnimatedCount(
                        count: count,
                        style: AppText.amount(
                          context,
                          size: 22,
                          color: count == 0
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                      ?delta,
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(height: 8),
                  if (segments.isNotEmpty)
                    SplitBar(segments: segments, height: 3)
                  else
                    const SizedBox(height: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
