import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/revenue/revenue_section_screen.dart';
import 'package:revenuecat/features/revenue/widgets/revenue_next_payday_proceeds_card.dart';
import 'package:revenuecat/features/revenue/widgets/revenue_insights_list.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/features/transactions/widgets/active_filters_row.dart';
import 'package:revenuecat/features/transactions/widgets/day_summary_card.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';
import 'package:revenuecat/widgets/shell_header.dart';

/// Month-to-date Revenue tab totals (local calendar month). Shares [transactionsProvider] with [TransactionsScreen].
class RealtimeTransactionsScreen extends ConsumerWidget {
  const RealtimeTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transactionsProvider);
    final commission = ref.watch(commissionSettingsProvider);
    final appIncludeFilter = ref.watch(transactionsAppIncludeFilterProvider);
    final countryFilter = ref.watch(transactionsCountryFilterProvider);
    final platformFilter = ref.watch(transactionsPlatformFilterProvider);

    final grouped = filteredGroupedByTransactionMeta(
      filteredGroupedByApps(state.grouped, appIncludeFilter),
      countryCodes: countryFilter,
      platforms: platformFilter,
    );
    final allLoadedTxs = flattenGroupedTransactionsDeduped(grouped);
    // Sum revenue from paginated `/me/transactions` merges only — not overview chart totals.
    final txs = collectTransactionsInCurrentLocalMonth(grouped);
    final grossTotal = grossRevenueSum(txs);
    final netTotal = netRevenueSum(txs, commission);

    final countryFilterActive =
        countryFilter != null && countryFilter.isNotEmpty;
    final platformFilterActive =
        platformFilter != null && platformFilter.isNotEmpty;
    final filtersActive =
        appIncludeFilter != null || countryFilterActive || platformFilterActive;

    final accountProjects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final windowTxsRaw = collectTransactionsInCurrentLocalMonth(state.grouped);
    final realtimeFilterSource = windowTxsRaw.isEmpty
        ? <String, List<RcTransaction>>{}
        : <String, List<RcTransaction>>{'_': windowTxsRaw};
    final canOpenRealtimeFilter =
        !state.isLoading &&
        collectAppFilterOptionsWithProjects(
          realtimeFilterSource,
          accountProjects,
        ).isNotEmpty;

    Future<void> openFilters() async {
      final projects = await ref.read(rcAccountProjectsProvider.future);
      if (!context.mounted) return;
      showTransactionsAppFilterSheet(
        context: context,
        filterSource: realtimeFilterSource,
        currentIncludeFilter: appIncludeFilter,
        currentCountryCodes: countryFilter,
        currentPlatforms: platformFilter,
        accountProjects: projects,
        onApply: (apps, countryCodes, platformFilters) {
          ref.read(transactionsAppIncludeFilterProvider.notifier).state = apps;
          ref.read(transactionsCountryFilterProvider.notifier).state =
              countryCodes;
          ref.read(transactionsPlatformFilterProvider.notifier).state =
              platformFilters;
        },
      );
    }

    void clearFilters() {
      ref.read(transactionsAppIncludeFilterProvider.notifier).state = null;
      ref.read(transactionsCountryFilterProvider.notifier).state = null;
      ref.read(transactionsPlatformFilterProvider.notifier).state = null;
    }

    return Scaffold(
      appBar: ShellHeader(
        title: 'Revenue',
        subtitle: DateFormat('MMMM y').format(DateTime.now()),
        actions: [
          HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter transactions',
            badge: filtersActive,
            onPressed: canOpenRealtimeFilter ? openFilters : null,
          ),
          if (ShellHeader.showsRefreshButton)
            HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onPressed: state.isLoading
                  ? null
                  : () =>
                        ref.read(transactionsProvider.notifier).fetchInitial(),
            ),
          const SettingsAppBarAction(),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoading && state.grouped.isEmpty) {
            return const TransactionsLoadingSkeleton();
          }

          if (state.error != null &&
              state.grouped.isEmpty &&
              !state.isLoading) {
            return AppStateMessage.error(
              title: 'Couldn’t load revenue',
              message: state.error!,
              onRetry: () =>
                  ref.read(transactionsProvider.notifier).fetchInitial(),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(transactionsProvider.notifier).fetchInitial(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: mainShellFloatingTabBarScrollPadding(context),
              ),
              children: [
                if (filtersActive)
                  ActiveFiltersRow(
                    appCount: appIncludeFilter?.length,
                    countryCodes: countryFilter,
                    platforms: platformFilter,
                    onOpenFilters: openFilters,
                    onClearApps: () =>
                        ref
                                .read(
                                  transactionsAppIncludeFilterProvider.notifier,
                                )
                                .state =
                            null,
                    onClearCountries: () =>
                        ref
                                .read(
                                  transactionsCountryFilterProvider.notifier,
                                )
                                .state =
                            null,
                    onClearPlatforms: () =>
                        ref
                                .read(
                                  transactionsPlatformFilterProvider.notifier,
                                )
                                .state =
                            null,
                    onClearAll: clearFilters,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _MonthHeroCard(
                    netTotal: netTotal,
                    grossTotal: grossTotal,
                    showGross: commission.adjustmentEnabled,
                    loadComplete: state.realtimeLoadComplete,
                    transactionCount: txs.length,
                  ).appCardEntrance(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DayTypeCountSummary(
                    transactions: txs,
                    previousDayTransactions: null,
                    selectedFilters: const <TransactionDaySectionFilter>{},
                    onFilterCellTap: (f) {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (ctx) => RealtimeSectionTransactionsScreen(
                            windowTransactions: txs,
                            filter: f,
                          ),
                        ),
                      );
                    },
                  ).appCardEntrance(delay: const Duration(milliseconds: 60)),
                ),
                const SizedBox(height: 12),
                RealtimeNextPaydayProceedsCard(
                  allLoadedTransactions: allLoadedTxs,
                  loadedTransactionCount: allLoadedTxs.length,
                ).appCardEntrance(delay: const Duration(milliseconds: 100)),
                RealtimeRevenueInsightsList(
                  transactions: txs,
                  compactRevenueAmounts: false,
                ).appCardEntrance(delay: const Duration(milliseconds: 160)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 16),
                  child: Text(
                    'Totals include every loaded transaction from this month. '
                    'Pull down to reload.',
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Month-to-date net total, gross before fees, and backfill progress.
class _MonthHeroCard extends StatelessWidget {
  const _MonthHeroCard({
    required this.netTotal,
    required this.grossTotal,
    required this.showGross,
    required this.loadComplete,
    required this.transactionCount,
  });

  final double netTotal;
  final double grossTotal;
  final bool showGross;
  final bool loadComplete;
  final int transactionCount;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: AppText.tabular,
    );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This month so far',
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          DualCurrencyExactText(
            amount: netTotal,
            style: AppText.amount(context, size: 34),
          ).appValueReveal(
            key: ValueKey('rt_net_${netTotal}_$transactionCount'),
          ),
          if (showGross) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Before store fees  ', style: muted),
                DualCurrencyExactText(
                  amount: grossTotal,
                  applyCommissionAdjustment: false,
                  style: muted,
                ),
              ],
            ),
          ],
          if (!loadComplete) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: 6),
            Text('Loading older transactions…', style: muted),
          ],
        ],
      ),
    );
  }
}
