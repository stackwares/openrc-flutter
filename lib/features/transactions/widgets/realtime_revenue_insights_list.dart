import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/features/transactions/transactions_revenue_insights_compute.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

/// Revenue breakdown for a transaction list: progress rows for share of total
/// (Transactions day view and Revenue tab).
class RealtimeRevenueInsightsList extends ConsumerWidget {
  final List<RcTransaction> transactions;

  /// When true, wraps insights in an [ExpansionTile] (collapsed by default on Transactions).
  final bool expandable;

  /// Used when [expandable] is true. Realtime tab typically leaves this `true`.
  final bool initiallyExpanded;

  /// When false (e.g. Revenue tab), revenue amounts use full grouping ($5,001.00)
  /// instead of compact ($5.1K).
  final bool compactRevenueAmounts;

  const RealtimeRevenueInsightsList({
    super.key,
    required this.transactions,
    this.expandable = false,
    this.initiallyExpanded = true,
    this.compactRevenueAmounts = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (transactions.isEmpty) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No transactions for insights',
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final commission = ref.watch(commissionSettingsProvider);
    final data = computeRevenueInsights(transactions, commission);
    final appIconOverrides = ref.watch(appIconOverridesProvider);

    final headerStyle = context.textTheme.labelMedium?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
    );

    final useCompactRevenue = compactRevenueAmounts;
    final insightsBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
          _InsightsSection(
            title: 'Platform',
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 2,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _InsightProgressRow(
                    label: 'Apple',
                    pct: data.applePct,
                    revenue: data.appleRevenue,
                    barColor: Color.lerp(
                      StoreBrandIconColors.appleBlue,
                      scheme.surface,
                      0.35,
                    )!,
                    leading: _InsightLeadingIconTile(
                      icon: Icons.apple,
                      iconColor: StoreBrandIconColors.appleBlue,
                    ),
                    compactRevenueAmounts: useCompactRevenue,
                  );
                }
                return _InsightProgressRow(
                  label: 'Google Play',
                  pct: data.googlePct,
                  revenue: data.googleRevenue,
                  barColor: Color.lerp(
                    StoreBrandIconColors.androidGreen,
                    scheme.surface,
                    0.4,
                  )!,
                  leading: _InsightLeadingIconTile(
                    icon: Icons.android,
                    iconColor: StoreBrandIconColors.androidGreen,
                  ),
                  compactRevenueAmounts: useCompactRevenue,
                );
              },
            ),
          ),
          _InsightsSection(
            title: 'New vs renewals',
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 2,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
              itemBuilder: (context, i) {
                if (i == 0) {
                  final accent = transactionTypeAccentColor(
                    RcTransactionType.newSubscription,
                    context,
                  );
                  return _InsightProgressRow(
                    label: 'New',
                    pct: data.newPct,
                    revenue: data.newRevenue,
                    barColor: accent,
                    leading: _InsightLeadingIconTile(
                      icon: Icons.add_circle_outline,
                      iconColor: accent,
                    ),
                    compactRevenueAmounts: useCompactRevenue,
                  );
                }
                final accent = transactionTypeAccentColor(
                  RcTransactionType.renewal,
                  context,
                );
                return _InsightProgressRow(
                  label: 'Renewals',
                  pct: data.renewalPct,
                  revenue: data.renewalRevenue,
                  barColor: accent,
                  leading: _InsightLeadingIconTile(
                    icon: Icons.autorenew,
                    iconColor: accent,
                  ),
                  compactRevenueAmounts: useCompactRevenue,
                );
              },
            ),
          ),
          _InsightsSection(
            title: 'Top apps',
            child: data.topApps.isEmpty
                ? _emptySectionHint(context, 'No app revenue')
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.topApps.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    itemBuilder: (context, i) {
                      final e = data.topApps[i];
                      final url = e.appId != null
                          ? appIconOverrides[e.appId]
                          : null;
                      return _InsightProgressRow(
                        label: e.label,
                        pct: e.pct,
                        revenue: e.revenue,
                        barColor: scheme.primary,
                        leading: TransactionLeadingAvatar(
                          imageUrl: url,
                          size: 36,
                          borderRadius: 8,
                          tintColor: scheme.onSurfaceVariant,
                          fallback: Icon(
                            Icons.apps_outlined,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        compactRevenueAmounts: useCompactRevenue,
                      );
                    },
                  ),
          ),
          _InsightsSection(
            title: 'Top countries',
            child: data.topCountries.isEmpty
                ? _emptySectionHint(context, 'No country data')
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.topCountries.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    itemBuilder: (context, i) {
                      final e = data.topCountries[i];
                      return _InsightProgressRow(
                        label: e.name,
                        pct: e.pct,
                        revenue: e.revenue,
                        barColor: scheme.tertiary,
                        leading: _InsightLeadingCountryEmoji(
                          countryKey: e.countryKey,
                        ),
                        compactRevenueAmounts: useCompactRevenue,
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
      ],
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      child: expandable
          ? Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: scheme.primary.withValues(alpha: 0.08),
              ),
              child: ExpansionTile(
                initiallyExpanded: initiallyExpanded,
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                expandedAlignment: Alignment.topLeft,
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                shape: const RoundedRectangleBorder(),
                collapsedShape: const RoundedRectangleBorder(),
                title: Text(
                  'REVENUE INSIGHTS',
                  style: headerStyle,
                ),
                children: [insightsBody],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  child: Text(
                    'REVENUE INSIGHTS',
                    style: headerStyle,
                  ),
                ),
                insightsBody,
              ],
            ),
    );
  }

  static Widget _emptySectionHint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Text(
        text,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InsightsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _InsightsSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Same footprint and fill as [TransactionLeadingAvatar] fallback tiles (36×8 radius).
class _InsightLeadingIconTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;

  const _InsightLeadingIconTile({
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: iconColor),
    );
  }
}

/// Flag / region emoji in the same 36×8 tile as app icons.
class _InsightLeadingCountryEmoji extends StatelessWidget {
  final String countryKey;

  const _InsightLeadingCountryEmoji({required this.countryKey});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = countryInsightLeadingEmoji(countryKey);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: const TextStyle(fontSize: 20, height: 1.05),
      ),
    );
  }
}

class _InsightProgressRow extends ConsumerWidget {
  final String label;
  final double pct;
  final double revenue;
  final Color barColor;
  final Widget leading;
  final bool compactRevenueAmounts;

  const _InsightProgressRow({
    required this.label,
    required this.pct,
    required this.revenue,
    required this.barColor,
    required this.leading,
    required this.compactRevenueAmounts,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final v = (pct / 100.0).clamp(0.0, 1.0);
    final titleStyle = context.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final captionStyle = context.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final amountStyle = context.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Align(
              alignment: Alignment.topCenter,
              child: leading,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: titleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: compactRevenueAmounts
                            ? DualCurrencyCompactText(
                                amount: revenue,
                                style: amountStyle,
                                textAlign: TextAlign.end,
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: DualCurrencyExactText(
                                  amount: revenue,
                                  applyCommissionAdjustment: false,
                                  style: amountStyle,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${pct.toStringAsFixed(1)}% of total revenue',
                  style: captionStyle,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
