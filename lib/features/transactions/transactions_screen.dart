import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:revenuecat/core/utils/currency_format.dart';
import 'package:revenuecat/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/api_error_message.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/core/utils/subscriber_tenure_format.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/revenue/revenue_next_payday_proceeds.dart';
import 'package:revenuecat/features/revenue/widgets/revenue_insights_list.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/active_filters_row.dart';
import 'package:revenuecat/features/transactions/widgets/day_revenue_strip.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_list_sort_menu.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:revenuecat/services/auto_app_icons_store.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/display_currency_store.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/widget_data_channel.dart';
import 'package:revenuecat/services/transaction_list_sort_store.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';
import 'package:revenuecat/features/transactions/widgets/day_summary_card.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/animated_number.dart';
import 'package:revenuecat/widgets/animated_reveal.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/delta_badge.dart';
import 'package:revenuecat/widgets/grouped_list.dart';
import 'package:revenuecat/widgets/section_header.dart';
import 'package:revenuecat/widgets/shell_header.dart';
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

  /// True once [dayKey] can't gain transactions from older pages: an older
  /// day has been merged (pages go newest first), or there are no more pages.
  bool isDayFullyLoaded(String dayKey) {
    if (!hasMore) return true;
    String? oldest;
    for (final k in grouped.keys) {
      if (!isIsoCalendarDayKey(k)) continue;
      if (oldest == null || k.compareTo(oldest) < 0) oldest = k;
    }
    return oldest != null && dayKey.compareTo(oldest) > 0;
  }
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
  required Set<TransactionDaySectionFilter> sectionFilters,
}) {
  final out = <RcTransaction>[];
  final seen = <String>{};
  for (final tx in groupedForList.values.expand((e) => e)) {
    if (!_isPurchaseInstantInFuture(tx)) continue;
    if (!transactionMatchesAnySectionFilters(tx, sectionFilters)) {
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

  /// The running backfill and the generation it loads for.
  Future<void>? _backfillTask;
  int? _backfillTaskGen;

  /// Upper bound of pages fetched to reach a day picked by day navigation.
  static const int _maxPagesPerDayJump = 10;

  void setSelectedDayKey(String dayKey) {
    if (!isIsoCalendarDayKey(dayKey) || dayKey == state.selectedDayKey) return;
    state = state.copyWith(
      selectedDayKey: dayKey,
      error: null,
      isLoadingMore: false,
    );
    unawaited(_loadDay(dayKey));
  }

  /// Fetches older pages until [dayKey] is complete, so stepping back shows
  /// real totals instead of an empty day. Bounded per call (a full backfill
  /// per tap used to fire up to [kRealtimeBackfillMaxPages] requests) and
  /// abandoned when the user moves to another day or a refresh starts.
  Future<void> _loadDay(String dayKey) async {
    final gen = _backfillGeneration;
    for (var i = 0; i < _maxPagesPerDayJump; i++) {
      if (!mounted || gen != _backfillGeneration || state.isLoading) return;
      if (dayKey != state.selectedDayKey || state.isDayFullyLoaded(dayKey)) {
        return;
      }
      while (state.isLoadingMore && gen == _backfillGeneration && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      }
      if (!mounted ||
          gen != _backfillGeneration ||
          state.isLoading ||
          state.isDayFullyLoaded(dayKey)) {
        return;
      }
      final ok = await _performFetchMorePage(
        requestContext: 'transactions:day_jump',
      );
      // Another loader grabbed the page slot first; wait and try again.
      if (!ok && !(mounted && state.isLoadingMore)) return;
    }
  }

  /// Looks up App Store / Google Play icons for apps seen in [txs].
  void _ensureAppIcons(Iterable<RcTransaction> txs) {
    final apps = txs.map(AppIconIdentity.fromTransaction).nonNulls;
    unawaited(_ref.read(autoAppIconsProvider.notifier).ensure(apps));
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
      final response = await api.transactions(
        request,
        requestContext: 'transactions:initial',
      );
      if (!mounted || gen != _backfillGeneration) return;
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
      _syncWidgetData();
      _ensureAppIcons(raw);
      if (hasMorePages && !preloadBoundaryMet && gen == _backfillGeneration) {
        unawaited(backfillIncompleteCalendarDays(gen, true));
      }
      if (hasMorePages) unawaited(_loadDay(state.selectedDayKey));
    } on DioException catch (e) {
      if (!mounted || gen != _backfillGeneration) return;
      _handleAuthError(e);
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: _extractErrorMessage(e),
        realtimeLoadStep: 0,
        realtimeLoadComplete: false,
      );
    } catch (e) {
      if (!mounted || gen != _backfillGeneration) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: friendlyApiErrorMessage(e),
        realtimeLoadStep: 0,
        realtimeLoadComplete: false,
      );
    }
  }

  /// Fetches the next page (older transactions). Returns false if the request
  /// did not complete successfully (caller may stop retry loops).
  Future<bool> _performFetchMorePage({required String requestContext}) async {
    if (state.isLoadingMore || !state.hasMore) return false;
    if (state.lastPurchaseMs == null) {
      state = state.copyWith(hasMore: false);
      return false;
    }

    state = state.copyWith(isLoadingMore: true);
    final prevCursor = state.lastPurchaseMs!;
    // A refresh started while this page was in flight; its cursor is stale.
    final gen = _backfillGeneration;
    bool stale() => !mounted || gen != _backfillGeneration;
    try {
      final api = _ref.read(rcApiServiceProvider);
      final request = RcTransactionsRequest(
        limit: _kediPaginationLimit,
        startFrom: prevCursor,
      );
      final response = await api.transactions(
        request,
        requestContext: requestContext,
      );
      if (stale()) return false;
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
      _ensureAppIcons(raw);
      return true;
    } on DioException catch (e) {
      if (stale()) return false;
      _handleAuthError(e);
      state = state.copyWith(isLoadingMore: false);
      return false;
    } catch (_) {
      if (stale()) return false;
      state = state.copyWith(isLoadingMore: false);
      return false;
    }
  }

  Future<void> fetchMore() async {
    await _performFetchMorePage(requestContext: 'transactions:scroll');
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
    // A run for an older generation (a refresh landed mid-backfill) is still
    // unwinding: wait for it rather than skipping, or this generation would
    // never load the month or mark the Revenue tab complete.
    while (_backfillTask != null) {
      if (_backfillTaskGen == gen) return;
      try {
        await _backfillTask;
      } catch (_) {}
      if (!mounted || gen != _backfillGeneration) return;
    }
    final task = _runBackfill(gen, onlyThroughCurrentMonth);
    _backfillTask = task;
    _backfillTaskGen = gen;
    try {
      await task;
    } finally {
      if (identical(_backfillTask, task)) {
        _backfillTask = null;
        _backfillTaskGen = null;
      }
    }
  }

  Future<void> _runBackfill(int gen, bool onlyThroughCurrentMonth) async {
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
        final backfillKind = onlyThroughCurrentMonth
            ? 'transactions:backfill_revenue_window'
            : 'transactions:backfill_after_day_change';
        final ok = await _performFetchMorePage(
          requestContext: '$backfillKind page=${pages + 1}',
        );
        if (!ok) {
          // A scroll or day load took the page slot; wait for it and go on.
          if (mounted && state.isLoadingMore && gen == _backfillGeneration) {
            continue;
          }
          break;
        }
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
      if (mounted && gen == _backfillGeneration) {
        state = state.copyWith(
          realtimeLoadComplete: true,
          realtimeLoadStep: kRealtimeLoadTarget,
        );
        _syncWidgetData();
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
    return friendlyApiErrorMessage(e, serverMessage: rcError?.message);
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

  /// Push current state to native home screen widgets.
  void _syncWidgetData() {
    final commission = _ref.read(commissionSettingsProvider);
    final currency = _ref.read(displayCurrencyProvider);
    final ratesAsync = _ref.read(usdExchangeRatesProvider);
    final rates = ratesAsync is AsyncData<Map<String, double>>
        ? ratesAsync.value
        : <String, double>{};
    unawaited(
      WidgetDataChannel.pushWidgetData(state, commission, currency, rates),
    );
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

/// Shared country filter: `null` or empty = all regions. Otherwise subscriber
/// country must be in the set, or match `'__'` for unknown / missing country.
final transactionsCountryFilterProvider = StateProvider<Set<String>?>(
  (ref) => null,
);

/// Shared store platform filter (`null` or empty = all).
final transactionsPlatformFilterProvider =
    StateProvider<Set<TransactionPlatformFilter>?>((ref) => null);

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  Set<TransactionDaySectionFilter> _sectionFilters = {};

  /// Expandable "Scheduled" section (today only); collapsed by default.
  bool _futureTransactionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsProvider);
    final appIncludeFilter = ref.watch(transactionsAppIncludeFilterProvider);
    final countryFilter = ref.watch(transactionsCountryFilterProvider);
    final platformFilter = ref.watch(transactionsPlatformFilterProvider);
    final accountProjects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final selectedKey = state.selectedDayKey;
    final dayTxs = state.grouped[selectedKey] ?? [];
    final dayFilterSource = <String, List<RcTransaction>>{
      if (dayTxs.isNotEmpty) selectedKey: dayTxs,
    };
    final canOpenTransactionFilter =
        !state.isLoading &&
        collectAppFilterOptionsWithProjects(
          dayFilterSource,
          accountProjects,
        ).isNotEmpty;
    final filtersActive =
        appIncludeFilter != null ||
        (countryFilter != null && countryFilter.isNotEmpty) ||
        (platformFilter != null && platformFilter.isNotEmpty) ||
        _sectionFilters.isNotEmpty;

    final todayKey = localTodayDayKey();
    final prevKey = _previousCalendarDayKey(selectedKey);
    final nextKey = _nextCalendarDayKey(selectedKey);
    final canGoNext = selectedKey.compareTo(todayKey) < 0 && nextKey != null;

    return Scaffold(
      appBar: ShellHeader(
        title: _dayTitle(selectedKey),
        subtitle: _daySubtitle(selectedKey),
        actions: [
          HeaderIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous day',
            onPressed: state.isLoading || prevKey == null
                ? null
                : () => _goToDay(prevKey),
          ),
          HeaderIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next day',
            onPressed: state.isLoading || !canGoNext
                ? null
                : () => _goToDay(nextKey),
          ),
          const SizedBox(width: 6),
          HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter transactions',
            badge: filtersActive,
            onPressed: !canOpenTransactionFilter
                ? null
                : () => _showAppFilterSheet(context, state),
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
      body: _buildDayTab(context, state),
    );
  }

  void _clearTransactionFilters() {
    ref.read(transactionsAppIncludeFilterProvider.notifier).state = null;
    ref.read(transactionsCountryFilterProvider.notifier).state = null;
    ref.read(transactionsPlatformFilterProvider.notifier).state = null;
    setState(() => _sectionFilters = {});
  }

  void _toggleSectionFilter(TransactionDaySectionFilter filter) {
    setState(() {
      final next = Set<TransactionDaySectionFilter>.from(_sectionFilters);
      if (!next.remove(filter)) next.add(filter);
      _sectionFilters = next;
    });
  }

  Widget _buildDayTab(BuildContext context, TransactionsState state) {
    final listSort = ref.watch(transactionListSortProvider);
    final commission = ref.watch(commissionSettingsProvider);
    final appIncludeFilter = ref.watch(transactionsAppIncludeFilterProvider);
    final countryFilter = ref.watch(transactionsCountryFilterProvider);
    final platformFilter = ref.watch(transactionsPlatformFilterProvider);
    final countryFilterActive =
        countryFilter != null && countryFilter.isNotEmpty;
    final platformFilterActive =
        platformFilter != null && platformFilter.isNotEmpty;
    if (state.isLoading && state.grouped.isEmpty) {
      return const TransactionsLoadingSkeleton();
    }

    if (state.error != null && state.grouped.isEmpty && !state.isLoading) {
      return AppStateMessage.error(
        title: 'Couldn’t load transactions',
        message: state.error!,
        onRetry: () => ref.read(transactionsProvider.notifier).fetchInitial(),
      );
    }

    final selectedKey = state.selectedDayKey;
    final groupedForList = filteredGroupedByTransactionMeta(
      filteredGroupedByApps(state.grouped, appIncludeFilter),
      countryCodes: countryFilter,
      platforms: platformFilter,
    );
    final todayKey = localTodayDayKey();
    final viewingToday = selectedKey == todayKey;

    // Scheduled (future-dated) rows on today haven't happened yet: they have
    // their own section and stay out of the day's totals, tiles and bars.
    List<RcTransaction> happened(String dayKey) {
      final txs = groupedForList[dayKey] ?? const <RcTransaction>[];
      if (dayKey != todayKey) return txs;
      return txs.where((tx) => !_isPurchaseInstantInFuture(tx)).toList();
    }

    final allForDay = happened(selectedKey);

    final listFiltersActive =
        appIncludeFilter != null || countryFilterActive || platformFilterActive;

    List<RcTransaction> sectionFiltered(List<RcTransaction> txs) => txs
        .where((tx) => transactionMatchesAnySectionFilters(tx, _sectionFilters))
        .toList();

    final allForDayForMetrics = sectionFiltered(allForDay);

    final transactions = List.of(allForDayForMetrics);
    sortMutableTransactionList(transactions, listSort);

    final prevKey = _previousCalendarDayKey(selectedKey);
    final headerDaily = netRevenueSum(allForDayForMetrics, commission);
    final previousDayForSummary = prevKey != null
        ? (groupedForList[prevKey] ?? <RcTransaction>[])
        : null;
    final previousDayLoaded =
        prevKey != null && state.isDayFullyLoaded(prevKey);
    final headerPrevTotal = previousDayForSummary != null && previousDayLoaded
        ? netRevenueSum(sectionFiltered(previousDayForSummary), commission)
        : null;

    final allTxForTenure = state.grouped.values.expand((e) => e);
    final subscriberEarliestPurchaseDay =
        earliestPurchaseLocalDayBySubscriberId(allTxForTenure);
    final subscriberEarliestPurchaseInstant =
        earliestPurchaseLocalInstantBySubscriberId(allTxForTenure);

    final futureTxs = viewingToday
        ? _collectFutureTransactions(
            groupedForList: groupedForList,
            sectionFilters: _sectionFilters,
          )
        : <RcTransaction>[];

    final filtersHideResults =
        transactions.isEmpty &&
        (listFiltersActive || _sectionFilters.isNotEmpty);
    final dayLoaded = state.isDayFullyLoaded(selectedKey);

    final stripDays = _stripDays(
      selectedKey: selectedKey,
      state: state,
      totalFor: (key) =>
          netRevenueSum(sectionFiltered(happened(key)), commission),
    );

    final bottomPadding = mainShellFloatingTabBarScrollPadding(context);

    void openTransaction(RcTransaction tx, {Object? heroTag}) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) =>
              TransactionDetailScreen(transaction: tx, heroTag: heroTag),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent - 240) {
          if (state.hasMore && !state.isLoadingMore && !state.isLoading) {
            ref.read(transactionsProvider.notifier).fetchMore();
          }
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => ref.read(transactionsProvider.notifier).fetchInitial(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: AnimatedReveal(
                visible: listFiltersActive || _sectionFilters.isNotEmpty,
                child: ActiveFiltersRow(
                  appCount: appIncludeFilter?.length,
                  countryCodes: countryFilter,
                  platforms: platformFilter,
                  sectionFilters: _sectionFilters,
                  onOpenFilters: () => _showAppFilterSheet(context, state),
                  onClearApps: () =>
                      ref
                              .read(
                                transactionsAppIncludeFilterProvider.notifier,
                              )
                              .state =
                          null,
                  onClearCountries: () =>
                      ref
                              .read(transactionsCountryFilterProvider.notifier)
                              .state =
                          null,
                  onClearPlatforms: () =>
                      ref
                              .read(transactionsPlatformFilterProvider.notifier)
                              .state =
                          null,
                  onRemoveSection: _toggleSectionFilter,
                  onClearAll: _clearTransactionFilters,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _DayHeroCard(
                  label: commission.adjustmentEnabled
                      ? 'Net revenue'
                      : 'Revenue',
                  total: headerDaily,
                  previousTotal: headerPrevTotal,
                  loading: !dayLoaded,
                  strip: DayRevenueStrip(
                    days: stripDays,
                    selectedDayKey: selectedKey,
                    formatAmount: _formatAmountForSemantics,
                    onDaySelected: state.isLoading ? null : _goToDay,
                  ),
                ).appCardEntrance(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                // Bones, not zeros, while the day is still loading.
                child: Skeletonizer(
                  enabled: !dayLoaded,
                  child: DayTypeCountSummary(
                    transactions: allForDay,
                    previousDayTransactions: previousDayLoaded
                        ? previousDayForSummary
                        : null,
                    selectedFilters: _sectionFilters,
                    onFilterCellTap: _toggleSectionFilter,
                  ),
                ).appCardEntrance(delay: const Duration(milliseconds: 60)),
              ),
            ),
            if (dayLoaded &&
                !filtersHideResults &&
                allForDayForMetrics.isNotEmpty)
              SliverToBoxAdapter(
                child: RealtimeRevenueInsightsList(
                  transactions: allForDayForMetrics,
                  asModalEntry: true,
                  cardMargin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                ).appCardEntrance(delay: const Duration(milliseconds: 100)),
              ),
            if (futureTxs.isNotEmpty)
              SliverToBoxAdapter(
                child: _FutureTransactionsSection(
                  transactions: futureTxs,
                  expanded: _futureTransactionsExpanded,
                  onExpandedChanged: (v) {
                    setState(() => _futureTransactionsExpanded = v);
                  },
                  subscriberEarliestPurchaseLocalDayById:
                      subscriberEarliestPurchaseDay,
                  subscriberEarliestPurchaseLocalInstantById:
                      subscriberEarliestPurchaseInstant,
                  onOpenTransaction: openTransaction,
                ).appCardEntrance(delay: const Duration(milliseconds: 120)),
              ),
            if (filtersHideResults)
              SliverToBoxAdapter(
                child: AppStateMessage(
                  icon: Icons.filter_list_off_outlined,
                  title: 'No transactions match your filters',
                  message: 'Try another day, or clear the filters.',
                  actionLabel: 'Clear filters',
                  actionIcon: Icons.filter_alt_off_outlined,
                  onAction: _clearTransactionFilters,
                  bottomPadding: bottomPadding,
                  shrinkWrap: true,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Transactions',
                  count: transactions.isEmpty ? null : '${transactions.length}',
                  trailing: transactions.length > 1
                      ? const TransactionListSortMenuButton(showLabel: true)
                      : null,
                ),
              ),
              if (transactions.isEmpty &&
                  state.grouped.isNotEmpty &&
                  (dayLoaded || !state.isLoadingMore))
                SliverToBoxAdapter(
                  child: AppCard(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      dayLoaded
                          ? (viewingToday
                                ? 'No transactions yet today.'
                                : 'No transactions on this day.')
                          : 'This day didn\u2019t finish loading. Pull down '
                                'to try again.',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else if (transactions.isNotEmpty)
                GroupedSliverList(
                  itemCount: transactions.length,
                  dividerIndent: kTransactionRowDividerIndent,
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final key = rcTransactionDedupKey(tx);
                    final heroTag = key == null ? null : 'tx-$key';
                    return TransactionItem(
                      heroTag: heroTag,
                      key: ValueKey(rcTransactionDedupKey(tx) ?? '$index'),
                      transaction: tx,
                      subscriberEarliestPurchaseLocalDayById:
                          subscriberEarliestPurchaseDay,
                      subscriberEarliestPurchaseLocalInstantById:
                          subscriberEarliestPurchaseInstant,
                      onTap: () => openTransaction(tx, heroTag: heroTag),
                    ).appListItemEntrance(index);
                  },
                ),
            ],
            if (state.hasMore && state.isLoadingMore)
              const SliverToBoxAdapter(child: TransactionRowsSkeleton(rows: 3)),
            if (!filtersHideResults)
              SliverPadding(padding: EdgeInsets.only(bottom: bottomPadding)),
          ],
        ),
      ),
    );
  }

  List<DayRevenueStripDay> _stripDays({
    required String selectedKey,
    required TransactionsState state,
    required double Function(String dayKey) totalFor,
  }) {
    final DateTime selected;
    try {
      selected = DateFormat('yyyy-MM-dd').parse(selectedKey);
    } catch (_) {
      return const [];
    }
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final date = DateTime(
            selected.year,
            selected.month,
            selected.day - i,
          );
          final key = DateFormat('yyyy-MM-dd').format(date);
          return DayRevenueStripDay(
            dayKey: key,
            date: date,
            total: state.isDayFullyLoaded(key) ? totalFor(key) : null,
          );
        }(),
    ];
  }

  String _formatAmountForSemantics(double usd) {
    final currency = ref.read(displayCurrencyProvider);
    if (currency == 'USD') return formatExactUsd(usd);
    final rates = ref.read(usdExchangeRatesProvider).asData?.value;
    final r = rates?[currency.toLowerCase()];
    if (r == null || r == 0) return formatExactUsd(usd);
    return formatExactForeign(usd * r, currency);
  }

  void _goToDay(String dayKey) {
    setState(() {
      _futureTransactionsExpanded = false;
    });
    ref.read(transactionsProvider.notifier).setSelectedDayKey(dayKey);
  }

  String _dayTitle(String dayKey) {
    if (dayKey == localTodayDayKey()) return 'Today';
    if (dayKey == _previousCalendarDayKey(localTodayDayKey())) {
      return 'Yesterday';
    }
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dayKey);
      final sameYear = date.year == DateTime.now().year;
      return DateFormat(sameYear ? 'EEE, MMM d' : 'MMM d, y').format(date);
    } catch (_) {
      return dayKey;
    }
  }

  String _daySubtitle(String dayKey) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dayKey);
      return DateFormat('EEEE, MMMM d, y').format(date);
    } catch (_) {
      return dayKey;
    }
  }

  Future<void> _showAppFilterSheet(
    BuildContext context,
    TransactionsState state,
  ) async {
    final dayTxs = state.grouped[state.selectedDayKey] ?? [];
    final filterSource = <String, List<RcTransaction>>{
      if (dayTxs.isNotEmpty) state.selectedDayKey: dayTxs,
    };
    final projects = await ref.read(rcAccountProjectsProvider.future);
    if (!context.mounted) return;
    final current = ref.read(transactionsAppIncludeFilterProvider);
    final country = ref.read(transactionsCountryFilterProvider);
    final platform = ref.read(transactionsPlatformFilterProvider);
    showTransactionsAppFilterSheet(
      context: context,
      filterSource: filterSource,
      currentIncludeFilter: current,
      currentCountryCodes: country,
      currentPlatforms: platform,
      accountProjects: projects,
      onApply: (apps, countryCodes, platformFilters) {
        ref.read(transactionsAppIncludeFilterProvider.notifier).state = apps;
        ref.read(transactionsCountryFilterProvider.notifier).state =
            countryCodes;
        ref.read(transactionsPlatformFilterProvider.notifier).state =
            platformFilters;
        setState(() => _sectionFilters = {});
      },
    );
  }
}

