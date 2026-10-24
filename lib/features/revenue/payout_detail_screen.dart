import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/store_display_name.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/revenue/payout_detail_provider.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/revenue_section_screen.dart';
import 'package:openrc/features/revenue/widgets/revenue_insights_list.dart';
import 'package:openrc/features/revenue/widgets/revenue_period_hero_card.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/widgets/day_summary_card.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Revenue-tab summary for one paid store payout's earnings window.
class PayoutDetailScreen extends ConsumerWidget {
  const PayoutDetailScreen({super.key, required this.payout});

  final Payout payout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(payoutDetailTransactionsProvider(payout.period));
    final commission = ref.watch(commissionSettingsProvider);
    final txs = state.transactions;
    final earningsLabel = 'revenue.earningsRange'.tr(
      namedArgs: {
        'range': formatPaydayRange(
          payout.period.earningsStart,
          payout.period.earningsEnd,
        ),
      },
    );
    final paidDate = DateFormat.MMMd().format(payout.period.paymentDate);
    final paidLine = payout.period.isProjected
        ? 'revenue.payouts.paidAbout'.tr(namedArgs: {'date': paidDate})
        : 'revenue.payouts.paid'.tr(namedArgs: {'date': paidDate});

    final Widget body;
    if (txs.isEmpty && state.isLoading && !state.loadComplete) {
      body = const _PayoutDetailSkeleton();
    } else if (txs.isEmpty && state.error != null) {
      body = AppStateMessage.error(
        title: 'revenue.payouts.couldntLoadDetail'.tr(),
        message: state.error!,
        onRetry: () => ref
            .read(payoutDetailTransactionsProvider(payout.period).notifier)
            .load(),
      );
    } else {
      final netTotal = netRevenueSum(txs, commission);
      final grossTotal = grossRevenueSum(txs);
      body = _PayoutDetailBody(
        earningsLabel: earningsLabel,
        netTotal: netTotal,
        grossTotal: grossTotal,
        showGross: commission.adjustmentEnabled,
        loadComplete: state.loadComplete,
        transactions: txs,
        onRefresh: () => ref
            .read(payoutDetailTransactionsProvider(payout.period).notifier)
            .load(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(payout.period.store.displayLabel),
            Text(
              '$paidLine · $earningsLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: body,
    );
  }
}

class _PayoutDetailBody extends StatelessWidget {
  const _PayoutDetailBody({
    required this.earningsLabel,
    required this.netTotal,
    required this.grossTotal,
    required this.showGross,
    required this.loadComplete,
    required this.transactions,
    required this.onRefresh,
  });

  final String earningsLabel;
  final double netTotal;
  final double grossTotal;
  final bool showGross;
  final bool loadComplete;
  final List<RcTransaction> transactions;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final txs = transactions;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = AppBreakpoints.centeringInset(
          constraints.maxWidth,
          maxWidth: AppBreakpoints.readableWidth + 2 * AppSpace.gutter,
        );
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              inset,
              AppSpace.xs,
              inset,
              AppSpace.xl + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: RevenuePeriodHeroCard(
                  title: earningsLabel,
                  netTotal: netTotal,
                  grossTotal: grossTotal,
                  showGross: showGross,
                  loadComplete: loadComplete,
                ).appCardEntrance(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DayTypeCountSummary(
                  transactions: txs,
                  previousDayTransactions: null,
                  selectedFilters: const <TransactionDaySectionFilter>{},
                  onFilterCellTap: (filter) {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => RealtimeSectionTransactionsScreen(
                          windowTransactions: txs,
                          filter: filter,
                          windowSubtitle: earningsLabel,
                        ),
                      ),
                    );
                  },
                ).appCardEntrance(delay: const Duration(milliseconds: 60)),
              ),
              const SizedBox(height: 12),
              RealtimeRevenueInsightsList(
                transactions: txs,
                compactRevenueAmounts: false,
              ).appCardEntrance(delay: const Duration(milliseconds: 160)),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 16),
                child: Text(
                  'revenue.payouts.detailNote'.tr(),
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PayoutDetailSkeleton extends StatelessWidget {
  const _PayoutDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget tileRow() => Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xs),
          const Expanded(
            child: AppCard(
              radius: AppRadius.tile,
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(fontSize: 12, width: 56),
                  SizedBox(height: 8),
                  Bone.text(fontSize: 22, width: 32),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    return Skeletonizer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          const AppCard(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone.text(fontSize: 13, width: 150),
                SizedBox(height: 8),
                Bone.text(fontSize: 32, width: 170),
              ],
            ),
          ),
          const SizedBox(height: 12),
          tileRow(),
          const SizedBox(height: 8),
          tileRow(),
        ],
      ),
    );
  }
}
