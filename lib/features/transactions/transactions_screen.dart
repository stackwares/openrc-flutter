import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/core/utils/subscriber_tenure_format.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';
import 'package:revenuecat/features/transactions/realtime_next_payday_proceeds.dart';
import 'package:revenuecat/features/transactions/realtime_section_transactions_screen.dart';
import 'package:revenuecat/features/transactions/widgets/realtime_next_payday_proceeds_card.dart';
import 'package:revenuecat/features/transactions/widgets/realtime_revenue_insights_list.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';
import 'package:skeletonizer/skeletonizer.dart';

class TransactionsState {
  /// Local calendar day being viewed (`yyyy-MM-dd`).
  final String selectedDayKey;

  final Map<String, List<RcTransaction>> grouped;
  final Map<String, double> dailyTotals;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int? firstPurchaseMs;
  final int? lastPurchaseMs;
  final String? error;

  /// Preload steps for the Revenue tab (1 = first page loaded, then +1 per backfill page).
  final int realtimeLoadStep;
  final bool realtimeLoadComplete;

  const TransactionsState({
    required this.selectedDayKey,
    this.grouped = const {},
    this.dailyTotals = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.firstPurchaseMs,
    this.lastPurchaseMs,
    this.error,
    this.realtimeLoadStep = 0,
    this.realtimeLoadComplete = false,
  });

  TransactionsState copyWith({
    String? selectedDayKey,
    Map<String, List<RcTransaction>>? grouped,
    Map<String, double>? dailyTotals,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? firstPurchaseMs,
    int? lastPurchaseMs,
    String? error,
    int? realtimeLoadStep,
    bool? realtimeLoadComplete,
  }) => TransactionsState(
    selectedDayKey: selectedDayKey ?? this.selectedDayKey,
    grouped: grouped ?? this.grouped,
    dailyTotals: dailyTotals ?? this.dailyTotals,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    firstPurchaseMs: firstPurchaseMs ?? this.firstPurchaseMs,
    lastPurchaseMs: lastPurchaseMs ?? this.lastPurchaseMs,
    error: error,
    realtimeLoadStep: realtimeLoadStep ?? this.realtimeLoadStep,
    realtimeLoadComplete: realtimeLoadComplete ?? this.realtimeLoadComplete,
  );
}

/// Matches [Kedi](https://github.com/sereisoglu/Kedi): small first page + `end_date`,
/// then pagination with `start_from` only (no date range on follow-up requests).
/// Stop when a page returns no transactions.
const int _kediFirstPageLimit = 20;
const int _kediPaginationLimit = 100;

/// Upper bound for the first-page `/me/transactions` query (`end_date`) — matches
/// [Kedi](https://github.com/sereisoglu/Kedi) (`Date().byAdding(.day, value: 7)`).
String _kediEndDateString() {
  final n = DateTime.now();
  final end = DateTime(n.year, n.month, n.day).add(const Duration(days: 7));
  return DateFormat('yyyy-MM-dd').format(end);
}

int? _purchaseDateMs(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final d = DateTime.tryParse(s.trim());
  return d?.millisecondsSinceEpoch;
}

bool _isPurchaseInstantInFuture(RcTransaction tx) {
  final p = tx.purchaseDate?.trim();
  if (p == null || p.isEmpty) return false;
  final dt = DateTime.tryParse(p);
  if (dt == null) return false;
  return dt.toLocal().isAfter(DateTime.now());
}

List<RcTransaction> _collectFutureTransactions({
  required Map<String, List<RcTransaction>> groupedForList,
  required TransactionDaySectionFilter? sectionFilter,
}) {
  final out = <RcTransaction>[];
  final seen = <String>{};
  for (final tx in groupedForList.values.expand((e) => e)) {
    if (!_isPurchaseInstantInFuture(tx)) continue;
    if (sectionFilter != null &&
        !transactionMatchesSectionFilter(tx, sectionFilter)) {
      continue;
    }
    final k = rcTransactionDedupKey(tx);
    if (k != null) {
      if (seen.contains(k)) continue;
      seen.add(k);
    }
    out.add(tx);
  }
  out.sort((a, b) {
    final ma = _purchaseDateMs(a.purchaseDate) ?? 0;
    final mb = _purchaseDateMs(b.purchaseDate) ?? 0;
    return ma.compareTo(mb);
  });
  return out;
}