String? _previousCalendarDayKey(String dayKey) {
  if (!isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateFormat('yyyy-MM-dd').parse(dayKey);
    return DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(d.year, d.month, d.day - 1));
  } catch (_) {
    return null;
  }
}

String? _nextCalendarDayKey(String dayKey) {
  if (!isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateFormat('yyyy-MM-dd').parse(dayKey);
    return DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(d.year, d.month, d.day + 1));
  } catch (_) {
    return null;
  }
}

/// Day total, change vs the previous day, and the 7-day strip.
class _DayHeroCard extends StatelessWidget {
  const _DayHeroCard({
    required this.label,
    required this.total,
    required this.previousTotal,
    required this.strip,
    this.loading = false,
  });

  final String label;
  final double total;

  /// The day's older pages are still loading; its total isn't known yet.
  final bool loading;

  /// Null when the previous day isn't loaded yet.
  final double? previousTotal;
  final Widget strip;

  /// Cross-fades when the change moves to a new value or direction.
  Widget _changeBadge(BuildContext context, double prev) {
    final badge = DeltaBadge.percent(current: total, previous: prev);
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.fast),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('${badge.direction}_${badge.label}'),
        child: badge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: AppText.tabular,
    );
    final prev = previousTotal;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (loading)
            Text(
              '\u2014',
              style: AppText.amount(
                context,
                size: 34,
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            AnimatedExactAmount(
              amount: total,
              countFromZero: true,
              style: AppText.amount(context, size: 34),
            ),
          const SizedBox(height: 8),
          if (loading)
            Text('Loading this day\u2026', style: muted)
          else if (prev == null)
            Text('Previous day not loaded yet', style: muted)
          else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (prev.abs() > 1e-6) _changeBadge(context, prev),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('vs yesterday  ', style: muted),
                    AnimatedExactAmount(amount: prev, style: muted),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 16),
          strip,
        ],
      ),
    );
  }
}

