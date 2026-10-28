import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/widgets/app_state_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/core/shell_insets.dart';
import 'package:openrc/core/utils/subscriber_tenure_format.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/features/ask/ask_context.dart';
import 'package:openrc/features/ask/widgets/ask_context_chip.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/revenue/revenue_next_payday_proceeds.dart';
import 'package:openrc/features/revenue/widgets/revenue_insights_list.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/widgets/active_filters_row.dart';
import 'package:openrc/features/transactions/widgets/day_revenue_strip.dart';
import 'package:openrc/features/transactions/widgets/jump_to_day_sheet.dart';
import 'package:openrc/features/transactions/widgets/transaction_list_sort_menu.dart';
import 'package:openrc/features/transactions/widgets/transactions_filter_bar.dart';
import 'package:openrc/features/transactions/widgets/transactions_table.dart';
import 'package:openrc/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:openrc/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:openrc/services/auto_app_icons_store.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/widget_data_channel.dart';
import 'package:openrc/services/transaction_list_sort_store.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_derived.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/features/transactions/widgets/day_summary_card.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/animated_number.dart';
import 'package:openrc/widgets/animated_reveal.dart';
import 'package:openrc/widgets/app_card.dart';
import 'package:openrc/widgets/delta_badge.dart';
import 'package:openrc/widgets/grouped_list.dart';
import 'package:openrc/widgets/section_header.dart';
import 'package:openrc/widgets/shell_header.dart';
import 'package:openrc/widgets/side_panel.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:easy_localization/easy_localization.dart';

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

  /// Days loaded by [dayRuns], kept apart from [grouped] so month totals
  /// and the backfill only ever see one unbroken run back from today.
  final Map<String, List<RcTransaction>> jumpedDays;

  /// Page runs started at a day picked far back in the calendar.
  final List<TransactionsDayRun> dayRuns;

  /// A [dayRuns] page is in flight.
  final bool isLoadingDay;

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
    this.jumpedDays = const {},
    this.dayRuns = const [],
    this.isLoadingDay = false,
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
    Map<String, List<RcTransaction>>? jumpedDays,
    List<TransactionsDayRun>? dayRuns,
    bool? isLoadingDay,
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
    jumpedDays: jumpedDays ?? this.jumpedDays,
    dayRuns: dayRuns ?? this.dayRuns,
    isLoadingDay: isLoadingDay ?? this.isLoadingDay,
  );

  /// Oldest day the pages back from today have reached (maybe partial).
  String? get oldestLoadedDayKey {
    String? oldest;
    for (final k in grouped.keys) {
      if (!isIsoCalendarDayKey(k)) continue;
      if (oldest == null || k.compareTo(oldest) < 0) oldest = k;
    }
    return oldest;
  }

  /// True once [dayKey] can't gain transactions from older pages: an older
  /// day has been merged (pages go newest first), or there are no more pages.
  bool isDayFullyLoaded(String dayKey) {
    if (!hasMore) return true;
    final oldest = oldestLoadedDayKey;
    if (oldest != null && dayKey.compareTo(oldest) > 0) return true;
    return dayRuns.any((run) => run.covers(dayKey));
  }

  /// Every loaded day for the day view: [grouped] plus [jumpedDays].
  Map<String, List<RcTransaction>> get dayView {
    if (jumpedDays.isEmpty) return grouped;
    final out = Map<String, List<RcTransaction>>.from(grouped);
    for (final e in jumpedDays.entries) {
      final days = out[e.key];
      if (days == null) {
        out[e.key] = e.value;
      } else {
        out[e.key] = List.of(days);
        _mergeTransactionsDeduping(out[e.key]!, e.value);
      }
    }
    return out;
  }
}

/// Pages fetched back from the end of [topDayKey], for a day picked far
/// beyond what the pages from today have reached.
@immutable
class TransactionsDayRun {
  const TransactionsDayRun({
    required this.topDayKey,
    required this.cursor,
    this.oldestDayKey,
  });

