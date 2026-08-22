import 'package:flutter/material.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

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

RcTransactionType sectionFilterAccentType(TransactionDaySectionFilter f) {
  switch (f) {
    case TransactionDaySectionFilter.trial:
      return RcTransactionType.trial;
    case TransactionDaySectionFilter.conversion:
      return RcTransactionType.conversion;
    case TransactionDaySectionFilter.renewal:
      return RcTransactionType.renewal;
    case TransactionDaySectionFilter.subscription:
      return RcTransactionType.newSubscription;
    case TransactionDaySectionFilter.refunded:
      return RcTransactionType.refund;
    case TransactionDaySectionFilter.cancelled:
      return RcTransactionType.renewal;
  }
}

Color daySummaryPillAccent(
  BuildContext context,
  TransactionDaySectionFilter filter,
) {
  return switch (filter) {
    TransactionDaySectionFilter.refunded => transactionTypeAccentColor(
      RcTransactionType.refund,
      context,
    ),
    TransactionDaySectionFilter.cancelled => Colors.deepOrange,
    _ => transactionTypeAccentColor(sectionFilterAccentType(filter), context),
  };
}

bool sectionCountHigherIsBetter(TransactionDaySectionFilter filter) {
  return filter != TransactionDaySectionFilter.refunded &&
      filter != TransactionDaySectionFilter.cancelled;
}

Color daySummaryPlatformDistColor(
  TransactionDaySummaryPlatform p,
  ColorScheme scheme,
) {
  return switch (p) {
    TransactionDaySummaryPlatform.apple => StoreBrandIconColors.appleBlue,
    TransactionDaySummaryPlatform.google => StoreBrandIconColors.androidGreen,
    TransactionDaySummaryPlatform.web => scheme.tertiary,
    TransactionDaySummaryPlatform.other => scheme.outline,
  };
}

IconData daySummaryPlatformDistIcon(TransactionDaySummaryPlatform p) {
  return switch (p) {
    TransactionDaySummaryPlatform.apple => Icons.apple,
    TransactionDaySummaryPlatform.google => Icons.android_rounded,
    TransactionDaySummaryPlatform.web => Icons.language_rounded,
    TransactionDaySummaryPlatform.other => Icons.storefront_outlined,
  };
}

/// Share per platform: store icon + colorized % (fixed order; omitted when count is 0).
class DaySummaryPlatformShare extends StatelessWidget {
  const DaySummaryPlatformShare({super.key, required this.platformCounts});

  final Map<TransactionDaySummaryPlatform, int> platformCounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final total = TransactionDaySummaryPlatform.values.fold<int>(
      0,
      (s, p) => s + (platformCounts[p] ?? 0),
    );
    if (total <= 0) return const SizedBox.shrink();

    final dotStyle = tt.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final basePctStyle = tt.labelSmall?.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final children = <Widget>[];
    for (final p in TransactionDaySummaryPlatform.values) {
      final count = platformCounts[p] ?? 0;
      if (count <= 0) continue;
      if (children.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('\u00b7', style: dotStyle),
          ),
        );
      }
      final pct = ((count * 100) / total).round().clamp(0, 100);
      final tint = daySummaryPlatformDistColor(p, scheme);
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(daySummaryPlatformDistIcon(p), size: 12, color: tint),
            const SizedBox(width: 3),
            Text('$pct%', style: basePctStyle?.copyWith(color: tint)),
          ],
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        runSpacing: 2,
        children: children,
      ),
    );
  }
}

class DayTypeCountSummary extends StatelessWidget {
  final List<RcTransaction> transactions;
  final List<RcTransaction>? previousDayTransactions;
  final Set<TransactionDaySectionFilter> selectedFilters;
  final void Function(TransactionDaySectionFilter filter) onFilterCellTap;
  final VoidCallback? onClearFilter;
  final bool enableFilterTaps;

