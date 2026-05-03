import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/revenue/revenue_next_payday_proceeds.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

class RealtimeNextPaydayProceedsCard extends ConsumerWidget {
  final List<RcTransaction> allLoadedTransactions;
  final int loadedTransactionCount;

  const RealtimeNextPaydayProceedsCard({
    super.key,
    required this.allLoadedTransactions,
    required this.loadedTransactionCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commission = ref.watch(commissionSettingsProvider);
    final est = computeNextPaydayProceedsEstimate(
      allLoadedTransactions,
      commission,
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();

    final total = est.appleNetUsd + est.googleNetUsd;
    final totalNonZero = total.abs() > 1e-9;
    double share(double part) =>
        totalNonZero ? (part / total * 100).clamp(0.0, 100.0) : 0.0;
    final applePct = share(est.appleNetUsd);
    final googlePct = share(est.googleNetUsd);

    final appleAccrual = est.applePayday != null
        ? _accrualRangeShort(
            est.applePayday!.startDate,
            est.applePayday!.endDate,
          )
        : null;
    final googleAccrual = est.googlePayday != null
        ? _accrualRangeShort(
            est.googlePayday!.earningsStart,
            est.googlePayday!.earningsEnd,
          )
        : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.payments_outlined, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NEXT PAYOUT ESTIMATES',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.55,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DualCurrencyExactText(
                  amount: total,
                  applyCommissionAdjustment: false,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              commission.adjustmentEnabled
                  ? 'Net after your store-fee settings · share of combined next-window total'
                  : 'Share of combined next-window total',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _NextPayoutPlatformRow(
            icon: Icons.apple,
            iconColor: StoreBrandIconColors.appleBlue,
            storeLabel: 'App Store',
            paymentDate: est.applePayday?.paymentDate,
            accrualLine: appleAccrual,
            netUsd: est.appleNetUsd,
            pct: applePct,
            barColor: Color.lerp(
              StoreBrandIconColors.appleBlue,
              scheme.surface,
              0.35,
            )!,
            now: now,
          ).appListItemEntrance(0),
          Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          _NextPayoutPlatformRow(
            icon: Icons.android,
            iconColor: StoreBrandIconColors.androidGreen,
            storeLabel: 'Google Play',
            paymentDate: est.googlePayday?.paymentDate,
            accrualLine: googleAccrual,
            netUsd: est.googleNetUsd,
            pct: googlePct,
            barColor: Color.lerp(
              StoreBrandIconColors.androidGreen,
              scheme.surface,
              0.4,
            )!,
            now: now,
          ).appListItemEntrance(1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              '$loadedTransactionCount loaded transaction'
              '${loadedTransactionCount == 1 ? '' : 's'} · gaps in history may lower totals',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    ).appCardEntrance();
  }
}

String _accrualRangeShort(DateTime start, DateTime end) {
  final a = DateFormat.MMMd().format(start);
  final b = DateFormat.MMMd().format(end);
  return 'Accrual $a–$b';
}

class _NextPayoutPlatformRow extends ConsumerWidget {
  const _NextPayoutPlatformRow({
    required this.icon,
    required this.iconColor,
    required this.storeLabel,
    required this.paymentDate,
    required this.accrualLine,
    required this.netUsd,
    required this.pct,
    required this.barColor,
    required this.now,
  });

  final IconData icon;
  final Color iconColor;
  final String storeLabel;
  final DateTime? paymentDate;
  final String? accrualLine;
  final double netUsd;
  final double pct;
  final Color barColor;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
    final v = (pct / 100.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Align(
              alignment: Alignment.topCenter,
              child: _LeadingIconTile(icon: icon, iconColor: iconColor),
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
                        storeLabel,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DualCurrencyExactText(
                      amount: netUsd,
                      applyCommissionAdjustment: false,
                      style: amountStyle,
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (paymentDate != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'Payout ${formatPaydayAbbrev(paymentDate!)}',
                          style: captionStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DaysToGoBadge(
                        label: paydayDaysToGoLabel(paymentDate!, now),
                        scheme: scheme,
                        textStyle: theme.textTheme.labelSmall,
                      ),
                    ],
                  )
                else
                  Text(
                    'Schedule unavailable',
                    style: captionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (accrualLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    accrualLine!,
                    style: captionStyle?.copyWith(
                      fontSize: (captionStyle.fontSize ?? 12) * 0.95,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${pct.toStringAsFixed(1)}% of next-payout total',
                  style: captionStyle,
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
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

class _DaysToGoBadge extends StatelessWidget {
  const _DaysToGoBadge({
    required this.label,
    required this.scheme,
    required this.textStyle,
  });

  final String label;
  final ColorScheme scheme;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.38)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: textStyle?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

class _LeadingIconTile extends StatelessWidget {
  const _LeadingIconTile({required this.icon, required this.iconColor});

  final IconData icon;
  final Color iconColor;

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