/// Oldest [RcTransaction.purchaseDate] on the page (cursor fallback if API omits
/// `last_purchase_ms`).
int? _oldestPurchaseMsInTransactions(List<RcTransaction> raw) {
  int? m;
  for (final tx in raw) {
    final ms = _purchaseDateMs(tx.purchaseDate);
    if (ms == null) continue;
    if (m == null || ms < m) m = ms;
  }
  return m;
}

int? _nextCursorFromResponse(List<RcTransaction> raw, int? apiLastPurchaseMs) {
  if (apiLastPurchaseMs != null) return apiLastPurchaseMs;
  final oldest = _oldestPurchaseMsInTransactions(raw);
  if (oldest == null) return null;
  return oldest - 1;
}

String _dayKeyFromPurchaseDate(String dateStr) {
  try {
    final dt = DateTime.tryParse(dateStr);
    if (dt != null) {
      final local = dt.toLocal();
      return DateFormat('yyyy-MM-dd').format(local);
    }
  } catch (_) {}
  return dateStr;
}

void _mergeRawIntoGrouped(
  Map<String, List<RcTransaction>> grouped,
  List<RcTransaction> raw,
) {
  final byDay = _groupByDateStatic(raw);
  for (final entry in byDay.entries) {
    grouped.putIfAbsent(entry.key, () => []);
    _mergeTransactionsDeduping(grouped[entry.key]!, entry.value);
  }
}

Map<String, List<RcTransaction>> _groupByDateStatic(
  List<RcTransaction> transactions,
) {
  final map = <String, List<RcTransaction>>{};
  for (final tx in transactions) {
    final date = tx.purchaseDate ?? 'Unknown';
    final dayKey = _dayKeyFromPurchaseDate(date);
    map.putIfAbsent(dayKey, () => []).add(tx);
  }
  return map;
}

void _mergeTransactionsDeduping(
  List<RcTransaction> into,
  List<RcTransaction> incoming,
) {
  final seen = <String>{};
  for (final tx in into) {
    final k = rcTransactionDedupKey(tx);
    if (k != null) seen.add(k);
  }
  for (final tx in incoming) {
    final k = rcTransactionDedupKey(tx);
    if (k != null && seen.contains(k)) continue;
    if (k != null) seen.add(k);
    into.add(tx);
  }
}

class TransactionsNotifier extends StateNotifier<TransactionsState> {
  final Ref _ref;

  TransactionsNotifier(this._ref)
    : super(TransactionsState(selectedDayKey: localTodayDayKey()));

  int _backfillGeneration = 0;
  bool _backfillRunning = false;

  void setSelectedDayKey(String dayKey) {
    if (!isIsoCalendarDayKey(dayKey) || dayKey == state.selectedDayKey) return;
    state = state.copyWith(
      selectedDayKey: dayKey,
      error: null,
      isLoadingMore: false,
    );
    unawaited(backfillIncompleteCalendarDays());
  }

  /// Recomputes [TransactionsState.dailyTotals] after commission settings change.
  void syncTotalsWithCommission() {
    if (state.grouped.isEmpty) return;
    state = state.copyWith(dailyTotals: _calculateDailyTotals(state.grouped));
  }

  Future<void> fetchInitial() => fetchSelectedDay();

