import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/features/ask/ask_context.dart';
import 'package:openrc/features/ask/widgets/ask_context_chip.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/payout_history_screen.dart';
import 'package:openrc/features/revenue/revenue_next_payday_proceeds.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/dual_currency_text.dart';
import 'package:openrc/widgets/share_row.dart';
import 'package:openrc/widgets/side_panel.dart';
import 'package:openrc/widgets/status_label.dart';

class RealtimeNextPaydayProceedsCard extends ConsumerWidget {
  final List<RcTransaction> allLoadedTransactions;
  final int loadedTransactionCount;

  /// Outer margin around the card.
  final EdgeInsetsGeometry margin;

  const RealtimeNextPaydayProceedsCard({
    super.key,
    required this.allLoadedTransactions,
    required this.loadedTransactionCount,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
      margin: margin,
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
                    'revenue.nextPayouts'.tr(),
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
              'revenue.estimatedAfterFees'.tr(
                namedArgs: {
                  'apple': _pct(commission.appleCommissionPercent),
                  'google': _pct(commission.googleCommissionPercent),
                },
              ),
              style: muted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AskContextChip(
                label: 'agent.askAboutPayout'.tr(),
                onPressed: () => openAskTab(
                  ref,
                  context: AskPrefills.payout(),
                ),
              ),
            ),
          ),
          _NextPayoutPlatformRow(
            icon: Icons.apple,
            iconColor: colors.apple,
            storeLabel: 'storeNames.appStore'.tr(),
            paymentDate: est.applePayday?.paymentDate,
            projected: est.applePayday?.isProjected ?? false,
            accrualLine: appleAccrual,
            netUsd: est.appleNetUsd,
            pct: applePct,
            now: now,
          ).appListItemEntrance(0),
          const Divider(indent: 64),
          _NextPayoutPlatformRow(
            icon: Icons.android,
            iconColor: colors.google,
            storeLabel: 'storeNames.googlePlay'.tr(),
            paymentDate: est.googlePayday?.paymentDate,
            accrualLine: googleAccrual,
            netUsd: est.googleNetUsd,
            pct: googlePct,
            now: now,
          ).appListItemEntrance(1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'revenue.basedOnLoaded'.plural(loadedTransactionCount),
              style: muted?.copyWith(fontSize: 12),
            ),
          ),
          const Divider(height: 1),
          _PayoutHistoryLink(now: now).appListItemEntrance(2),
        ],
      ),
    );
  }
}

String _pct(double v) => (v - v.roundToDouble()).abs() < 1e-9
    ? '${v.round()}%'
    : '${v.toStringAsFixed(1)}%';

String _accrualRangeShort(DateTime start, DateTime end) =>
    'revenue.earningsRange'.tr(
      namedArgs: {'range': formatPaydayRange(start, end)},
    );

/// Opens the payouts each store has already made.
class _PayoutHistoryLink extends StatelessWidget {
  const _PayoutHistoryLink({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    String lastPaid(PayoutStore store) {
      final paid = paidPayouts(store, now);
      return paid.isEmpty
          ? '—'
          : DateFormat.MMMd().format(paid.last.paymentDate);
    }

    return Semantics(
      button: true,
      child: InkWell(
        onTap: () =>
            openDetail(context, (context) => const PayoutHistoryScreen()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.icon),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'revenue.payouts.title'.tr(),
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'revenue.payouts.lastPaid'.tr(
                        namedArgs: {
                          'apple': lastPaid(PayoutStore.apple),
                          'google': lastPaid(PayoutStore.google),
                        },
                      ),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextPayoutPlatformRow extends StatelessWidget {
  const _NextPayoutPlatformRow({
    required this.icon,
    required this.iconColor,
    required this.storeLabel,
    required this.paymentDate,
    this.projected = false,
    required this.accrualLine,
    required this.netUsd,
    required this.pct,
    required this.now,
  });

  final IconData icon;
  final Color iconColor;
  final String storeLabel;
  final DateTime? paymentDate;

  /// Date comes from Apple's fiscal rules, not the published calendar.
  final bool projected;
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
                  projected
                      ? 'revenue.paysAbout'.tr(
                          namedArgs: {
                            'date': formatPaydayAbbrev(paymentDate!),
                          },
                        )
                      : 'revenue.pays'.tr(
                          namedArgs: {
                            'date': formatPaydayAbbrev(paymentDate!),
                          },
                        ),
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
          Text('revenue.scheduleUnavailable'.tr(), style: caption),
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