  const DayTypeCountSummary({
    super.key,
    required this.transactions,
    required this.previousDayTransactions,
    required this.selectedFilters,
    required this.onFilterCellTap,
    required this.onClearFilter,
    this.enableFilterTaps = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = aggregateDayCounts(transactions);
    final p = previousDayTransactions != null
        ? aggregateDayCounts(previousDayTransactions!)
        : null;
    final platformBySection = platformCountsByDaySection(transactions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            DaySummaryStatCell(
              label: 'Trials',
              count: n.trials,
              previousCount: p?.trials,
              filter: TransactionDaySectionFilter.trial,
              selected: selectedFilters.contains(
                TransactionDaySectionFilter.trial,
              ),
              allowTap: enableFilterTaps,
              onTap: onFilterCellTap,
              platformCounts:
                  platformBySection[TransactionDaySectionFilter.trial]!,
            ),
            DaySummaryStatCell(
              label: 'Conversions',
              count: n.conversions,
              previousCount: p?.conversions,
              filter: TransactionDaySectionFilter.conversion,
              selected: selectedFilters.contains(
                TransactionDaySectionFilter.conversion,
              ),
              allowTap: enableFilterTaps,
              onTap: onFilterCellTap,
              platformCounts:
                  platformBySection[TransactionDaySectionFilter.conversion]!,
            ),
            DaySummaryStatCell(
              label: 'Renewals',
              count: n.renewals,
              previousCount: p?.renewals,
              filter: TransactionDaySectionFilter.renewal,
              selected: selectedFilters.contains(
                TransactionDaySectionFilter.renewal,
              ),
              allowTap: enableFilterTaps,
              onTap: onFilterCellTap,
              platformCounts:
                  platformBySection[TransactionDaySectionFilter.renewal]!,
            ),
            DaySummaryStatCell(
              label: 'Purchases',
              count: n.purchases,
              previousCount: p?.purchases,
              filter: TransactionDaySectionFilter.subscription,
              selected: selectedFilters.contains(
                TransactionDaySectionFilter.subscription,
              ),
              allowTap: enableFilterTaps,
              onTap: onFilterCellTap,
              platformCounts:
                  platformBySection[TransactionDaySectionFilter.subscription]!,
            ),
            DaySummaryStatCell(
              label: 'Refunds',
              count: n.refunds,
              previousCount: p?.refunds,
              filter: TransactionDaySectionFilter.refunded,
              selected: selectedFilters.contains(
                TransactionDaySectionFilter.refunded,
              ),
              allowTap: enableFilterTaps,
              onTap: onFilterCellTap,
              platformCounts:
                  platformBySection[TransactionDaySectionFilter.refunded]!,
            ),
            DaySummaryStatCell(
              label: 'Cancellations',
              count: n.cancelled,
              previousCount: p?.cancelled,
              filter: TransactionDaySectionFilter.cancelled,
              selected: selectedFilters.contains(
                TransactionDaySectionFilter.cancelled,
              ),
              allowTap: enableFilterTaps,
              onTap: onFilterCellTap,
              platformCounts:
                  platformBySection[TransactionDaySectionFilter.cancelled]!,
            ),
          ],
        ),
        if (onClearFilter != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: onClearFilter,
              child: const Text('Clear filter'),
            ),
          ),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = daySummaryPillAccent(context, filter);
    final baseCard = scheme.surfaceContainerHighest.withValues(alpha: 0.38);
    final fill = Color.alphaBlend(
      accent.withValues(alpha: selected ? 0.2 : 0.1),
      baseCard,
    );
    final borderColor = selected
        ? accent.withValues(alpha: 0.72)
        : Color.alphaBlend(
            accent.withValues(alpha: 0.28),
            scheme.outlineVariant.withValues(alpha: 0.45),
          );
    final prev = previousCount;
    final higherIsBetter = sectionCountHigherIsBetter(filter);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: allowTap ? () => onTap(filter) : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            color: fill,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1,
                      color: selected ? accent : scheme.onSurface,
                    ),
                  ),
                  if (prev != null) ...[
                    const SizedBox(width: 6),
                    DayCountTrendRow(
                      current: count,
                      previous: prev,
                      higherIsBetter: higherIsBetter,
                    ),
                  ],
                ],
              ),
              DaySummaryPlatformShare(platformCounts: platformCounts),
            ],
          ),
        ),
      ),
    );
  }
}

class DayCountTrendRow extends StatelessWidget {
  final int current;
  final int previous;
  final bool higherIsBetter;

  const DayCountTrendRow({
    super.key,
    required this.current,
    required this.previous,
    required this.higherIsBetter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = current - previous;
    final IconData icon;
    final Color accent;
    if (delta == 0) {
      icon = Icons.horizontal_rule_rounded;
      accent = theme.colorScheme.onSurfaceVariant;
    } else {
      final up = delta > 0;
      icon = up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
      final improved = higherIsBetter ? up : !up;
      accent = improved
          ? (theme.brightness == Brightness.dark
                ? const Color(0xFF81C784)
                : const Color(0xFF2E7D32))
          : theme.colorScheme.error;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 4),
        Text(
          '$previous',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