  /// Full reload (pull-to-refresh): same as Kedi’s first fetch — small limit,
  /// `end_date` only, then pagination uses `start_from` alone.
  Future<void> fetchSelectedDay() async {
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      error: null,
      realtimeLoadStep: 0,
      realtimeLoadComplete: false,
    );
    _backfillGeneration++;
    final gen = _backfillGeneration;
    try {
      final api = _ref.read(rcApiServiceProvider);
      final request = RcTransactionsRequest(
        limit: _kediFirstPageLimit,
        endDate: _kediEndDateString(),
      );
      final response = await api.transactions(request);
      final raw = response.transactions ?? [];
      final grouped = <String, List<RcTransaction>>{};
      _mergeRawIntoGrouped(grouped, raw);
      final dailyTotals = _calculateDailyTotals(grouped);
      final nextCursor = _nextCursorFromResponse(raw, response.lastPurchaseMs);
      final hasMorePages = raw.isNotEmpty && nextCursor != null;
      final preloadBoundaryMet = realtimeTabPreloadBoundaryReached(grouped);
      final realtimeDone = !hasMorePages || preloadBoundaryMet;
      state = state.copyWith(
        grouped: grouped,
        dailyTotals: dailyTotals,
        isLoading: false,
        isLoadingMore: false,
        hasMore: hasMorePages,
        firstPurchaseMs: response.firstPurchaseMs,
        lastPurchaseMs: hasMorePages ? nextCursor : null,
        realtimeLoadStep: realtimeDone ? kRealtimeLoadTarget : 1,
        realtimeLoadComplete: realtimeDone,
      );
      if (hasMorePages && !preloadBoundaryMet && gen == _backfillGeneration) {
        unawaited(backfillIncompleteCalendarDays(gen, true));
      }
    } on DioException catch (e) {
      _handleAuthError(e);
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: _extractErrorMessage(e),
        realtimeLoadStep: 0,
        realtimeLoadComplete: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: 'Failed to load transactions',
        realtimeLoadStep: 0,
        realtimeLoadComplete: false,
      );
    }
  }

  /// Fetches the next page (older transactions). Returns false if the request
  /// did not complete successfully (caller may stop retry loops).
  Future<bool> _performFetchMorePage() async {
    if (state.isLoadingMore || !state.hasMore) return false;
    if (state.lastPurchaseMs == null) {
      state = state.copyWith(hasMore: false);
      return false;
    }

    state = state.copyWith(isLoadingMore: true);
    final prevCursor = state.lastPurchaseMs!;
    try {
      final api = _ref.read(rcApiServiceProvider);
      final request = RcTransactionsRequest(
        limit: _kediPaginationLimit,
        startFrom: prevCursor,
      );
      final response = await api.transactions(request);
      final raw = response.transactions ?? [];
      final existingGrouped = Map<String, List<RcTransaction>>.from(
        state.grouped,
      );
      _mergeRawIntoGrouped(existingGrouped, raw);

      final dailyTotals = _calculateDailyTotals(existingGrouped);
      final nextCursor = raw.isNotEmpty
          ? _nextCursorFromResponse(raw, response.lastPurchaseMs)
          : null;
      final hasMorePages = raw.isNotEmpty && nextCursor != null;

      state = state.copyWith(
        grouped: existingGrouped,
        dailyTotals: dailyTotals,
        isLoadingMore: false,
        hasMore: hasMorePages,
        firstPurchaseMs: state.firstPurchaseMs ?? response.firstPurchaseMs,
        lastPurchaseMs: hasMorePages ? nextCursor : null,
      );
      return true;
    } on DioException catch (e) {
      _handleAuthError(e);
      state = state.copyWith(isLoadingMore: false);
      return false;
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
      return false;
    }
  }

  Future<void> fetchMore() async {
    await _performFetchMorePage();
    unawaited(backfillIncompleteCalendarDays());
  }

  /// Keeps calling [_performFetchMorePage] while [state.hasMore] and under
  /// [kRealtimeBackfillMaxPages]. When [onlyThroughCurrentMonth] is true (initial
  /// Revenue preload), stops once [realtimeTabPreloadBoundaryReached] is true
  /// (current local month + Apple next-payout accrual window).
  Future<void> backfillIncompleteCalendarDays([
    int? capturedGen,
    bool onlyThroughCurrentMonth = false,
  ]) async {
    final gen = capturedGen ?? _backfillGeneration;
    if (_backfillRunning) return;
    _backfillRunning = true;
    try {
      var pages = 0;
      while (pages < kRealtimeBackfillMaxPages &&
          gen == _backfillGeneration &&
          !state.isLoading &&
          state.hasMore) {
        if (onlyThroughCurrentMonth &&
            realtimeTabPreloadBoundaryReached(state.grouped)) {
          break;
        }
        while (state.isLoadingMore && gen == _backfillGeneration) {
          await Future<void>.delayed(const Duration(milliseconds: 24));
        }
        if (gen != _backfillGeneration || state.isLoading || !state.hasMore) {
          break;
        }
        final ok = await _performFetchMorePage();
        if (!ok) break;
        pages++;
        if (gen == _backfillGeneration) {
          state = state.copyWith(realtimeLoadStep: state.realtimeLoadStep + 1);
        }
        if (onlyThroughCurrentMonth &&
            realtimeTabPreloadBoundaryReached(state.grouped)) {
          break;
        }
      }
    } finally {
      _backfillRunning = false;
      if (gen == _backfillGeneration) {
        state = state.copyWith(
          realtimeLoadComplete: true,
          realtimeLoadStep: kRealtimeLoadTarget,
        );
      }
    }
  }

  void _handleAuthError(DioException e) {
    final rcError = _ref.read(rcApiServiceProvider).parseError(e);
    if (rcError?.code == AppConstants.rcErrorInvalidAuthToken ||
        rcError?.code == AppConstants.rcErrorExpiredAuthToken) {
      _ref.read(rcAuthServiceProvider).signOut();
    }
  }

  String? _extractErrorMessage(DioException e) {
    final rcError = _ref.read(rcApiServiceProvider).parseError(e);
    return rcError?.message ?? 'Request failed';
  }

  Map<String, double> _calculateDailyTotals(
    Map<String, List<RcTransaction>> grouped,
  ) {
    final commission = _ref.read(commissionSettingsProvider);
    final totals = <String, double>{};
    for (final entry in grouped.entries) {
      totals[entry.key] = netRevenueSum(entry.value, commission);
    }
    return totals;
  }
}