  /// Opens a run at the last millisecond of [dayKey] (local time).
  factory TransactionsDayRun.endOf(String dayKey) {
    final d = DateTime.parse(dayKey);
    final end = DateTime(d.year, d.month, d.day + 1);
    return TransactionsDayRun(
      topDayKey: dayKey,
      cursor: end.millisecondsSinceEpoch - 1,
    );
  }

  final String topDayKey;

  /// `start_from` for the next page; null once the oldest page is in.
  final int? cursor;

  /// Oldest day merged so far, maybe partial (pages go newest first).
  final String? oldestDayKey;

  bool get hasMore => cursor != null;

  /// [dayKey] is complete in this run: at or below its top, and above its
  /// partial oldest day (or the run reached the first transaction).
  bool covers(String dayKey) {
    if (dayKey.compareTo(topDayKey) > 0) return false;
    if (!hasMore) return true;
    final oldest = oldestDayKey;
    return oldest != null && dayKey.compareTo(oldest) > 0;
  }

  /// The next page of this run brings [dayKey] closer: it's the partial
  /// oldest day or the one before it.
  bool reaches(String dayKey) {
    if (!hasMore || dayKey.compareTo(topDayKey) > 0) return false;
    final oldest = oldestDayKey;
    if (oldest == null) return true;
    final before = _previousCalendarDayKey(oldest);
    return before == null || dayKey.compareTo(before) >= 0;
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
  return isoLocalDayKey(end);
}

int? _purchaseDateMs(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final d = DateTime.tryParse(s.trim());
  return d?.millisecondsSinceEpoch;
}

bool _isPurchaseInstantInFuture(RcTransaction tx) {
  final instant = tx.purchaseLocalInstant;
  return instant != null && instant.isAfter(DateTime.now());
}

/// Scheduled rows that haven't happened yet, newest first, from the days that
/// can hold them.
///
/// Purchase dates bucket rows into `yyyy-MM-dd` keys, so a future-dated row
/// always sits in today's bucket or a later one: scanning the whole loaded
/// feed (a hundred pages of history) for it on every rebuild is avoidable.
List<RcTransaction> _collectFutureTransactions({
  required Map<String, List<RcTransaction>> groupedForList,
  required Set<TransactionDaySectionFilter> sectionFilters,
}) {
  final todayKey = localTodayDayKey();
  final out = <RcTransaction>[];
  final seen = <String>{};
  for (final entry in groupedForList.entries) {
    if (entry.key.compareTo(todayKey) < 0) continue;
    for (final tx in entry.value) {
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
      return isoLocalDayKey(dt.toLocal());
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
    state = state.copyWith(selectedDayKey: dayKey, error: null);
    unawaited(_loadDay(dayKey));
  }

  /// Loads [dayKey] if it isn't complete. Days at the edge of what's loaded
  /// page back as usual; a day further back (picked in the calendar) gets
  /// its own run of pages from its end, a request or two instead of every
  /// page in between.
  Future<void> _loadDay(String dayKey) async {
    if (state.isDayFullyLoaded(dayKey)) return;
    final oldest = state.oldestLoadedDayKey;
    final edge = oldest == null ? null : _previousCalendarDayKey(oldest);
    if (edge == null || dayKey.compareTo(edge) >= 0) {
      await _loadDayFromToday(dayKey);
    } else {
      await _loadDayRun(dayKey);
    }
  }

  /// Fetches older pages until [dayKey] is complete, so stepping back shows
  /// real totals instead of an empty day. Bounded per call (a full backfill
  /// per tap used to fire up to [kRealtimeBackfillMaxPages] requests) and
  /// abandoned when the user moves to another day or a refresh starts.
  Future<void> _loadDayFromToday(String dayKey) async {
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

  /// Run pages in flight, so [TransactionsState.isLoadingDay] stays on
  /// until the last one lands.
  int _runPagesInFlight = 0;

  /// Pages back from the end of [dayKey] (or from a run already heading
  /// there) until it's complete, within the same bound as a day step.
  Future<void> _loadDayRun(String dayKey) async {
    final gen = _backfillGeneration;
    var run =
        state.dayRuns.where((r) => r.reaches(dayKey)).firstOrNull ??
        TransactionsDayRun.endOf(dayKey);
    for (var i = 0; i < _maxPagesPerDayJump; i++) {
      if (!mounted || gen != _backfillGeneration || state.isLoading) return;
      if (dayKey != state.selectedDayKey || state.isDayFullyLoaded(dayKey)) {
        return;
      }
      final next = await _fetchRunPage(run, gen);
      if (next == null) return;
      run = next;
    }
  }

  /// Fetches the next page of [run] into [TransactionsState.jumpedDays].
  /// Returns the run after the page, or null if the page failed or a
  /// refresh made it stale.
  Future<TransactionsDayRun?> _fetchRunPage(
    TransactionsDayRun run,
    int gen,
  ) async {
    final cursor = run.cursor;
    if (cursor == null) return null;
    bool stale() => !mounted || gen != _backfillGeneration;
    _runPagesInFlight++;
    state = state.copyWith(isLoadingDay: true);
    try {
      final api = _ref.read(rcApiServiceProvider);
      final response = await api.transactions(
        RcTransactionsRequest(limit: _kediPaginationLimit, startFrom: cursor),
        requestContext: 'transactions:day_run',
      );
      if (stale()) return null;
      final raw = response.transactions ?? [];
      final jumped = {
        for (final e in state.jumpedDays.entries) e.key: List.of(e.value),
      };
      _mergeRawIntoGrouped(jumped, raw);
      var oldest = run.oldestDayKey;
      for (final k in _groupByDateStatic(raw).keys) {
        if (!isIsoCalendarDayKey(k)) continue;
        if (oldest == null || k.compareTo(oldest) < 0) oldest = k;
      }
      final next = TransactionsDayRun(
        topDayKey: run.topDayKey,
        cursor: raw.isEmpty
            ? null
            : _nextCursorFromResponse(raw, response.lastPurchaseMs),
        oldestDayKey: oldest,
      );
      state = state.copyWith(
        jumpedDays: jumped,
        dayRuns: [
          for (final r in state.dayRuns)
            if (r.topDayKey != run.topDayKey) r,
          next,
        ],
      );
      _ensureAppIcons(raw);
      return next;
    } on DioException catch (e) {
      if (stale()) return null;
      _handleAuthError(e);
      return null;
    } catch (_) {
      return null;
    } finally {
      // A refresh already reset the count for pages it made stale.
      if (!stale()) {
        _runPagesInFlight--;
        state = state.copyWith(isLoadingDay: _runPagesInFlight > 0);
      }
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
      isLoadingDay: false,
      error: null,
      realtimeLoadStep: 0,
      realtimeLoadComplete: false,
    );
    _backfillGeneration++;
    _runPagesInFlight = 0;
    final gen = _backfillGeneration;
    final started = DateTime.now();
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
        jumpedDays: const {},
        dayRuns: const [],
        isLoading: false,
        isLoadingMore: false,
        hasMore: hasMorePages,
        firstPurchaseMs: response.firstPurchaseMs,
        lastPurchaseMs: hasMorePages ? nextCursor : null,
        realtimeLoadStep: realtimeDone ? kRealtimeLoadTarget : 1,
        realtimeLoadComplete: realtimeDone,
      );
      Telemetry.dataLoaded(
        result: 'ok',
        source: 'initial',
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
      _syncWidgetData();
      _ensureAppIcons(raw);
      if (hasMorePages && !preloadBoundaryMet && gen == _backfillGeneration) {
        unawaited(backfillIncompleteCalendarDays(gen, true));
      }
      if (hasMorePages) unawaited(_loadDay(state.selectedDayKey));
    } on DioException catch (e) {
      if (!mounted || gen != _backfillGeneration) return;
      Telemetry.dataLoaded(
        result: 'error',
        source: 'initial',
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
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
  ///
  /// [advanceRealtimeStep] adds the page to the Revenue tab's preload progress
  /// in the same state change as the rows, so a background page costs one
  /// rebuild of the dashboard instead of two.
  Future<bool> _performFetchMorePage({
    required String requestContext,
    bool advanceRealtimeStep = false,
  }) async {
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

      final nextCursor = raw.isNotEmpty
          ? _nextCursorFromResponse(raw, response.lastPurchaseMs)
          : null;
      final hasMorePages = raw.isNotEmpty && nextCursor != null;

      state = state.copyWith(
        grouped: existingGrouped,
        dailyTotals: _dailyTotalsWithPage(
          totals: state.dailyTotals,
          grouped: existingGrouped,
          page: raw,
        ),
        isLoadingMore: false,
        hasMore: hasMorePages,
        firstPurchaseMs: state.firstPurchaseMs ?? response.firstPurchaseMs,
        lastPurchaseMs: hasMorePages ? nextCursor : null,
        realtimeLoadStep: advanceRealtimeStep
            ? state.realtimeLoadStep + 1
            : null,
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

  /// The day's list neared its end: keeps loading the selected day if it
  /// isn't complete. Older pages never show in a day's list, so once it is
  /// there's nothing to page in.
  Future<void> fetchMore() async {
    if (state.isLoading || state.isLoadingMore || state.isLoadingDay) return;
    await _loadDay(state.selectedDayKey);
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
          advanceRealtimeStep: true,
        );
        if (!ok) {
          // A scroll or day load took the page slot; wait for it and go on.
          if (mounted && state.isLoadingMore && gen == _backfillGeneration) {
            continue;
          }
          break;
        }
        pages++;
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
      _ref
          .read(rcAuthServiceProvider)
          .signOut(reason: SignOutReason.sessionExpired);
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

  /// [totals] with the days [page] touched re-summed from [grouped].
  ///
  /// A page only ever adds rows to a handful of days, while the feed can hold
  /// a hundred pages of history: re-summing the whole feed for every page is
  /// quadratic in the number of pages loaded.
  Map<String, double> _dailyTotalsWithPage({
    required Map<String, double> totals,
    required Map<String, List<RcTransaction>> grouped,
    required List<RcTransaction> page,
  }) {
    if (page.isEmpty) return totals;
    final commission = _ref.read(commissionSettingsProvider);
    final next = Map<String, double>.from(totals);
    for (final dayKey in _groupByDateStatic(page).keys) {
      final rows = grouped[dayKey];
      next[dayKey] = rows == null ? 0 : netRevenueSum(rows, commission);
    }
    return next;
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

/// A single column of cards, gutters included, never grows past this.
const double _columnMaxWidth =
    AppBreakpoints.readableWidth + 2 * AppSpace.gutter;

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
    final dayTxs = state.dayView[selectedKey] ?? [];
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
        onTitleTap: () => _pickDay(selectedKey),
        titleTapTooltip: 'transactions.jumpToDay'.tr(),
        actions: [
          HeaderIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'transactions.previousDay'.tr(),
            onPressed: state.isLoading || prevKey == null
                ? null
                : () => _goToDay(prevKey),
          ),
          HeaderIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'transactions.nextDay'.tr(),
            onPressed: state.isLoading || !canGoNext
                ? null
                : () => _goToDay(nextKey),
          ),
          const SizedBox(width: 6),
          HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'transactions.filterTransactions'.tr(),
            badge: filtersActive,
            onPressed: !canOpenTransactionFilter
                ? null
                : () => _showAppFilterSheet(context, state),
          ),
          if (ShellHeader.showsRefreshButton)
            HeaderIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'transactions.refresh'.tr(),
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
        title: 'transactions.loadError'.tr(),
        message: state.error!,
        onRetry: () => ref.read(transactionsProvider.notifier).fetchInitial(),
      );
    }

    final selectedKey = state.selectedDayKey;
    final days = state.dayView;
    final groupedForList = filteredGroupedByTransactionMeta(
      filteredGroupedByApps(days, appIncludeFilter),
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

    final allTxForTenure = days.values.expand((e) => e);
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
      openDetail(
        context,
        (context) => TransactionDetailScreen(transaction: tx, heroTag: heroTag),
      );
    }

    // The day at a glance: totals, counts, insights, scheduled rows.
    final summarySlivers = <Widget>[
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
                ref.read(transactionsAppIncludeFilterProvider.notifier).state =
                    null,
            onClearCountries: () =>
                ref.read(transactionsCountryFilterProvider.notifier).state =
                    null,
            onClearPlatforms: () =>
                ref.read(transactionsPlatformFilterProvider.notifier).state =
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
                ? 'transactions.netRevenue'.tr()
                : 'transactions.revenue'.tr(),
            total: headerDaily,
            previousTotal: headerPrevTotal,
            loading: !dayLoaded,
            strip: DayRevenueStrip(
              days: stripDays,
              selectedDayKey: selectedKey,
              formatAmount: _formatAmountForSemantics,
              onDaySelected: state.isLoading ? null : _goToDay,
            ),
            onAsk: () =>
                openAskTab(ref, context: AskPrefills.selectedDay(selectedKey)),
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
      if (dayLoaded && !filtersHideResults && allForDayForMetrics.isNotEmpty)
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
    ];

    // Every sale of the day.
    final listSlivers = <Widget>[
      if (filtersHideResults)
        SliverToBoxAdapter(
          child: AppStateMessage(
            icon: Icons.filter_list_off_outlined,
            title: 'transactions.noFilterMatches'.tr(),
            message: 'transactions.noFilterMatchesMessage'.tr(),
            actionLabel: 'transactions.clearFilters'.tr(),
            actionIcon: Icons.filter_alt_off_outlined,
            onAction: _clearTransactionFilters,
            bottomPadding: bottomPadding,
            shrinkWrap: true,
          ),
        )
      else ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'transactions.title'.tr(),
            count: transactions.isEmpty ? null : '${transactions.length}',
            trailing: transactions.length > 1
                ? const TransactionListSortMenuButton(showLabel: true)
                : null,
          ),
        ),
        if (transactions.isEmpty &&
            state.grouped.isNotEmpty &&
            (dayLoaded || !(state.isLoadingMore || state.isLoadingDay)))
          SliverToBoxAdapter(
            child: AppCard(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                dayLoaded
                    ? (viewingToday
                          ? 'transactions.noTransactionsToday'.tr()
                          : 'transactions.noTransactionsOnDay'.tr())
                    : 'transactions.dayNotFinished'.tr(),
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
      // Only while this day's rows are on the way: the Revenue tab's month
      // backfill pages other days and can run for a hundred pages.
      if (!dayLoaded && (state.isLoadingMore || state.isLoadingDay))
        const SliverToBoxAdapter(child: TransactionRowsSkeleton(rows: 3)),
    ];

    Future<void> refresh() =>
        ref.read(transactionsProvider.notifier).fetchInitial();

    Widget scrollView(List<Widget> slivers, {double inset = 0}) =>
        CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
            SliverPadding(padding: EdgeInsets.only(bottom: bottomPadding)),
          ],
        );

    // Keeps loading an unfinished day as its list nears the end.
    Widget pagesMore(Widget child) => NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (!dayLoaded &&
            scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 240) {
          ref.read(transactionsProvider.notifier).fetchMore();
        }
        return false;
      },
      child: child,
    );

