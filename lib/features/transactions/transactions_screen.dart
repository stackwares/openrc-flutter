import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/features/transactions/transaction_detail_screen.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

class TransactionsState {
  final Map<String, List<RcTransaction>> grouped;
  final Map<String, double> dailyTotals;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int? firstPurchaseMs;
  final int? lastPurchaseMs;
  final String? error;

  const TransactionsState({
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
/// refunds (typically negative), so the header matches list math.
double _netRevenueSum(Iterable<RcTransaction> transactions) {
  return transactions.fold(0.0, (sum, tx) => sum + (tx.revenue ?? 0));
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

/// API returns transactions newest-first. A calendar [dayKey] has all of its
/// rows loaded once we hold at least one transaction from an **older** local
/// calendar day, or [hasMore] is false.
bool _isCalendarDayFullyLoaded(
  String dayKey,
  Map<String, List<RcTransaction>> grouped,
  bool hasMore,
) {
  if (!hasMore) return true;
  if (!_isIsoCalendarDayKey(dayKey)) return true;
  for (final k in grouped.keys) {
    if (!_isIsoCalendarDayKey(k)) continue;
    if (k.compareTo(dayKey) < 0) return true;
  }
  return false;
}

bool _groupedHasAnyIncompleteCalendarDay(
  Map<String, List<RcTransaction>> grouped,
  bool hasMore,
) {
  if (!hasMore) return false;
  for (final k in grouped.keys) {
    if (!_isIsoCalendarDayKey(k)) continue;
    if (!_isCalendarDayFullyLoaded(k, grouped, hasMore)) return true;
  }
  return false;
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

  TransactionsNotifier(this._ref) : super(const TransactionsState());

  int _backfillGeneration = 0;
  bool _backfillRunning = false;

  Future<void> fetchInitial() async {
    state = state.copyWith(isLoading: true, error: null);
    _backfillGeneration++;
    final gen = _backfillGeneration;
    try {
      final api = _ref.read(rcApiServiceProvider);
      final endDate = DateFormat('yyyy-MM-dd').format(
        DateTime.now().add(const Duration(days: 7)),
      );
      final request = RcTransactionsRequest(
        limit: 20,
        endDate: endDate,
      );
      final response = await api.transactions(request);
      final transactions = response.transactions ?? [];
      final grouped = _groupByDate(transactions);
      final dailyTotals = _calculateDailyTotals(grouped);
      state = state.copyWith(
        grouped: grouped,
        dailyTotals: dailyTotals,
        isLoading: false,
        hasMore: transactions.length >= 20,
        firstPurchaseMs: response.firstPurchaseMs,
        lastPurchaseMs: response.lastPurchaseMs,
      );
      if (gen == _backfillGeneration) {
        unawaited(backfillIncompleteCalendarDays(gen));
      }
    } on DioException catch (e) {
      _handleAuthError(e);
      state = state.copyWith(
        isLoading: false,
        error: _extractErrorMessage(e),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load transactions');
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
    try {
      final api = _ref.read(rcApiServiceProvider);
      final request = RcTransactionsRequest(
        limit: 100,
        startFrom: state.lastPurchaseMs,
      );
      final response = await api.transactions(request);
      final newTransactions = response.transactions ?? [];
      final existingGrouped = Map<String, List<RcTransaction>>.from(state.grouped);
      final newGrouped = _groupByDate(newTransactions);

      for (final entry in newGrouped.entries) {
        existingGrouped.putIfAbsent(entry.key, () => []);
        _mergeTransactionsDeduping(existingGrouped[entry.key]!, entry.value);
      }

      final dailyTotals = _calculateDailyTotals(existingGrouped);
      state = state.copyWith(
        grouped: existingGrouped,
        dailyTotals: dailyTotals,
        isLoadingMore: false,
        hasMore: newTransactions.length >= 100,
        firstPurchaseMs: state.firstPurchaseMs ?? response.firstPurchaseMs,
        lastPurchaseMs: response.lastPurchaseMs,
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
      const maxPages = 400;
      while (pages < maxPages &&
          gen == _backfillGeneration &&
          !state.isLoading &&
          state.hasMore &&
          _groupedHasAnyIncompleteCalendarDay(state.grouped, state.hasMore)) {
        while (state.isLoadingMore && gen == _backfillGeneration) {
          await Future<void>.delayed(const Duration(milliseconds: 24));
        }
        if (gen != _backfillGeneration || state.isLoading || !state.hasMore) {
          break;
        }
        if (!_groupedHasAnyIncompleteCalendarDay(state.grouped, state.hasMore)) {
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

  Map<String, List<RcTransaction>> _groupByDate(
    List<RcTransaction> transactions,
  ) {
    final map = <String, List<RcTransaction>>{};
    for (final tx in transactions) {
      final date = tx.purchaseDate ?? 'Unknown';
      final dayKey = _extractDayKey(date);
      map.putIfAbsent(dayKey, () => []).add(tx);
    }
    return map;
  }

  String _extractDayKey(String dateStr) {
    try {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        final local = dt.toLocal();
        return DateFormat('yyyy-MM-dd').format(local);
      }
    } catch (_) {}
    return dateStr;
  }

  Map<String, double> _calculateDailyTotals(
    Map<String, List<RcTransaction>> grouped,
  ) {
    final totals = <String, double>{};
    for (final entry in grouped.entries) {
      totals[entry.key] = _netRevenueSum(entry.value);
    }
    return totals;
  }
}

final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, TransactionsState>((ref) {
  return TransactionsNotifier(ref);
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
) {
  final totals = <String, double>{};
  for (final entry in grouped.entries) {
    totals[entry.key] = _netRevenueSum(entry.value);
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

  /// When set, only [dayKey]'s list shows transactions matching [filter].
  String? _sectionFilterDayKey;
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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(transactionsProvider.notifier).fetchMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _appIncludeFilter != null
                  ? context.colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter by app',
            onPressed: state.isLoading || state.grouped.isEmpty
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
      body: _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, TransactionsState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.grouped.isEmpty) {
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

    if (state.grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No transactions yet',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final groupedForList =
        _filteredGroupedByApps(state.grouped, _appIncludeFilter);
    final dailyTotalsForList = _dailyTotalsForGrouped(groupedForList);

    if (groupedForList.isEmpty) {
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
                    _sectionFilterDayKey = null;
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

    if (_sectionFilterDayKey != null &&
        !groupedForList.containsKey(_sectionFilterDayKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _sectionFilterDayKey = null;
          _sectionFilter = null;
        });
      });
    }

    final sortedKeys = groupedForList.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(transactionsProvider.notifier).fetchInitial(),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          0,
          4,
          0,
          4 + mainShellFloatingTabBarScrollPadding(context),
        ),
        itemCount: sortedKeys.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= sortedKeys.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final dayKey = sortedKeys[index];
          final allForDay = groupedForList[dayKey]!;
          final sectionFiltered = _sectionFilterDayKey == dayKey &&
              _sectionFilter != null;
          final transactions = sectionFiltered
              ? allForDay
                  .where(
                    (tx) => _transactionMatchesSectionFilter(
                      tx,
                      _sectionFilter!,
                    ),
                  )
                  .toList()
              : allForDay;
          final dailyTotal = dailyTotalsForList[dayKey] ?? 0;
          final dateLabel = _dayHeaderDateLabel(dayKey);
          final theme = Theme.of(context);
          final dividerColor =
              theme.colorScheme.outlineVariant.withValues(alpha: 0.42);

          return Card(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: allForDay.isNotEmpty
                              ? DualCurrencyExactText(
                                  amount: dailyTotal,
                                  textAlign: TextAlign.start,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                    letterSpacing: -0.65,
                                    height: 1.1,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      _DayHeaderDateBlock(
                        dayKey: dayKey,
                        dateLabel: dateLabel,
                        currentTotal: dailyTotal,
                        dailyTotals: dailyTotalsForList,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: dividerColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: _DayTypeCountSummary(
                    transactions: allForDay,
                    selectedFilter: sectionFiltered ? _sectionFilter : null,
                    onSelectFilter: (filter) {
                      setState(() {
                        if (_sectionFilterDayKey == dayKey &&
                            _sectionFilter == filter) {
                          _sectionFilterDayKey = null;
                          _sectionFilter = null;
                        } else {
                          _sectionFilterDayKey = dayKey;
                          _sectionFilter = filter;
                        }
                      });
                    },
                    onClearFilter: sectionFiltered
                        ? () {
                            setState(() {
                              _sectionFilterDayKey = null;
                              _sectionFilter = null;
                            });
                          }
                        : null,
                  ),
                ),
                if (transactions.isNotEmpty)
                  Divider(height: 1, thickness: 1, color: dividerColor),
                for (var i = 0; i < transactions.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: dividerColor,
                    ),
                  TransactionItem(
                    transaction: transactions[i],
                    inSectionCard: true,
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (context) => TransactionDetailScreen(
                            transaction: transactions[i],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        },
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
    final options = _collectAppFilterOptions(state.grouped);
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
                    _sectionFilterDayKey = null;
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

class _DayHeaderDateBlock extends StatelessWidget {
  final String dayKey;
  final String dateLabel;
  final double currentTotal;
  final Map<String, double> dailyTotals;

  const _DayHeaderDateBlock({
    required this.dayKey,
    required this.dateLabel,
    required this.currentTotal,
    required this.dailyTotals,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prevKey = _previousCalendarDayKey(dayKey);
    final prevTotal = prevKey != null && dailyTotals.containsKey(prevKey)
        ? dailyTotals[prevKey]!
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          dateLabel,
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.35,
          ),
        ),
        if (prevTotal != null) ...[
          const SizedBox(height: 6),
          _PrevDayRevenueRow(
            previousTotal: prevTotal,
            currentTotal: currentTotal,
          ),
        ],
      ],
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

  const _DayTxnCounts({
    required this.trials,
    required this.conversions,
    required this.renewals,
    required this.purchases,
  });
}

_DayTxnCounts _aggregateDayCounts(List<RcTransaction> transactions) {
  var trials = 0;
  var conversions = 0;
  var renewals = 0;
  var purchases = 0;
  for (final tx in transactions) {
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
  );
}

/// Matches the TRIAL / CONV / REN / SUB day header pills (SUB = new sub + one-time).
enum TransactionDaySectionFilter {
  trial,
  conversion,
  renewal,
  subscription,
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
  }
}

class _DayTypeCountSummary extends StatelessWidget {
  final List<RcTransaction> transactions;
  final TransactionDaySectionFilter? selectedFilter;
  final void Function(TransactionDaySectionFilter filter) onSelectFilter;
  final VoidCallback? onClearFilter;

  const _DayTypeCountSummary({
    required this.transactions,
    required this.selectedFilter,
    required this.onSelectFilter,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final n = _aggregateDayCounts(transactions);
    return Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dayCountSegment(
            context,
            label: 'TRIAL',
            count: n.trials,
            filter: TransactionDaySectionFilter.trial,
            selected: selectedFilter == TransactionDaySectionFilter.trial,
            onTap: onSelectFilter,
          ),
          _dayCountSegment(
            context,
            label: 'CONV',
            count: n.conversions,
            filter: TransactionDaySectionFilter.conversion,
            selected: selectedFilter == TransactionDaySectionFilter.conversion,
            onTap: onSelectFilter,
          ),
          _dayCountSegment(
            context,
            label: 'REN',
            count: n.renewals,
            filter: TransactionDaySectionFilter.renewal,
            selected: selectedFilter == TransactionDaySectionFilter.renewal,
            onTap: onSelectFilter,
          ),
          _dayCountSegment(
            context,
            label: 'SUB',
            count: n.purchases,
            filter: TransactionDaySectionFilter.subscription,
            selected: selectedFilter == TransactionDaySectionFilter.subscription,
            onTap: onSelectFilter,
          ),
          if (onClearFilter != null)
            Material(
              color: Colors.transparent,
              child: ActionChip(
                label: Text(
                  'CLEAR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colorScheme.primary,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: context.colorScheme.outlineVariant),
                backgroundColor:
                    context.colorScheme.primaryContainer.withValues(alpha: 0.35),
                onPressed: onClearFilter,
              ),
            ),
        ],
    );
  }
}

Widget _dayCountSegment(
  BuildContext context, {
  required String label,
  required int count,
  required TransactionDaySectionFilter filter,
  required bool selected,
  required void Function(TransactionDaySectionFilter filter) onTap,
}) {
  final type = _sectionFilterAccentType(filter);
  final color = transactionTypeAccentColor(type, context);
  final enabled = count > 0;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: enabled
          ? () {
              onTap(filter);
            }
          : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.28 : 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.85)
                : color.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
            height: 1.1,
            color: enabled ? color : color.withValues(alpha: 0.45),
          ),
        ),
      ),
    ),
  );
}
