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
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/core/utils/subscriber_tenure_format.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_revenue_insights_card.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';
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
  }) =>
      TransactionsState(
        selectedDayKey: selectedDayKey ?? this.selectedDayKey,
        grouped: grouped ?? this.grouped,
        dailyTotals: dailyTotals ?? this.dailyTotals,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        firstPurchaseMs: firstPurchaseMs ?? this.firstPurchaseMs,
        lastPurchaseMs: lastPurchaseMs ?? this.lastPurchaseMs,
        error: error,
      );
}

/// Net revenue for a day: sum of [RcTransaction.revenue] (null → 0), including
/// refunds (typically negative), with optional store commission when enabled.
double _netRevenueSum(
  Iterable<RcTransaction> transactions,
  CommissionSettings commission,
) {
  return transactions.fold(0.0, (sum, tx) {
    final gross = tx.revenue ?? 0;
    return sum +
        adjustUsdForDisplay(
          gross: gross,
          settings: commission,
          store: tx.store,
        );
  });
}

String? _transactionDedupKey(RcTransaction tx) {
  final stid = tx.storeTransactionIdentifier?.trim();
  if (stid != null && stid.isNotEmpty) return 'stid:$stid';
  final sub = tx.subscriberId?.trim();
  final prod = tx.productIdentifier?.trim();
  final pd = tx.purchaseDate?.trim();
  if (sub != null &&
      sub.isNotEmpty &&
      prod != null &&
      prod.isNotEmpty &&
      pd != null &&
      pd.isNotEmpty) {
    return 'cmp:$sub|$prod|$pd';
  }
  return null;
}

final RegExp _isoCalendarDayKeyRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool _isIsoCalendarDayKey(String key) => _isoCalendarDayKeyRe.hasMatch(key);

/// Matches [Kedi](https://github.com/sereisoglu/Kedi): small first page + `end_date`,
/// then pagination with `start_from` only (no date range on follow-up requests).
/// Stop when a page returns no transactions.
const int _kediFirstPageLimit = 20;
const int _kediPaginationLimit = 100;

/// Upper bound for the first-page `/me/transactions` query (`end_date`) and for
/// the latest calendar day the user can open — matches
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

String _localTodayDayKey() {
  final n = DateTime.now();
  return DateFormat('yyyy-MM-dd').format(DateTime(n.year, n.month, n.day));
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
    final k = _transactionDedupKey(tx);
    if (k != null) seen.add(k);
  }
  for (final tx in incoming) {
    final k = _transactionDedupKey(tx);
    if (k != null && seen.contains(k)) continue;
    if (k != null) seen.add(k);
    into.add(tx);
  }
}

class TransactionsNotifier extends StateNotifier<TransactionsState> {
  final Ref _ref;

  TransactionsNotifier(this._ref)
      : super(TransactionsState(selectedDayKey: _localTodayDayKey()));

  int _backfillGeneration = 0;
  bool _backfillRunning = false;