    // Wide windows: filters, the day's cards, then the day's table, in one
    // column.
    List<Widget> dashboardSlivers(double tableWidth) {
      final hero = _DayHeroCard(
        label: commission.adjustmentEnabled
            ? 'transactions.netRevenue'.tr()
            : 'transactions.revenue'.tr(),
        total: headerDaily,
        previousTotal: headerPrevTotal,
        loading: !dayLoaded,
        strip: DayRevenueStrip(
          days: stripDays,
          selectedDayKey: selectedKey,
          formatAmount: _formatAmountForSemantics,
          onDaySelected: state.isLoading ? null : _goToDay,
        ),
        onAsk: () =>
            openAskTab(ref, context: AskPrefills.selectedDay(selectedKey)),
      );
      final showBreakdown =
          dayLoaded && !filtersHideResults && allForDayForMetrics.isNotEmpty;
      return [
        SliverToBoxAdapter(
          child: TransactionsFilterBar(
            transactions: days[selectedKey] ?? const [],
            onOpenAllFilters: () => _showAppFilterSheet(context, state),
            sectionFilters: _sectionFilters,
            onRemoveSection: _toggleSectionFilter,
            onClearSections: () => setState(() => _sectionFilters = {}),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          sliver: SliverToBoxAdapter(
            child: showBreakdown
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: hero),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          flex: 4,
                          child: RealtimeRevenueInsightsList(
                            transactions: allForDayForMetrics,
                            asModalEntry: true,
                            cardMargin: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ).appCardEntrance()
                : hero.appCardEntrance(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          sliver: SliverToBoxAdapter(
            child: Skeletonizer(
              enabled: !dayLoaded,
              child: DayTypeCountSummary(
                transactions: allForDay,
                previousDayTransactions: previousDayLoaded
                    ? previousDayForSummary
                    : null,
                selectedFilters: _sectionFilters,
                onFilterCellTap: _toggleSectionFilter,
                singleRow: true,
              ),
            ).appCardEntrance(delay: const Duration(milliseconds: 60)),
          ),
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
              margin: const EdgeInsets.only(top: AppSpace.sm),
            ).appCardEntrance(delay: const Duration(milliseconds: 100)),
          ),
        if (filtersHideResults)
          SliverToBoxAdapter(
            child: AppStateMessage(
              icon: Icons.filter_list_off_outlined,
              title: 'transactions.noFilterMatches'.tr(),
              message: 'transactions.noFilterMatchesMessage'.tr(),
              actionLabel: 'transactions.clearFilters'.tr(),
              actionIcon: Icons.filter_alt_off_outlined,
              onAction: _clearTransactionFilters,
              bottomPadding: bottomPadding,
              shrinkWrap: true,
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'transactions.title'.tr(),
              count: transactions.isEmpty ? null : '${transactions.length}',
              padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
            ),
          ),
          if (transactions.isEmpty &&
              state.grouped.isNotEmpty &&
              (dayLoaded || !(state.isLoadingMore || state.isLoadingDay)))
            SliverToBoxAdapter(
              child: AppCard(
                child: Text(
                  dayLoaded
                      ? (viewingToday
                            ? 'transactions.noTransactionsToday'.tr()
                            : 'transactions.noTransactionsOnDay'.tr())
                      : 'transactions.dayNotFinished'.tr(),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else if (transactions.isNotEmpty)
            TransactionsTable(
              transactions: transactions,
              width: tableWidth,
              onOpen: openTransaction,
            ),
        ],
        if (!dayLoaded && (state.isLoadingMore || state.isLoadingDay))
          const SliverToBoxAdapter(child: TransactionRowsSkeleton(rows: 3)),
      ];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= AppBreakpoints.dashboard) {
          final gutter =
              AppBreakpoints.dashboardGutter +
              AppBreakpoints.centeringInset(
                width,
                maxWidth: AppBreakpoints.dashboardMaxWidth,
              );
          return pagesMore(
            RefreshIndicator(
              onRefresh: refresh,
              child: scrollView(
                dashboardSlivers(width - 2 * gutter),
                inset: gutter,
              ),
            ),
          );
        }
        return pagesMore(
          RefreshIndicator(
            onRefresh: refresh,
            child: scrollView(
              [...summarySlivers, ...listSlivers],
              inset: AppBreakpoints.centeringInset(
                width,
                maxWidth: _columnMaxWidth,
              ),
            ),
          ),
        );
      },
    );
  }

