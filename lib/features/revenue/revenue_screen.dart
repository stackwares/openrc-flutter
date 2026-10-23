import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/shell_insets.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/revenue/revenue_section_screen.dart';
import 'package:openrc/features/revenue/widgets/revenue_next_payday_proceeds_card.dart';
import 'package:openrc/features/revenue/widgets/revenue_insights_list.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/active_filters_row.dart';
import 'package:openrc/features/transactions/widgets/day_summary_card.dart';
import 'package:openrc/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:openrc/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/animated_number.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/shell_header.dart';

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
        title: 'revenue.title'.tr(),
        subtitle: DateFormat.yMMMM().format(DateTime.now()),
        actions: [
          HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'revenue.filterTransactions'.tr(),
            badge: filtersActive,
            onPressed: canOpenRealtimeFilter ? openFilters : null,
          ),
          if (ShellHeader.showsRefreshButton)
            HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'revenue.refresh'.tr(),
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
              title: 'revenue.couldntLoad'.tr(),
              message: state.error!,
              onRetry: () =>
                  ref.read(transactionsProvider.notifier).fetchInitial(),
            );
          }

          // The month at a glance, and where its money will be paid.
          final summary = <Widget>[
            AnimatedReveal(
              visible: filtersActive,
              child: ActiveFiltersRow(
                appCount: appIncludeFilter?.length,
                countryCodes: countryFilter,
                platforms: platformFilter,
                onOpenFilters: openFilters,
                onClearApps: () =>
                    ref
                            .read(transactionsAppIncludeFilterProvider.notifier)
                            .state =
                        null,
                onClearCountries: () =>
                    ref.read(transactionsCountryFilterProvider.notifier).state =
                        null,
                onClearPlatforms: () =>
                    ref
                            .read(transactionsPlatformFilterProvider.notifier)
                            .state =
                        null,
                onClearAll: clearFilters,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _MonthHeroCard(
                netTotal: netTotal,
                grossTotal: grossTotal,
                showGross: commission.adjustmentEnabled,
                loadComplete: state.realtimeLoadComplete,
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
          ];

          // Where it came from: stores, apps, countries, products.
          final breakdown = <Widget>[
            RealtimeRevenueInsightsList(
              transactions: txs,
              compactRevenueAmounts: false,
            ).appCardEntrance(delay: const Duration(milliseconds: 160)),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 16),
              child: Text(
                ShellHeader.showsRefreshButton
                    ? 'revenue.totalsNoteRefresh'.tr()
                    : 'revenue.totalsNotePullDown'.tr(),
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ];

          Future<void> refresh() =>
              ref.read(transactionsProvider.notifier).fetchInitial();
          final bottom = mainShellFloatingTabBarScrollPadding(context);

          Widget column(List<Widget> children, {double inset = 0}) =>
              RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, bottom),
                  children: children,
                ),
              );

          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Wide: the summary beside the breakdown, each scrolling.
              if (width >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: (width * 0.45).clamp(380.0, 520.0),
                      child: column(summary),
                    ),
                    Expanded(
                      child: column([const SizedBox(height: 8), ...breakdown]),
                    ),
                  ],
                );
              }
              return column(
                [...summary, ...breakdown],
                inset: AppBreakpoints.centeringInset(
                  width,
                  maxWidth: AppBreakpoints.readableWidth + 2 * AppSpace.gutter,
                ),
              );
            },
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
  });

  final double netTotal;
  final double grossTotal;
  final bool showGross;
  final bool loadComplete;

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
            'revenue.thisMonthSoFar'.tr(),
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedExactAmount(
            amount: netTotal,
            countFromZero: true,
            style: AppText.amount(context, size: 34),
          ),
          if (showGross) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('revenue.beforeStoreFees'.tr(), style: muted),
                AnimatedExactAmount(
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
            Text('revenue.loadingOlder'.tr(), style: muted),
          ],
        ],
      ),
    );
  }
}
