import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/upcoming/upcoming_projection.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';

final _log = Logger('Upcoming');

/// Longest look-ahead the Upcoming screen offers; the loader fetches enough
/// history for it, and shorter views filter the same rows.
const kUpcomingMaxHorizon = Duration(days: 30);

/// Page size for each window sweep; same as payout detail pages.
const upcomingPageLimit = 100;

class UpcomingLoadState {
  const UpcomingLoadState({
    this.transactions = const [],
    this.isLoading = false,
    this.loadComplete = false,
    this.truncated = false,
    this.error,
  });

  /// Rows from every look-back window, deduplicated.
  final List<RcTransaction> transactions;
  final bool isLoading;

  /// Every window was swept (or failed) at least once.
  final bool loadComplete;

  /// A window hit the page cap, so some of its subscriptions are missing.
  final bool truncated;
  final String? error;

  UpcomingLoadState copyWith({
    List<RcTransaction>? transactions,
    bool? isLoading,
    bool? loadComplete,
    bool? truncated,
    String? error,
  }) => UpcomingLoadState(
    transactions: transactions ?? this.transactions,
    isLoading: isLoading ?? this.isLoading,
    loadComplete: loadComplete ?? this.loadComplete,
    truncated: truncated ?? this.truncated,
    error: error,
  );
}

/// Transactions bought one plan length ago (weekly through annual), so their
/// current periods end within [kUpcomingMaxHorizon]. Starts over when the
/// account changes.
final upcomingTransactionsProvider =
    StateNotifierProvider<UpcomingNotifier, UpcomingLoadState>((ref) {
      ref.watch(isSignedInProvider);
      return UpcomingNotifier(ref);
    });

/// Projected events within [horizonDays], from the look-back windows plus
/// everything the transactions feed has loaded (so a sale that just came in
/// replaces the row it renews).
final upcomingEventsProvider = Provider.family<List<UpcomingEvent>, int>((
  ref,
  horizonDays,
) {
  final windows = ref.watch(upcomingTransactionsProvider).transactions;
  final feed = flattenGroupedTransactionsDeduped(
    ref.watch(transactionsProvider.select((s) => s.grouped)),
  );
  return projectUpcoming(
    [...windows, ...feed],
    now: DateTime.now(),
    horizon: Duration(days: horizonDays),
  );
});

class UpcomingNotifier extends StateNotifier<UpcomingLoadState> {
  UpcomingNotifier(this._ref, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const UpcomingLoadState(isLoading: true)) {
    _inFlight = _load().whenComplete(() => _inFlight = null);
  }

  /// Fixed state for tests; does not fetch until [load] is called.
  UpcomingNotifier.ready(this._ref, UpcomingLoadState initial)
    : _clock = DateTime.now,
      super(initial);

  final Ref _ref;
  final DateTime Function() _clock;
  Future<void>? _inFlight;

  Future<void> load() =>
      _inFlight ??= _load().whenComplete(() => _inFlight = null);

  /// The in-flight fetch, or a completed future.
  Future<void> get loaded => _inFlight ?? Future<void>.value();

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final merged = <RcTransaction>[];
    final seen = <String>{};
    var truncated = false;
    try {
      final api = _ref.read(rcApiServiceProvider);
      final windows = upcomingFetchWindows(
        now: _clock(),
        horizon: kUpcomingMaxHorizon,
      );
      for (final window in windows) {
        int? cursor;
        var pages = 0;
        while (true) {
          if (!mounted) return;
          if (pages >= kRealtimeBackfillMaxPages) {
            truncated = true;
            break;
          }
          final response = await _retryAfterRateLimit(
            () => api.transactions(
              cursor == null
                  ? RcTransactionsRequest(
                      limit: upcomingPageLimit,
                      startDate: isoLocalDayKey(window.start),
                      endDate: isoLocalDayKey(window.end),
                    )
                  : RcTransactionsRequest(
                      limit: upcomingPageLimit,
                      startFrom: cursor,
                    ),
              requestContext: 'upcoming',
            ),
          );
          if (!mounted) return;
          final raw = response.transactions ?? [];
          pages++;
          _mergePage(merged, seen, raw.where((tx) => _inWindow(tx, window)));
          if (raw.isEmpty) break;
          final oldest = oldestLocalPurchaseCalendarDay(raw);
          if (oldest != null && oldest.isBefore(window.start)) break;
          final next = _nextCursor(raw, response.lastPurchaseMs);
          if (next == null || next == cursor) break;
          cursor = next;
        }
        // Show what's known as each window lands (recent plans first).
        state = state.copyWith(
          transactions: List.unmodifiable(merged),
          truncated: truncated,
        );
      }
      if (!mounted) return;
      state = UpcomingLoadState(
        transactions: List.unmodifiable(merged),
        loadComplete: true,
        truncated: truncated,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final rcError = _ref.read(rcApiServiceProvider).parseError(e);
      _log.warning('Upcoming load failed: $e');
      state = state.copyWith(
        transactions: merged.isEmpty ? null : List.unmodifiable(merged),
        isLoading: false,
        loadComplete: true,
        error: friendlyApiErrorMessage(e, serverMessage: rcError?.message),
      );
    } catch (e) {
      _log.warning('Upcoming load failed: $e');
      if (!mounted) return;
      state = state.copyWith(
        transactions: merged.isEmpty ? null : List.unmodifiable(merged),
        isLoading: false,
        loadComplete: true,
        error: friendlyApiErrorMessage(e),
      );
    }
  }

  static bool _inWindow(RcTransaction tx, UpcomingWindow window) {
    final day = localPurchaseCalendarDay(tx);
    if (day == null) return false;
    return !day.isBefore(window.start) && !day.isAfter(window.end);
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
      final ms = DateTime.tryParse(
        tx.purchaseDate?.trim() ?? '',
      )?.millisecondsSinceEpoch;
      if (ms == null) continue;
      if (oldest == null || ms < oldest) oldest = ms;
    }
    return oldest == null ? null : oldest - 1;
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

/// Last day the Transactions tab can step forward to (`yyyy-MM-dd`): the end
/// of [kUpcomingMaxHorizon].
String upcomingLastDayKey({DateTime? now}) {
  final n = now ?? DateTime.now();
  return isoLocalDayKey(
    DateTime(n.year, n.month, n.day + kUpcomingMaxHorizon.inDays),
  );
}

/// [events] by the local day they fall on (`yyyy-MM-dd`), soonest first
/// within each day.
Map<String, List<UpcomingEvent>> upcomingEventsByDayKey(
  Iterable<UpcomingEvent> events,
) {
  final out = <String, List<UpcomingEvent>>{};
  for (final e in events) {
    out.putIfAbsent(isoLocalDayKey(e.dueAt), () => []).add(e);
  }
  return out;
}
