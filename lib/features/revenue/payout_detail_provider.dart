import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/rc_api_service.dart';

final _log = Logger('PayoutDetail');

/// Page size for a payout window; same as Revenue tab backfill pages.
const payoutDetailPageLimit = 100;

class PayoutDetailState {
  const PayoutDetailState({
    this.transactions = const [],
    this.isLoading = false,
    this.loadComplete = false,
    this.error,
  });

  final List<RcTransaction> transactions;
  final bool isLoading;
  final bool loadComplete;
  final String? error;

  PayoutDetailState copyWith({
    List<RcTransaction>? transactions,
    bool? isLoading,
    bool? loadComplete,
    String? error,
  }) => PayoutDetailState(
    transactions: transactions ?? this.transactions,
    isLoading: isLoading ?? this.isLoading,
    loadComplete: loadComplete ?? this.loadComplete,
    error: error,
  );
}

/// Transactions in one paid payout's earnings window. Disposed when the
/// detail screen closes.
final payoutDetailTransactionsProvider = StateNotifierProvider.autoDispose
    .family<PayoutDetailNotifier, PayoutDetailState, PayoutPeriod>((
      ref,
      period,
    ) {
      return PayoutDetailNotifier(ref, period);
    });

class PayoutDetailNotifier extends StateNotifier<PayoutDetailState> {
  PayoutDetailNotifier(this._ref, this.period)
    : super(const PayoutDetailState()) {
    final seeded = transactionsForPayout(
      flattenGroupedTransactionsDeduped(
        _ref.read(transactionsProvider).grouped,
      ),
      period,
    );
    state = PayoutDetailState(transactions: seeded, isLoading: true);
    _inFlight = _load().whenComplete(() => _inFlight = null);
  }

  /// Fixed state for tests; does not fetch until [load] is called.
  PayoutDetailNotifier.ready(this._ref, this.period, PayoutDetailState initial)
    : super(initial);

  final Ref _ref;
  final PayoutPeriod period;
  Future<void>? _inFlight;

  Future<void> load() =>
      _inFlight ??= _load().whenComplete(() => _inFlight = null);

  /// The in-flight fetch started by the constructor, or a completed future.
  Future<void> get loaded => _inFlight ?? Future<void>.value();

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, loadComplete: false);
    try {
      final api = _ref.read(rcApiServiceProvider);
      final merged = [...state.transactions];
      final seen = <String>{};
      for (final tx in merged) {
        final key = rcTransactionDedupKey(tx);
        if (key != null) seen.add(key);
      }

      int? cursor;
      var pages = 0;
      while (pages < kRealtimeBackfillMaxPages) {
        if (!mounted) return;
        final response = await _retryAfterRateLimit(
          () => api.transactions(
            cursor == null
                ? RcTransactionsRequest(
                    limit: payoutDetailPageLimit,
                    startDate: dayKey(period.earningsStart),
                    endDate: dayKey(period.earningsEnd),
                  )
                : RcTransactionsRequest(
                    limit: payoutDetailPageLimit,
                    startFrom: cursor,
                  ),
            requestContext: 'payout_detail',
          ),
        );
        if (!mounted) return;
        final raw = response.transactions ?? [];
        pages++;
        _mergePage(merged, seen, transactionsForPayout(raw, period));
        state = state.copyWith(transactions: List.unmodifiable(merged));

        if (raw.isEmpty) break;
        final oldest = oldestLocalPurchaseCalendarDay(raw);
        final start = DateTime(
          period.earningsStart.year,
          period.earningsStart.month,
          period.earningsStart.day,
        );
        if (oldest != null && oldest.isBefore(start)) break;
        final next = _nextCursor(raw, response.lastPurchaseMs);
        if (next == null) break;
        cursor = next;
      }

      if (!mounted) return;
      state = state.copyWith(
        transactions: List.unmodifiable(merged),
        isLoading: false,
        loadComplete: true,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final rcError = _ref.read(rcApiServiceProvider).parseError(e);
      _log.warning('Payout detail load failed: $e');
      state = state.copyWith(
        isLoading: false,
        loadComplete: true,
        error: friendlyApiErrorMessage(e, serverMessage: rcError?.message),
      );
    } catch (e) {
      _log.warning('Payout detail load failed: $e');
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        loadComplete: true,
        error: friendlyApiErrorMessage(e),
      );
    }
  }

  void _mergePage(
    List<RcTransaction> merged,
    Set<String> seen,
    Iterable<RcTransaction> incoming,
  ) {
    for (final tx in incoming) {
      final key = rcTransactionDedupKey(tx);
      if (key != null) {
        if (seen.contains(key)) continue;
        seen.add(key);
      }
      merged.add(tx);
    }
  }

  int? _nextCursor(List<RcTransaction> raw, int? apiLastPurchaseMs) {
    if (apiLastPurchaseMs != null) return apiLastPurchaseMs;
    int? oldest;
    for (final tx in raw) {
      final ms = _purchaseDateMs(tx.purchaseDate);
      if (ms == null) continue;
      if (oldest == null || ms < oldest) oldest = ms;
    }
    if (oldest == null) return null;
    return oldest - 1;
  }

  int? _purchaseDateMs(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return DateTime.tryParse(s.trim())?.millisecondsSinceEpoch;
  }

  Future<T> _retryAfterRateLimit<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final response = e.response;
      if (response == null || response.statusCode != 429 || !mounted) rethrow;
      final seconds = int.tryParse(response.headers.value('retry-after') ?? '');
      await Future<void>.delayed(
        Duration(seconds: (seconds ?? 2).clamp(1, 10)),
      );
      return request();
    }
  }
}