  void setSelectedDayKey(String dayKey) {
    if (!_isIsoCalendarDayKey(dayKey) || dayKey == state.selectedDayKey) return;
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
    state = state.copyWith(isLoading: true, isLoadingMore: false, error: null);
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
      state = state.copyWith(
        grouped: grouped,
        dailyTotals: dailyTotals,
        isLoading: false,
        isLoadingMore: false,
        hasMore: hasMorePages,
        firstPurchaseMs: response.firstPurchaseMs,
        lastPurchaseMs: hasMorePages ? nextCursor : null,
      );
      if (gen == _backfillGeneration) {
        unawaited(backfillIncompleteCalendarDays(gen));
      }
    } on DioException catch (e) {
      _handleAuthError(e);
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: _extractErrorMessage(e),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: 'Failed to load transactions',
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
      final existingGrouped = Map<String, List<RcTransaction>>.from(state.grouped);
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

  /// Keeps calling [_performFetchMorePage] while any visible calendar day may
  /// still have undelivered rows (newest-first pagination).
  Future<void> backfillIncompleteCalendarDays([int? capturedGen]) async {
    final gen = capturedGen ?? _backfillGeneration;
    if (_backfillRunning) return;
    _backfillRunning = true;
    try {
      var pages = 0;
      const maxPages = 800;
      while (pages < maxPages &&
          gen == _backfillGeneration &&
          !state.isLoading &&
          state.hasMore) {
        while (state.isLoadingMore && gen == _backfillGeneration) {
          await Future<void>.delayed(const Duration(milliseconds: 24));
        }
        if (gen != _backfillGeneration || state.isLoading || !state.hasMore) {
          break;
        }
        final ok = await _performFetchMorePage();
        if (!ok) break;
        pages++;
      }
    } finally {
      _backfillRunning = false;
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
      totals[entry.key] = _netRevenueSum(entry.value, commission);
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

String _appKeyForTransaction(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return '';
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return '';
}

String _appLabelForTransaction(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return 'Unknown app';
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  return 'Unknown app';
}

class _AppFilterOption {
  final String key;
  final String label;

  /// RevenueCat app id ([RcTransactionApp.id]) for icon override lookup; may be null.
  final String? appId;

  const _AppFilterOption(this.key, this.label, this.appId);
}

List<_AppFilterOption> _collectAppFilterOptions(
  Map<String, List<RcTransaction>> grouped,
) {
  final labelByKey = <String, String>{};
  final appIdByKey = <String, String>{};
  for (final list in grouped.values) {
    for (final tx in list) {
      final k = _appKeyForTransaction(tx);
      labelByKey.putIfAbsent(k, () => _appLabelForTransaction(tx));
      final aid = tx.app?.id?.trim();
      if (aid != null && aid.isNotEmpty) {
        appIdByKey.putIfAbsent(k, () => aid);
      }
    }
  }
  final out = labelByKey.entries
      .map(
        (e) => _AppFilterOption(
          e.key,
          e.value,
          appIdByKey[e.key],
        ),
      )
      .toList();
  out.sort(
    (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
  );
  return out;
}

Map<String, List<RcTransaction>> _filteredGroupedByApps(
  Map<String, List<RcTransaction>> grouped,
  Set<String>? appFilter,
) {
  if (appFilter == null) return grouped;
  final out = <String, List<RcTransaction>>{};
  for (final e in grouped.entries) {
    final filtered = e.value
        .where((tx) => appFilter.contains(_appKeyForTransaction(tx)))
        .toList();
    if (filtered.isNotEmpty) {
      out[e.key] = filtered;
    }
  }
  return out;
}

Map<String, double> _dailyTotalsForGrouped(
  Map<String, List<RcTransaction>> grouped,
  CommissionSettings commission,
) {
  final totals = <String, double>{};
  for (final entry in grouped.entries) {
    totals[entry.key] = _netRevenueSum(entry.value, commission);
  }
  return totals;
}

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

  /// When non-null, only transactions for these app keys are listed.
  /// When null, all apps are shown.
  Set<String>? _appIncludeFilter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transactionsProvider.notifier).fetchInitial();
    });
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
    final nearEnd = maxExt <= 0
        ? true
        : pos.pixels >= maxExt - _loadMoreLeadPx;
    if (nearEnd) {
      ref.read(transactionsProvider.notifier).fetchMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsProvider);
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
              color: _appIncludeFilter != null
                  ? context.colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter by app',
            onPressed: state.isLoading ||
                    (state.grouped[state.selectedDayKey] ?? []).isEmpty
                ? null
                : () => _showAppFilterSheet(context, state),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const SettingsScreen(),
                ),
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
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, TransactionsState state) {
    final commission = ref.watch(commissionSettingsProvider);
    if (state.isLoading && state.grouped.isEmpty) {
      return _buildTransactionsScreenSkeleton(context);
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
    final groupedForList =
        _filteredGroupedByApps(state.grouped, _appIncludeFilter);
    final allForDay = groupedForList[selectedKey] ?? [];

    if (_appIncludeFilter != null &&
        rawDayTxs.isNotEmpty &&
        allForDay.isEmpty) {
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
                  setState(() {
                    _appIncludeFilter = null;
                    _sectionFilter = null;
                  });
                },
                child: const Text('Show all apps'),
              ),
            ],
          ),
        ),
      );
    }

    final sectionFiltered = _sectionFilter != null;
    final transactions = sectionFiltered
        ? allForDay
            .where(
              (tx) => _transactionMatchesSectionFilter(tx, _sectionFilter!),
            )
            .toList()
        : allForDay;

    final theme = Theme.of(context);
    final prevKey = _previousCalendarDayKey(selectedKey);
    final latestNavigableKey = _kediEndDateString();
    final canGoNext = selectedKey.compareTo(latestNavigableKey) < 0;
    final groupedForHeader =
        _filteredGroupedByApps(state.grouped, _appIncludeFilter);
    final headerDailyTotals =
        _dailyTotalsForGrouped(groupedForHeader, commission);
    final headerDaily = headerDailyTotals[selectedKey] ?? 0;
    final headerPrevTotal =
        prevKey != null ? headerDailyTotals[prevKey] : null;
    final previousDayForSummary =
        prevKey != null ? (groupedForList[prevKey] ?? <RcTransaction>[]) : null;

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
                        DualCurrencyExactText(
                          amount: headerDaily,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
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
      TransactionsRevenueInsightsCard(transactions: allForDay),
    ];

    final subscriberEarliestPurchaseDay =
        earliestPurchaseLocalDayBySubscriberId(
      state.grouped.values.expand((e) => e),
    );

    for (final tx in transactions) {
      children.add(
        TransactionItem(
          transaction: tx,
          subscriberEarliestPurchaseLocalDayById: subscriberEarliestPurchaseDay,
          inSectionCard: false,
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (context) => TransactionDetailScreen(
                  transaction: tx,
                ),
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
      final runway = math.max(
        280.0,
        MediaQuery.sizeOf(context).height * 0.35,
      );
      children.add(SizedBox(height: runway));
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(transactionsProvider.notifier).fetchInitial(),
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
    setState(() => _sectionFilter = null);
    ref.read(transactionsProvider.notifier).setSelectedDayKey(dayKey);
  }

  /// Full-screen placeholder while the selected day (and window) loads.
  Widget _buildTransactionsScreenSkeleton(BuildContext context) {
    final bottom = mainShellFloatingTabBarScrollPadding(context);
    return Skeletonizer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottom),
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Bone(
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              Bone.text(fontSize: 28, width: 160),
                              const SizedBox(height: 8),
                              Bone.text(fontSize: 14, width: 140),
                            ],
                          ),
                        ),
                      ),
                      Bone(
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: List.generate(
                      6,
                      (_) => Bone(
                        width: 118,
                        height: 30,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone.text(fontSize: 12, width: 120),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      5,
                      (_) => Bone(
                        width: 88,
                        height: 30,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      4,
                      (_) => Bone(
                        width: 72,
                        height: 30,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Bone(
                        width: 96,
                        height: 36,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(width: 10),
                      Bone(
                        width: 110,
                        height: 36,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ...List.generate(
            7,
            (_) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                        Bone.text(fontSize: 12, width: 180),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    final dayMap = <String, List<RcTransaction>>{
      if (dayTxs.isNotEmpty) state.selectedDayKey: dayTxs,
    };
    final options = _collectAppFilterOptions(dayMap);
    if (options.isEmpty) return;

    final allKeys = options.map((o) => o.key).toSet();
    final initialSelected = _appIncludeFilter == null
        ? Set<String>.from(allKeys)
        : () {
            final i = _appIncludeFilter!.intersection(allKeys);
            return i.isEmpty ? Set<String>.from(allKeys) : i;
          }();

    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: SizedBox(
              height: maxHeight,
              child: _AppFilterModal(
                options: options,
                allKeys: allKeys,
                initialSelected: initialSelected,
                onApply: (selected) {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _sectionFilter = null;
                    if (selected.length == allKeys.length) {
                      _appIncludeFilter = null;
                    } else {
                      _appIncludeFilter = selected;
                    }
                  });
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

String? _previousCalendarDayKey(String dayKey) {
  if (!_isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateFormat('yyyy-MM-dd').parse(dayKey);
    return DateFormat('yyyy-MM-dd').format(
      d.subtract(const Duration(days: 1)),
    );
  } catch (_) {
    return null;
  }
}

String? _nextCalendarDayKey(String dayKey) {
  if (!_isIsoCalendarDayKey(dayKey)) return null;
  try {
    final d = DateFormat('yyyy-MM-dd').parse(dayKey);
    return DateFormat('yyyy-MM-dd').format(
      d.add(const Duration(days: 1)),
    );
  } catch (_) {
    return null;
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
        Text(
          'Prev',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.25,
          ),
        ),
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

class _AppFilterModal extends StatefulWidget {
  final List<_AppFilterOption> options;
  final Set<String> allKeys;
  final Set<String> initialSelected;
  final void Function(Set<String> selected) onApply;

  const _AppFilterModal({
    required this.options,
    required this.allKeys,
    required this.initialSelected,
    required this.onApply,
  });

  @override
  State<_AppFilterModal> createState() => _AppFilterModalState();
}

class _AppFilterModalState extends State<_AppFilterModal> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              Text(
                'Apps',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() => _selected = Set<String>.from(widget.allKeys));
                },
                child: const Text('ALL'),
              ),
              TextButton(
                onPressed: () => setState(() => _selected = {}),
                child: const Text('NONE'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.options.length,
            itemBuilder: (context, index) {
              final opt = widget.options[index];
              return CheckboxListTile(
                value: _selected.contains(opt.key),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selected.add(opt.key);
                    } else {
                      _selected.remove(opt.key);
                    }
                  });
                },
                title: Row(
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final scheme = Theme.of(context).colorScheme;
                        final url = opt.appId != null
                            ? ref.watch(appIconOverridesProvider)[opt.appId]
                            : null;
                        return TransactionLeadingAvatar(
                          imageUrl: url,
                          size: 40,
                          borderRadius: 10,
                          tintColor: scheme.primary,
                          fallback: Icon(
                            Icons.apps_outlined,
                            color: scheme.primary,
                            size: 22,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        opt.label,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => widget.onApply(Set<String>.from(_selected)),
                child: const Text('Apply'),
              ),
            ],
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

/// Day header pills for filtering the transaction list.
enum TransactionDaySectionFilter {
  trial,
  conversion,
  renewal,
  subscription,
  refunded,
  cancelled,
}

bool _transactionMatchesSectionFilter(
  RcTransaction tx,
  TransactionDaySectionFilter filter,
) {
  final t = tx.type;
  switch (filter) {
    case TransactionDaySectionFilter.trial:
      return t == RcTransactionType.trial;
    case TransactionDaySectionFilter.conversion:
      return t == RcTransactionType.conversion;
    case TransactionDaySectionFilter.renewal:
      return t == RcTransactionType.renewal;
    case TransactionDaySectionFilter.subscription:
      return t == RcTransactionType.newSubscription ||
          t == RcTransactionType.oneTimePurchase;
    case TransactionDaySectionFilter.refunded:
      return t == RcTransactionType.refund;
    case TransactionDaySectionFilter.cancelled:
      return tx.isCancelledSummaryBadge;
  }
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
    TransactionDaySectionFilter.refunded =>
        transactionTypeAccentColor(RcTransactionType.refund, context),
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

  const _DayTypeCountSummary({
    required this.transactions,
    required this.previousDayTransactions,
    required this.selectedFilter,
    required this.onSelectFilter,
    required this.onClearFilter,
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
          childAspectRatio: 1.22,
          children: [
            _DaySummaryStatCell(
              label: 'Trials',
              count: n.trials,
              previousCount: p?.trials,
              filter: TransactionDaySectionFilter.trial,
              selected: selectedFilter == TransactionDaySectionFilter.trial,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Conversions',
              count: n.conversions,
              previousCount: p?.conversions,
              filter: TransactionDaySectionFilter.conversion,
              selected: selectedFilter == TransactionDaySectionFilter.conversion,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Renewals',
              count: n.renewals,
              previousCount: p?.renewals,
              filter: TransactionDaySectionFilter.renewal,
              selected: selectedFilter == TransactionDaySectionFilter.renewal,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Purchases',
              count: n.purchases,
              previousCount: p?.purchases,
              filter: TransactionDaySectionFilter.subscription,
              selected:
                  selectedFilter == TransactionDaySectionFilter.subscription,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Refunds',
              count: n.refunds,
              previousCount: p?.refunds,
              filter: TransactionDaySectionFilter.refunded,
              selected: selectedFilter == TransactionDaySectionFilter.refunded,
              onTap: onSelectFilter,
            ),
            _DaySummaryStatCell(
              label: 'Cancellations',
              count: n.cancelled,
              previousCount: p?.cancelled,
              filter: TransactionDaySectionFilter.cancelled,
              selected: selectedFilter == TransactionDaySectionFilter.cancelled,
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
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final TransactionDaySectionFilter filter;
  final bool selected;
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onTap(filter) : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1,
            ),
            color: fill,
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.38,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