final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, TransactionsState>((ref) {
      final notifier = TransactionsNotifier(ref);
      ref.listen<CommissionSettings>(commissionSettingsProvider, (prev, next) {
        notifier.syncTotalsWithCommission();
      });
      return notifier;
    });

/// Shared app filter for the Transactions (day) and Revenue tabs.
final transactionsAppIncludeFilterProvider = StateProvider<Set<String>?>(
  (ref) => null,
);

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scrollController = ScrollController();

  /// Distance from the end of the list that triggers the next page.
  static const _loadMoreLeadPx = 420.0;

  TransactionDaySectionFilter? _sectionFilter;

  /// Expandable "Future transactions" (today only); collapsed by default.
  bool _futureTransactionsExpanded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final state = ref.read(transactionsProvider);
    if (!state.hasMore || state.isLoading) return;
    if (state.isLoadingMore) return;

    final pos = _scrollController.position;
    final maxExt = pos.maxScrollExtent;
    final nearEnd = maxExt <= 0 ? true : pos.pixels >= maxExt - _loadMoreLeadPx;
    if (nearEnd) {
      ref.read(transactionsProvider.notifier).fetchMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsProvider);
    final appIncludeFilter = ref.watch(transactionsAppIncludeFilterProvider);
    final theme = Theme.of(context);
    final dateLabel = _dayHeaderDateLabel(state.selectedDayKey);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(
          dateLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: appIncludeFilter != null
                  ? context.colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter by app',
            onPressed:
                state.isLoading ||
                    (state.grouped[state.selectedDayKey] ?? []).isEmpty
                ? null
                : () => _showAppFilterSheet(context, state),
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
      body: _buildDayTab(context, state),
    );
  }

  Widget _buildDayTab(BuildContext context, TransactionsState state) {
    final commission = ref.watch(commissionSettingsProvider);
    final appIncludeFilter = ref.watch(transactionsAppIncludeFilterProvider);
    if (state.isLoading && state.grouped.isEmpty) {
      return const TransactionsLoadingSkeleton();
    }

    if (state.error != null && state.grouped.isEmpty && !state.isLoading) {
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

    final selectedKey = state.selectedDayKey;
    final rawDayTxs = state.grouped[selectedKey] ?? [];
    final groupedForList = filteredGroupedByApps(
      state.grouped,
      appIncludeFilter,
    );
    final allForDay = groupedForList[selectedKey] ?? [];

    if (appIncludeFilter != null && rawDayTxs.isNotEmpty && allForDay.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_list_off_outlined,
                size: 48,
                color: context.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No transactions for the selected apps',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  ref
                          .read(transactionsAppIncludeFilterProvider.notifier)
                          .state =
                      null;
                  setState(() => _sectionFilter = null);
                },
                child: const Text('Show all apps'),
              ),
            ],
          ),
        ),
      );
    }

    final sectionFiltered = _sectionFilter != null;
    final todayKey = localTodayDayKey();
    final viewingToday = selectedKey == todayKey;
    var transactions = sectionFiltered
        ? allForDay
              .where(
                (tx) => transactionMatchesSectionFilter(tx, _sectionFilter!),
              )
              .toList()
        : allForDay;
    if (viewingToday) {
      transactions = transactions
          .where((tx) => !_isPurchaseInstantInFuture(tx))
          .toList();
    }

    final theme = Theme.of(context);
    final prevKey = _previousCalendarDayKey(selectedKey);
    final canGoNext = selectedKey.compareTo(todayKey) < 0;
    final groupedForHeader = filteredGroupedByApps(
      state.grouped,
      appIncludeFilter,
    );
    final headerDailyTotals = dailyTotalsForGrouped(
      groupedForHeader,
      commission,
    );
    final headerDaily = headerDailyTotals[selectedKey] ?? 0;
    final headerPrevTotal = prevKey != null ? headerDailyTotals[prevKey] : null;
    final previousDayForSummary = prevKey != null
        ? (groupedForList[prevKey] ?? <RcTransaction>[])
        : null;

    final subscriberEarliestPurchaseDay =
        earliestPurchaseLocalDayBySubscriberId(
          state.grouped.values.expand((e) => e),
        );

    final futureTxs = viewingToday
        ? _collectFutureTransactions(
            groupedForList: groupedForList,
            sectionFilter: sectionFiltered ? _sectionFilter : null,
          )
        : <RcTransaction>[];

    final children = <Widget>[
      Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous day',
                    onPressed: state.isLoading || prevKey == null
                        ? null
                        : () => _goToDay(prevKey),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Revenue',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        DualCurrencyExactText(
                          amount: headerDaily,
                          textAlign: TextAlign.center,
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
                        ),
                        const SizedBox(height: 4),
                        if (headerPrevTotal != null)
                          Center(
                            child: _PrevDayRevenueRow(
                              previousTotal: headerPrevTotal,
                              currentTotal: headerDaily,
                            ),
                          )
                        else
                          Text(
                            'Previous day: —',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next day',
                    onPressed: state.isLoading || !canGoNext
                        ? null
                        : () {
                            final n = _nextCalendarDayKey(selectedKey);
                            if (n != null) _goToDay(n);
                          },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DayTypeCountSummary(
                transactions: allForDay,
                previousDayTransactions: previousDayForSummary,
                selectedFilter: sectionFiltered ? _sectionFilter : null,
                onSelectFilter: (filter) {
                  setState(() {
                    if (_sectionFilter == filter) {
                      _sectionFilter = null;
                    } else {
                      _sectionFilter = filter;
                    }
                  });
                },
                onClearFilter: sectionFiltered
                    ? () {
                        setState(() => _sectionFilter = null);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
      RealtimeRevenueInsightsList(
        transactions: allForDay,
        expandable: true,
        initiallyExpanded: false,
      ),
      if (futureTxs.isNotEmpty)
        _FutureTransactionsSection(
          transactions: futureTxs,
          expanded: _futureTransactionsExpanded,
          onExpandedChanged: (v) {
            setState(() => _futureTransactionsExpanded = v);
          },
          subscriberEarliestPurchaseLocalDayById: subscriberEarliestPurchaseDay,
          onOpenTransaction: (tx) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (context) => TransactionDetailScreen(transaction: tx),
              ),
            );
          },
        ),
    ];

    for (final tx in transactions) {
      children.add(
        TransactionItem(
          transaction: tx,
          subscriberEarliestPurchaseLocalDayById: subscriberEarliestPurchaseDay,
          inSectionCard: false,
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (context) => TransactionDetailScreen(transaction: tx),
              ),
            );
          },
        ),
      );
    }

    if (state.hasMore) {
      if (state.isLoadingMore) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Skeletonizer(
              child: Column(
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Bone.circle(size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Bone.text(fontSize: 14),
                              const SizedBox(height: 6),
                              Bone.text(fontSize: 12, width: 140),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Center(
              child: Text(
                'Swipe up for more',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }
      final runway = math.max(280.0, MediaQuery.sizeOf(context).height * 0.35);
      children.add(SizedBox(height: runway));
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(transactionsProvider.notifier).fetchInitial(),
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: mainShellFloatingTabBarScrollPadding(context),
        ),
        children: children,
      ),
    );
  }

  void _goToDay(String dayKey) {
    setState(() {
      _sectionFilter = null;
      _futureTransactionsExpanded = false;
    });
    ref.read(transactionsProvider.notifier).setSelectedDayKey(dayKey);
  }

  String _dayHeaderDateLabel(String dayKey) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dayKey);
      return DateFormat('EEE, MMM d, yyyy').format(date);
    } catch (_) {
      return dayKey;
    }
  }

  void _showAppFilterSheet(BuildContext context, TransactionsState state) {
    final dayTxs = state.grouped[state.selectedDayKey] ?? [];
    final filterSource = <String, List<RcTransaction>>{
      if (dayTxs.isNotEmpty) state.selectedDayKey: dayTxs,
    };
    final current = ref.read(transactionsAppIncludeFilterProvider);
    showTransactionsAppFilterSheet(
      context: context,
      filterSource: filterSource,
      currentIncludeFilter: current,
      onApply: (next) {
        ref.read(transactionsAppIncludeFilterProvider.notifier).state = next;
        setState(() => _sectionFilter = null);
      },
    );
  }
}

