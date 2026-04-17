import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_item.dart';

class TransactionsState {
  final Map<String, List<RcTransaction>> grouped;
  final Map<String, double> dailyTotals;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int? lastPurchaseMs;
  final String? error;

  const TransactionsState({
    this.grouped = const {},
    this.dailyTotals = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.lastPurchaseMs,
    this.error,
  });

  TransactionsState copyWith({
    Map<String, List<RcTransaction>>? grouped,
    Map<String, double>? dailyTotals,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? lastPurchaseMs,
    String? error,
  }) =>
      TransactionsState(
        grouped: grouped ?? this.grouped,
        dailyTotals: dailyTotals ?? this.dailyTotals,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        lastPurchaseMs: lastPurchaseMs ?? this.lastPurchaseMs,
        error: error,
      );
}

class TransactionsNotifier extends StateNotifier<TransactionsState> {
  final Ref _ref;

  TransactionsNotifier(this._ref) : super(const TransactionsState());

  Future<void> fetchInitial() async {
    state = state.copyWith(isLoading: true, error: null);
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
        lastPurchaseMs: response.lastPurchaseMs,
      );
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

  Future<void> fetchMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

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
        existingGrouped[entry.key]!.addAll(entry.value);
      }

      final dailyTotals = _calculateDailyTotals(existingGrouped);
      state = state.copyWith(
        grouped: existingGrouped,
        dailyTotals: dailyTotals,
        isLoadingMore: false,
        hasMore: newTransactions.length >= 100,
        lastPurchaseMs: response.lastPurchaseMs,
      );
    } on DioException catch (e) {
      _handleAuthError(e);
      state = state.copyWith(isLoadingMore: false);
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
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
        return DateFormat('yyyy-MM-dd').format(dt);
      }
    } catch (_) {}
    return dateStr;
  }

  Map<String, double> _calculateDailyTotals(
    Map<String, List<RcTransaction>> grouped,
  ) {
    final totals = <String, double>{};
    for (final entry in grouped.entries) {
      totals[entry.key] = entry.value
          .where((tx) => tx.wasRefunded != true)
          .fold(0.0, (sum, tx) => sum + (tx.revenue ?? 0));
    }
    return totals;
  }
}

final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, TransactionsState>((ref) {
  return TransactionsNotifier(ref);
});

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scrollController = ScrollController();

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
            icon: const Icon(Icons.logout),
            onPressed: () async {
              UtilitiesService.hapticMedium();
              await ref.read(rcAuthServiceProvider).signOut();
              if (context.mounted) context.go('/sign-in');
            },
            tooltip: 'Sign Out',
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

    final sortedKeys = state.grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(transactionsProvider.notifier).fetchInitial(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: sortedKeys.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= sortedKeys.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final dayKey = sortedKeys[index];
          final transactions = state.grouped[dayKey]!;
          final dailyTotal = state.dailyTotals[dayKey] ?? 0;
          final header = _formatDayHeader(dayKey, dailyTotal);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        header,
                        style: context.textTheme.titleSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...transactions.map(
                (tx) => TransactionItem(transaction: tx),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDayHeader(String dayKey, double total) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dayKey);
      final formatted = DateFormat('EEE, MMM d, yyyy').format(date);
      if (total > 0) {
        final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
        return '$formatted  \u2022  ${currency.format(total)}';
      }
      return formatted;
    } catch (_) {
      return dayKey;
    }
  }
}
