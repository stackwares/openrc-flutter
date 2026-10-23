import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/revenue/revenue_next_payday_proceeds.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';
import 'package:revenuecat/widgets/share_row.dart';
import 'package:revenuecat/widgets/status_label.dart';

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
    final colors = context.appColors;
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

    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );

    return AppCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Next payouts',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                DualCurrencyExactText(
                  amount: total,
                  applyCommissionAdjustment: false,
                  style: AppText.amount(context, size: 17),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              commission.adjustmentEnabled
                  ? 'Estimated, after your store fees'
                  : 'Estimated from loaded transactions',
              style: muted,
            ),
          ),
          _NextPayoutPlatformRow(
            icon: Icons.apple,
            iconColor: colors.apple,
            storeLabel: 'App Store',
            paymentDate: est.applePayday?.paymentDate,
            accrualLine: appleAccrual,
            netUsd: est.appleNetUsd,
            pct: applePct,
            now: now,
          ).appListItemEntrance(0),
          const Divider(indent: 64),
          _NextPayoutPlatformRow(
            icon: Icons.android,
            iconColor: colors.google,
            storeLabel: 'Google Play',
            paymentDate: est.googlePayday?.paymentDate,
            accrualLine: googleAccrual,
            netUsd: est.googleNetUsd,
            pct: googlePct,
            now: now,
          ).appListItemEntrance(1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'Based on $loadedTransactionCount loaded transaction'
              '${loadedTransactionCount == 1 ? '' : 's'}. Gaps in history can lower these totals.',
              style: muted?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

String _accrualRangeShort(DateTime start, DateTime end) {
  final a = DateFormat.MMMd().format(start);
  final b = DateFormat.MMMd().format(end);
  return 'Earnings $a–$b';
}

class _NextPayoutPlatformRow extends StatelessWidget {
  const _NextPayoutPlatformRow({
    required this.icon,
    required this.iconColor,
    required this.storeLabel,
    required this.paymentDate,
    required this.accrualLine,
    required this.netUsd,
    required this.pct,
    required this.now,
  });

  final IconData icon;
  final Color iconColor;
  final String storeLabel;
  final DateTime? paymentDate;
  final String? accrualLine;
  final double netUsd;
  final double pct;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final caption = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );
    return ShareRow(
      label: storeLabel,
      pct: pct,
      barColor: iconColor,
      amount: DualCurrencyExactText(
        amount: netUsd,
        applyCommissionAdjustment: false,
        textAlign: TextAlign.end,
      ),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.icon),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: iconColor),
      ),
      details: [
        const SizedBox(height: 4),
        if (paymentDate != null)
          Row(
            children: [
              Flexible(
                child: Text(
                  'Pays ${formatPaydayAbbrev(paymentDate!)}',
                  style: caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusLabel(
                text: paydayDaysToGoLabel(paymentDate!, now),
                color: scheme.primary,
                pill: true,
              ),
            ],
          )
        else
          Text('Schedule unavailable', style: caption),
        if (accrualLine != null) ...[
          const SizedBox(height: 2),
          Text(
            accrualLine!,
            style: caption?.copyWith(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
