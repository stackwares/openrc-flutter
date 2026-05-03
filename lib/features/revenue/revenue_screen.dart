import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/features/revenue/revenue_section_screen.dart';
import 'package:revenuecat/features/revenue/widgets/revenue_next_payday_proceeds_card.dart';
import 'package:revenuecat/features/revenue/widgets/revenue_insights_list.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/features/transactions/widgets/day_summary_card.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

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
    final theme = Theme.of(context);

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
        appIncludeFilter != null ||
        countryFilterActive ||
        platformFilterActive;

    final accountProjects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final windowTxsRaw = collectTransactionsInCurrentLocalMonth(state.grouped);
    final realtimeFilterSource = windowTxsRaw.isEmpty
        ? <String, List<RcTransaction>>{}
        : <String, List<RcTransaction>>{'_': windowTxsRaw};
    final canOpenRealtimeFilter = !state.isLoading &&
        collectAppFilterOptionsWithProjects(
          realtimeFilterSource,
          accountProjects,
        ).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(
          'Revenue',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
        ),
        actions: [
          if (filtersActive)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: 'Clear filters',
              onPressed: () {
                ref.read(transactionsAppIncludeFilterProvider.notifier).state =
                    null;
                ref.read(transactionsCountryFilterProvider.notifier).state =
                    null;
                ref.read(transactionsPlatformFilterProvider.notifier).state =
                    null;
              },
            ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: filtersActive ? context.colorScheme.primary : null,
            ),
            tooltip: 'Filter transactions',
            onPressed: !canOpenRealtimeFilter
                ? null
                : () async {
                    final filterSource = realtimeFilterSource;
                    final projects = await ref.read(
                      rcAccountProjectsProvider.future,
                    );
                    if (!context.mounted) return;
                    showTransactionsAppFilterSheet(
                      context: context,
                      filterSource: filterSource,
                      currentIncludeFilter: appIncludeFilter,
                      currentCountryCodes: countryFilter,
                      currentPlatforms: platformFilter,
                      accountProjects: projects,
                      onApply: (apps, countryCodes, platformFilters) {
                        ref
                                .read(
                                  transactionsAppIncludeFilterProvider.notifier,
                                )
                                .state =
                            apps;
                        ref
                                .read(transactionsCountryFilterProvider.notifier)
                                .state =
                            countryCodes;
                        ref
                                .read(
                                  transactionsPlatformFilterProvider.notifier,
                                )
                                .state =
                            platformFilters;
                      },
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: state.isLoading
                ? null
                : () => ref.read(transactionsProvider.notifier).fetchInitial(),
          ),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: context.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(state.error!, style: context.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () =>
                        ref.read(transactionsProvider.notifier).fetchInitial(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
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
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!state.realtimeLoadComplete) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(minHeight: 4),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          kRealtimeWindowSubtitle,
                          textAlign: TextAlign.start,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (commission.adjustmentEnabled) ...[
                          Text(
                            afterStoreCommissionTitle(commission),
                            textAlign: TextAlign.start,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DualCurrencyExactText(
                                  amount: netTotal,
                                  textAlign: TextAlign.start,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontSize:
                                            (theme
                                                    .textTheme
                                                    .headlineSmall
                                                    ?.fontSize ??
                                                24) *
                                            1.2,
                                        fontWeight: FontWeight.w800,
                                        color: theme.colorScheme.onSurface,
                                        letterSpacing: -0.65,
                                        height: 1.1,
                                      ),
                                ).appValueReveal(
                                  key: ValueKey(
                                    'rt_net_${netTotal}_${txs.length}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Original revenue',
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.15,
                                      fontSize:
                                          (theme
                                                  .textTheme
                                                  .labelSmall
                                                  ?.fontSize ??
                                              11) *
                                          0.92,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  DualCurrencyExactText(
                                    amount: grossTotal,
                                    applyCommissionAdjustment: false,
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      height: 1.2,
                                    ),
                                  ).appValueReveal(
                                    key: ValueKey('rt_gross_$grossTotal'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ] else
                          DualCurrencyExactText(
                            amount: netTotal,
                            textAlign: TextAlign.start,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize:
                                  (theme.textTheme.headlineSmall?.fontSize ??
                                      24) *
                                  1.2,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: -0.65,
                              height: 1.1,
                            ),
                          ).appValueReveal(
                            key: ValueKey('rt_${netTotal}_${txs.length}'),
                          ),
                        if (!state.realtimeLoadComplete) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Fetching older transactions…',
                            textAlign: TextAlign.start,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        DayTypeCountSummary(
                          transactions: txs,
                          previousDayTransactions: null,
                          selectedFilters: <TransactionDaySectionFilter>{},
                          onFilterCellTap: (f) {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (ctx) =>
                                    RealtimeSectionTransactionsScreen(
                                      windowTransactions: txs,
                                      filter: f,
                                    ),
                              ),
                            );
                          },
                          onClearFilter: null,
                          enableFilterTaps: true,
                        ),
                      ],
                    ),
                  ),
                ).appCardEntrance(),
                RealtimeNextPaydayProceedsCard(
                  allLoadedTransactions: allLoadedTxs,
                  loadedTransactionCount: allLoadedTxs.length,
                ).appCardEntrance(delay: const Duration(milliseconds: 80)),
                RealtimeRevenueInsightsList(
                  transactions: txs,
                  compactRevenueAmounts: false,
                ).appCardEntrance(delay: const Duration(milliseconds: 160)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Text(
                    'Totals include every transaction in the current local calendar month that has been loaded. '
                    'Pull to refresh to reload.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ).appCardEntrance(delay: const Duration(milliseconds: 240)),
              ],
            ),
          );
        },
      ),
    );
  }
}