  List<DayRevenueStripDay> _stripDays({
    required String selectedKey,
    required TransactionsState state,
    required double Function(String dayKey) totalFor,
  }) {
    final DateTime selected;
    try {
      selected = DateTime.parse(selectedKey);
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
          final key = isoLocalDayKey(date);
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

  /// Opens the calendar and goes to the picked day.
  Future<void> _pickDay(String selectedKey) async {
    final picked = await showJumpToDaySheet(
      context,
      selectedDay: DateTime.parse(selectedKey),
    );
    if (picked == null || !mounted) return;
    _goToDay(isoLocalDayKey(picked));
  }

  void _goToDay(String dayKey) {
    setState(() {
      _futureTransactionsExpanded = false;
    });
    ref.read(transactionsProvider.notifier).setSelectedDayKey(dayKey);
  }

  String _dayTitle(String dayKey) {
    if (dayKey == localTodayDayKey()) return 'transactions.today'.tr();
    if (dayKey == _previousCalendarDayKey(localTodayDayKey())) {
      return 'transactions.yesterday'.tr();
    }
    try {
      final date = DateTime.parse(dayKey);
      final sameYear = date.year == DateTime.now().year;
      return (sameYear ? DateFormat.MMMEd() : DateFormat.yMMMd()).format(date);
    } catch (_) {
      return dayKey;
    }
  }

  String _daySubtitle(String dayKey) {
    try {
      final date = DateTime.parse(dayKey);
      return DateFormat.yMMMMEEEEd().format(date);
    } catch (_) {
      return dayKey;
    }
  }

  Future<void> _showAppFilterSheet(
    BuildContext context,
    TransactionsState state,
  ) async {
    final dayTxs = state.dayView[state.selectedDayKey] ?? [];
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

/// Moves the Transactions day back ([delta] < 0) or forward, never past
/// today. For keyboard shortcuts; the header buttons follow the same rules.
void stepTransactionsDay(WidgetRef ref, int delta) {
  final state = ref.read(transactionsProvider);
  if (state.isLoading) return;
  final key = state.selectedDayKey;
  if (delta > 0 && key.compareTo(localTodayDayKey()) >= 0) return;
  final target = delta < 0
      ? _previousCalendarDayKey(key)
      : _nextCalendarDayKey(key);
  if (target != null) {
    ref.read(transactionsProvider.notifier).setSelectedDayKey(target);
  }
}

String? _previousCalendarDayKey(String dayKey) {
  if (!isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateTime.parse(dayKey);
    return isoLocalDayKey(DateTime(d.year, d.month, d.day - 1));
  } catch (_) {
    return null;
  }
}

String? _nextCalendarDayKey(String dayKey) {
  if (!isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateTime.parse(dayKey);
    return isoLocalDayKey(DateTime(d.year, d.month, d.day + 1));
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
    required this.onAsk,
    this.loading = false,
  });

  final String label;
  final double total;

  /// The day's older pages are still loading; its total isn't known yet.
  final bool loading;

  /// Null when the previous day isn't loaded yet.
  final double? previousTotal;
  final Widget strip;
  final VoidCallback onAsk;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AskContextChip(label: 'agent.askAboutDay'.tr(), onPressed: onAsk),
            ],
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
            Text('transactions.loadingThisDay'.tr(), style: muted)
          else if (prev == null)
            Text('transactions.previousDayNotLoaded'.tr(), style: muted)
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
                    Text('${'transactions.vsYesterday'.tr()}  ', style: muted),
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
  final EdgeInsetsGeometry margin;

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
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Card(
      margin: margin,
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
                        text: 'transactions.scheduled'.tr(),
                        children: [
                          TextSpan(
                            text:
                                '  ${'transactions.laterToday'.tr(namedArgs: {'count': '${transactions.length}'})}',
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
                      semanticLabel: expanded
                          ? 'transactions.collapse'.tr()
                          : 'transactions.expand'.tr(),
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