/// e.g. `After 15% store commission` or `After 15% / 12% store commission` when rates differ.
String _afterStoreCommissionTitle(CommissionSettings commission) {
  String fmt(double p) {
    final v = p.clamp(0.0, 100.0);
    if ((v - v.round()).abs() < 1e-6) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  final a = commission.appleCommissionPercent;
  final g = commission.googleCommissionPercent;
  final pct = (a - g).abs() < 0.05 ? '${fmt(a)}%' : '${fmt(a)}% / ${fmt(g)}%';
  return 'After $pct store commission';
}

/// Month-to-date Revenue tab totals (local calendar month). Shares [transactionsProvider] with [TransactionsScreen].
class RealtimeTransactionsScreen extends ConsumerWidget {
  const RealtimeTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transactionsProvider);
    final commission = ref.watch(commissionSettingsProvider);
    final appIncludeFilter = ref.watch(transactionsAppIncludeFilterProvider);
    final theme = Theme.of(context);

    final grouped = filteredGroupedByApps(state.grouped, appIncludeFilter);
    final allLoadedTxs = flattenGroupedTransactionsDeduped(grouped);
    // Sum revenue from paginated `/me/transactions` merges only — not overview chart totals.
    final txs = collectTransactionsInCurrentLocalMonth(grouped);
    final grossTotal = grossRevenueSum(txs);
    final netTotal = netRevenueSum(txs, commission);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Revenue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              kRealtimeWindowSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                height: 1.15,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: appIncludeFilter != null
                  ? context.colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter by app',
            onPressed: state.isLoading || txs.isEmpty
                ? null
                : () {
                    final windowTxs = collectTransactionsInCurrentLocalMonth(
                      state.grouped,
                    );
                    final filterSource = windowTxs.isEmpty
                        ? <String, List<RcTransaction>>{}
                        : <String, List<RcTransaction>>{'_': windowTxs};
                    showTransactionsAppFilterSheet(
                      context: context,
                      filterSource: filterSource,
                      currentIncludeFilter: appIncludeFilter,
                      onApply: (next) {
                        ref
                                .read(
                                  transactionsAppIncludeFilterProvider.notifier,
                                )
                                .state =
                            next;
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
                        if (commission.adjustmentEnabled) ...[
                          Text(
                            _afterStoreCommissionTitle(commission),
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
                        _DayTypeCountSummary(
                          transactions: txs,
                          previousDayTransactions: null,
                          selectedFilter: null,
                          onSelectFilter: (f) {
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
                          allowTapWhenEmpty: true,
                        ),
                      ],
                    ),
                  ),
                ),
                RealtimeNextPaydayProceedsCard(
                  allLoadedTransactions: allLoadedTxs,
                  loadedTransactionCount: allLoadedTxs.length,
                ),
                RealtimeRevenueInsightsList(
                  transactions: txs,
                  compactRevenueAmounts: false,
                ),
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
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String? _previousCalendarDayKey(String dayKey) {
  if (!isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateFormat('yyyy-MM-dd').parse(dayKey);
    return DateFormat('yyyy-MM-dd').format(d.subtract(const Duration(days: 1)));
  } catch (_) {
    return null;
  }
}

String? _nextCalendarDayKey(String dayKey) {
  if (!isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateFormat('yyyy-MM-dd').parse(dayKey);
    return DateFormat('yyyy-MM-dd').format(d.add(const Duration(days: 1)));
  } catch (_) {
    return null;
  }
}

class _FutureTransactionsSection extends StatelessWidget {
  final List<RcTransaction> transactions;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final Map<String, DateTime> subscriberEarliestPurchaseLocalDayById;
  final void Function(RcTransaction tx) onOpenTransaction;

  const _FutureTransactionsSection({
    required this.transactions,
    required this.expanded,
    required this.onExpandedChanged,
    required this.subscriberEarliestPurchaseLocalDayById,
    required this.onOpenTransaction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FUTURE TRANSACTIONS',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${transactions.length} scheduled after now',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            for (final tx in transactions)
              TransactionItem(
                transaction: tx,
                subscriberEarliestPurchaseLocalDayById:
                    subscriberEarliestPurchaseLocalDayById,
                inSectionCard: true,
                onTap: () => onOpenTransaction(tx),
              ),
          ],
        ],
      ),
    );
  }
}