class _FutureTransactionsSection extends StatelessWidget {
  final List<RcTransaction> transactions;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final Map<String, DateTime> subscriberEarliestPurchaseLocalDayById;
  final Map<String, DateTime> subscriberEarliestPurchaseLocalInstantById;
  final void Function(RcTransaction tx, {Object? heroTag}) onOpenTransaction;

  static Object? _heroTag(RcTransaction tx) {
    final key = rcTransactionDedupKey(tx);
    return key == null ? null : 'tx-scheduled-$key';
  }

  const _FutureTransactionsSection({
    required this.transactions,
    required this.expanded,
    required this.onExpandedChanged,
    required this.subscriberEarliestPurchaseLocalDayById,
    required this.subscriberEarliestPurchaseLocalInstantById,
    required this.onOpenTransaction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Scheduled',
                        children: [
                          TextSpan(
                            text: '  ${transactions.length} later today',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant,
                      semanticLabel: expanded ? 'Collapse' : 'Expand',
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedReveal(
            visible: expanded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tx in transactions) ...[
                  const Divider(indent: kTransactionRowDividerIndent),
                  TransactionItem(
                    transaction: tx,
                    heroTag: _heroTag(tx),
                    subscriberEarliestPurchaseLocalDayById:
                        subscriberEarliestPurchaseLocalDayById,
                    subscriberEarliestPurchaseLocalInstantById:
                        subscriberEarliestPurchaseLocalInstantById,
                    onTap: () => onOpenTransaction(tx, heroTag: _heroTag(tx)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
