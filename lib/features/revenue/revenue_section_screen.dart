import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/utils/subscriber_tenure_format.dart';
import 'package:openrc/features/revenue/widgets/revenue_insights_list.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/widgets/active_filters_row.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/features/transactions/widgets/transaction_list_sort_menu.dart';
import 'package:openrc/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/transaction_list_sort_store.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/grouped_list.dart';
import 'package:openrc/widgets/shell_header.dart';
import 'package:openrc/widgets/side_panel.dart';
import 'package:openrc/services/telemetry.dart';

/// Lists transactions in the Revenue tab window for one [TransactionDaySectionFilter] category.
class RealtimeSectionTransactionsScreen extends ConsumerStatefulWidget {
  final List<RcTransaction> windowTransactions;
  final TransactionDaySectionFilter filter;

  /// Shown under the category heading. Defaults to this month so far.
  final String? windowSubtitle;

  const RealtimeSectionTransactionsScreen({
    super.key,
    required this.windowTransactions,
    required this.filter,
    this.windowSubtitle,
  });

  @override
  ConsumerState<RealtimeSectionTransactionsScreen> createState() =>
      _RealtimeSectionTransactionsScreenState();
}

class _RealtimeSectionTransactionsScreenState
    extends ConsumerState<RealtimeSectionTransactionsScreen> {
  @override
  void initState() {
    super.initState();
    Telemetry.screen('Insights');
  }

  Set<String>? _appIncludeFilter;
  Set<String>? _countryFilter;
  Set<TransactionPlatformFilter>? _platformFilter;

  List<RcTransaction> _appFilteredWindow() {
    var list = widget.windowTransactions;
    if (_appIncludeFilter != null) {
      list = list
          .where((tx) => _appIncludeFilter!.contains(appKeyForTransaction(tx)))
          .toList();
    }
    return list
        .where(
          (tx) =>
              transactionMatchesCountryFilters(tx, _countryFilter) &&
              transactionMatchesPlatformFilter(tx, _platformFilter),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final listSort = ref.watch(transactionListSortProvider);
    final appFiltered = _appFilteredWindow();
    final filtered = appFiltered
        .where((t) => transactionMatchesSectionFilter(t, widget.filter))
        .toList();
    sortMutableTransactionList(filtered, listSort);

    final tenureMap = earliestPurchaseLocalDayBySubscriberId(
      widget.windowTransactions,
    );
    final tenureInstantMap = earliestPurchaseLocalInstantBySubscriberId(
      widget.windowTransactions,
    );

    final heading =
        '${filtered.length} ${transactionDaySectionGridLabel(widget.filter)}';

    final accountProjects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final filterOptions = collectAppFilterOptionsWithProjects({
      '_': widget.windowTransactions,
    }, accountProjects);
    final canFilterApps = filterOptions.isNotEmpty;

    String emptyMessage() {
      final countryOn = _countryFilter != null && _countryFilter!.isNotEmpty;
      final platformOn = _platformFilter != null && _platformFilter!.isNotEmpty;
      final filtersOn = _appIncludeFilter != null || countryOn || platformOn;
      if (appFiltered.isEmpty && filtersOn) {
        return 'revenue.noFilterMatches'.tr();
      }
      return 'revenue.noCategoryTransactions'.tr();
    }

    final filtersOn =
        _appIncludeFilter != null ||
        (_countryFilter != null && _countryFilter!.isNotEmpty) ||
        (_platformFilter != null && _platformFilter!.isNotEmpty);

    Future<void> openFilters() async {
      final projects = await ref.read(rcAccountProjectsProvider.future);
      if (!context.mounted) return;
      showTransactionsAppFilterSheet(
        context: context,
        filterSource: {'_': widget.windowTransactions},
        currentIncludeFilter: _appIncludeFilter,
        currentCountryCodes: _countryFilter,
        currentPlatforms: _platformFilter,
        accountProjects: projects,
        onApply: (apps, countryCodes, platforms) {
          setState(() {
            _appIncludeFilter = apps;
            _countryFilter = countryCodes;
            _platformFilter = platforms;
          });
        },
      );
    }

    final inset = AppBreakpoints.centeringInset(
      MediaQuery.sizeOf(context).width,
      maxWidth: AppBreakpoints.readableWidth + 2 * AppSpace.gutter,
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(heading),
            Text(
              widget.windowSubtitle ?? 'revenue.thisMonthSoFar'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          const TransactionListSortMenuButton(),
          HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'revenue.filterTransactions'.tr(),
            badge: filtersOn,
            onPressed: canFilterApps ? openFilters : null,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            sliver: SliverToBoxAdapter(
              child: AnimatedReveal(
                visible: filtersOn,
                child: ActiveFiltersRow(
                  appCount: _appIncludeFilter?.length,
                  countryCodes: _countryFilter,
                  platforms: _platformFilter,
                  onOpenFilters: openFilters,
                  onClearApps: () => setState(() => _appIncludeFilter = null),
                  onClearCountries: () => setState(() => _countryFilter = null),
                  onClearPlatforms: () =>
                      setState(() => _platformFilter = null),
                  onClearAll: () => setState(() {
                    _appIncludeFilter = null;
                    _countryFilter = null;
                    _platformFilter = null;
                  }),
                ),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    emptyMessage(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            if (widget.filter == TransactionDaySectionFilter.trial)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 8, inset, 4),
                sliver: SliverToBoxAdapter(
                  child: RealtimeRevenueInsightsList(
                    transactions: filtered,
                    asModalEntry: true,
                    cardMargin: const EdgeInsets.symmetric(horizontal: 16),
                  ).appCardEntrance(),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              sliver: GroupedSliverList(
                itemCount: filtered.length,
                dividerIndent: kTransactionRowDividerIndent,
                itemBuilder: (context, i) {
                  final tx = filtered[i];
                  final key = rcTransactionDedupKey(tx);
                  final heroTag = key == null ? null : 'tx-section-$key';
                  return TransactionItem(
                    transaction: tx,
                    heroTag: heroTag,
                    subscriberEarliestPurchaseLocalDayById: tenureMap,
                    subscriberEarliestPurchaseLocalInstantById:
                        tenureInstantMap,
                    onTap: () => openDetail(
                      context,
                      (context) => TransactionDetailScreen(
                        transaction: tx,
                        heroTag: heroTag,
                      ),
                    ),
                  ).appListItemEntrance(i);
                },
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