class _PrevDayRevenueRow extends StatelessWidget {
  final double previousTotal;
  final double currentTotal;

  const _PrevDayRevenueRow({
    required this.previousTotal,
    required this.currentTotal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const eps = 1e-6;
    final diff = currentTotal - previousTotal;
    final IconData icon;
    final Color accent;
    if (diff > eps) {
      icon = Icons.arrow_upward_rounded;
      accent = theme.brightness == Brightness.dark
          ? const Color(0xFF81C784)
          : const Color(0xFF2E7D32);
    } else if (diff < -eps) {
      icon = Icons.arrow_downward_rounded;
      accent = theme.colorScheme.error;
    } else {
      icon = Icons.horizontal_rule_rounded;
      accent = theme.colorScheme.onSurfaceVariant;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 6),
        DualCurrencyExactText(
          amount: previousTotal,
          textAlign: TextAlign.end,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DayTxnCounts {
  final int trials;
  final int conversions;
  final int renewals;
  final int purchases;
  final int refunds;
  final int cancelled;

  const _DayTxnCounts({
    required this.trials,
    required this.conversions,
    required this.renewals,
    required this.purchases,
    required this.refunds,
    required this.cancelled,
  });
}

_DayTxnCounts _aggregateDayCounts(List<RcTransaction> transactions) {
  var trials = 0;
  var conversions = 0;
  var renewals = 0;
  var purchases = 0;
  var refunds = 0;
  var cancelled = 0;
  for (final tx in transactions) {
    if (tx.type == RcTransactionType.refund) {
      refunds++;
    } else if (tx.isCancelledSummaryBadge) {
      cancelled++;
    }
    switch (tx.type) {
      case RcTransactionType.trial:
        trials++;
        break;
      case RcTransactionType.conversion:
        conversions++;
        break;
      case RcTransactionType.renewal:
        renewals++;
        break;
      case RcTransactionType.newSubscription:
      case RcTransactionType.oneTimePurchase:
        purchases++;
        break;
      case RcTransactionType.refund:
      case RcTransactionType.unknown:
        break;
    }
  }
  return _DayTxnCounts(
    trials: trials,
    conversions: conversions,
    renewals: renewals,
    purchases: purchases,
    refunds: refunds,
    cancelled: cancelled,
  );
}

RcTransactionType _sectionFilterAccentType(TransactionDaySectionFilter f) {
  switch (f) {
    case TransactionDaySectionFilter.trial:
      return RcTransactionType.trial;
    case TransactionDaySectionFilter.conversion:
      return RcTransactionType.conversion;
    case TransactionDaySectionFilter.renewal:
      return RcTransactionType.renewal;
    case TransactionDaySectionFilter.subscription:
      return RcTransactionType.newSubscription;
    case TransactionDaySectionFilter.refunded:
      return RcTransactionType.refund;
    case TransactionDaySectionFilter.cancelled:
      return RcTransactionType.renewal;
  }
}

Color _daySummaryPillAccent(
  BuildContext context,
  TransactionDaySectionFilter filter,
) {
  return switch (filter) {
    TransactionDaySectionFilter.refunded => transactionTypeAccentColor(
      RcTransactionType.refund,
      context,
    ),
    TransactionDaySectionFilter.cancelled => Colors.deepOrange,
    _ => transactionTypeAccentColor(_sectionFilterAccentType(filter), context),
  };
}

bool _sectionCountHigherIsBetter(TransactionDaySectionFilter filter) {
  return filter != TransactionDaySectionFilter.refunded &&
      filter != TransactionDaySectionFilter.cancelled;
}

class _DayTypeCountSummary extends StatelessWidget {
  final List<RcTransaction> transactions;
  final List<RcTransaction>? previousDayTransactions;
  final TransactionDaySectionFilter? selectedFilter;
  final void Function(TransactionDaySectionFilter filter) onSelectFilter;
  final VoidCallback? onClearFilter;
  final bool enableFilterTaps;

  /// When true, cells call [onSelectFilter] even if the count is zero (e.g. Revenue drill-down).
  final bool allowTapWhenEmpty;

  const _DayTypeCountSummary({
    required this.transactions,
    required this.previousDayTransactions,
    required this.selectedFilter,
    required this.onSelectFilter,
    required this.onClearFilter,
    this.enableFilterTaps = true,
    this.allowTapWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _aggregateDayCounts(transactions);
    final p = previousDayTransactions != null
        ? _aggregateDayCounts(previousDayTransactions!)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            _DaySummaryStatCell(
              label: 'Trials',
              count: n.trials,
              previousCount: p?.trials,
              filter: TransactionDaySectionFilter.trial,
              selected: selectedFilter == TransactionDaySectionFilter.trial,
              allowTap: enableFilterTaps,
              allowTapWhenEmpty: allowTapWhenEmpty,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Conversions',
              count: n.conversions,
              previousCount: p?.conversions,
              filter: TransactionDaySectionFilter.conversion,
              selected:
                  selectedFilter == TransactionDaySectionFilter.conversion,
              allowTap: enableFilterTaps,
              allowTapWhenEmpty: allowTapWhenEmpty,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Renewals',
              count: n.renewals,
              previousCount: p?.renewals,
              filter: TransactionDaySectionFilter.renewal,
              selected: selectedFilter == TransactionDaySectionFilter.renewal,
              allowTap: enableFilterTaps,
              allowTapWhenEmpty: allowTapWhenEmpty,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Purchases',
              count: n.purchases,
              previousCount: p?.purchases,
              filter: TransactionDaySectionFilter.subscription,
              selected:
                  selectedFilter == TransactionDaySectionFilter.subscription,
              allowTap: enableFilterTaps,
              allowTapWhenEmpty: allowTapWhenEmpty,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Refunds',
              count: n.refunds,
              previousCount: p?.refunds,
              filter: TransactionDaySectionFilter.refunded,
              selected: selectedFilter == TransactionDaySectionFilter.refunded,
              allowTap: enableFilterTaps,
              allowTapWhenEmpty: allowTapWhenEmpty,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Cancellations',
              count: n.cancelled,
              previousCount: p?.cancelled,
              filter: TransactionDaySectionFilter.cancelled,
              selected: selectedFilter == TransactionDaySectionFilter.cancelled,
              allowTap: enableFilterTaps,
              allowTapWhenEmpty: allowTapWhenEmpty,
              onTap: onSelectFilter,
            ),
          ],
        ),
        if (onClearFilter != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: onClearFilter,
              child: const Text('Clear filter'),
            ),
          ),
        ],
      ],
    );
  }
}

