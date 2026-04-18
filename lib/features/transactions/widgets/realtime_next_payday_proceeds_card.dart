import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/theme/store_brand_icon_colors.dart';
import 'package:revenuecat/core/utils/store_payday_schedule.dart';
import 'package:revenuecat/features/transactions/realtime_next_payday_proceeds.dart';
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
    final est =
        computeNextPaydayProceedsEstimate(allLoadedTransactions, commission);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Next payout estimates',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              commission.adjustmentEnabled
                  ? 'Net proceeds after your store-fee settings, for the accrual window paid on each date.'
                  : 'Proceeds for each accrual window (same basis as your totals).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 420;
                final apple = _PlatformProceedsPanel(
                  icon: Icons.apple,
                  iconColor: StoreBrandIconColors.appleBlue,
                  storeLabel: 'App Store',
                  paymentDate: est.applePayday?.paymentDate,
                  netUsd: est.appleNetUsd,
                  periodLines: est.applePayday != null
                      ? [
                          'Fiscal ${DateFormat.yMMMM().format(est.applePayday!.fiscalMonthStart)}',
                          '${formatPaydayAbbrev(est.applePayday!.startDate)} – ${formatPaydayAbbrev(est.applePayday!.endDate)}',
                        ]
                      : const <String>[],
                  now: now,
                );
                final google = _PlatformProceedsPanel(
                  icon: Icons.android,
                  iconColor: StoreBrandIconColors.androidGreen,
                  storeLabel: 'Google Play',
                  paymentDate: est.googlePayday?.paymentDate,
                  netUsd: est.googleNetUsd,
                  periodLines: est.googlePayday != null
                      ? [
                          '${formatPaydayMonthYear(est.googlePayday!.earningsStart)} earnings',
                          '${formatPaydayAbbrev(est.googlePayday!.earningsStart)} – ${formatPaydayAbbrev(est.googlePayday!.earningsEnd)}',
                        ]
                      : const <String>[],
                  now: now,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: apple),
                      const SizedBox(width: 12),
                      Expanded(child: google),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    apple,
                    const SizedBox(height: 12),
                    google,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'From $loadedTransactionCount loaded transaction${loadedTransactionCount == 1 ? '' : 's'}. '
              'Only purchases in each accrual window are counted; gaps in loaded history are excluded.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.92),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformProceedsPanel extends ConsumerWidget {
  const _PlatformProceedsPanel({
    required this.icon,
    required this.iconColor,
    required this.storeLabel,
    required this.paymentDate,
    required this.netUsd,
    required this.periodLines,
    required this.now,
  });

  final IconData icon;
  final Color iconColor;
  final String storeLabel;
  final DateTime? paymentDate;
  final double netUsd;
  final List<String> periodLines;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = Color.alphaBlend(
      iconColor.withValues(alpha: 0.1),
      scheme.surfaceContainerHighest.withValues(alpha: 0.4),
    );

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (paymentDate != null) ...[
                      Text(
                        'Payout ${formatPaydayAbbrev(paymentDate!)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        paydayDaysToGoLabel(paymentDate!, now),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else
                      Text(
                        'Schedule unavailable',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (periodLines.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final line in periodLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  line,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          DualCurrencyExactText(
            amount: netUsd,
            applyCommissionAdjustment: false,
            textAlign: TextAlign.start,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.55,
              height: 1.05,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