class _DaySummaryStatCell extends StatelessWidget {
  const _DaySummaryStatCell({
    required this.label,
    required this.count,
    required this.previousCount,
    required this.filter,
    required this.selected,
    required this.allowTap,
    required this.allowTapWhenEmpty,
    required this.onTap,
  });

  final String label;
  final int count;
  final int? previousCount;
  final TransactionDaySectionFilter filter;
  final bool selected;
  final bool allowTap;
  final bool allowTapWhenEmpty;
  final void Function(TransactionDaySectionFilter filter) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = _daySummaryPillAccent(context, filter);
    final enabled = count > 0;
    final baseCard = scheme.surfaceContainerHighest.withValues(alpha: 0.38);
    final fill = Color.alphaBlend(
      accent.withValues(alpha: selected ? 0.2 : 0.1),
      baseCard,
    );
    final borderColor = selected
        ? accent.withValues(alpha: 0.72)
        : Color.alphaBlend(
            accent.withValues(alpha: 0.28),
            scheme.outlineVariant.withValues(alpha: 0.45),
          );
    final prev = previousCount;
    final higherIsBetter = _sectionCountHigherIsBetter(filter);
    final tappable = allowTap && (enabled || allowTapWhenEmpty);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable ? () => onTap(filter) : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            color: fill,
          ),
          child: Opacity(
            opacity: (enabled || allowTapWhenEmpty) ? 1 : 0.38,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1,
                        color: selected ? accent : scheme.onSurface,
                      ),
                    ),
                    if (prev != null) ...[
                      const SizedBox(width: 6),
                      _DayCountTrendRow(
                        current: count,
                        previous: prev,
                        higherIsBetter: higherIsBetter,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCountTrendRow extends StatelessWidget {
  final int current;
  final int previous;
  final bool higherIsBetter;

  const _DayCountTrendRow({
    required this.current,
    required this.previous,
    required this.higherIsBetter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = current - previous;
    final IconData icon;
    final Color accent;
    if (delta == 0) {
      icon = Icons.horizontal_rule_rounded;
      accent = theme.colorScheme.onSurfaceVariant;
    } else {
      final up = delta > 0;
      icon = up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
      final improved = higherIsBetter ? up : !up;
      accent = improved
          ? (theme.brightness == Brightness.dark
                ? const Color(0xFF81C784)
                : const Color(0xFF2E7D32))
          : theme.colorScheme.error;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 4),
        Text(
          '$previous',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
