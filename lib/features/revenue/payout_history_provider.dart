import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/services/payout_history_cache.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';

final _log = Logger('PayoutHistory');

class PayoutHistoryState {
  const PayoutHistoryState({
    this.amounts = const {},
    this.isLoading = false,
    this.error,
    this.storeSplitUnavailable = false,
    this.hasLoaded = false,
  });

  /// USD proceeds of each paid payout, by [PayoutPeriod.id].
  final Map<String, double> amounts;

  /// Asking RevenueCat for payouts that are not saved yet.
  final bool isLoading;
  final String? error;

  /// RevenueCat ignored the store filter, so payouts can't be worked out.
  final bool storeSplitUnavailable;

  /// Saved payouts were read and any missing ones requested at least once.
  final bool hasLoaded;

  PayoutHistoryState copyWith({
    Map<String, double>? amounts,
    bool? isLoading,
    String? error,
    bool? storeSplitUnavailable,
    bool? hasLoaded,
  }) => PayoutHistoryState(
    amounts: amounts ?? this.amounts,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    storeSplitUnavailable: storeSplitUnavailable ?? this.storeSplitUnavailable,
    hasLoaded: hasLoaded ?? this.hasLoaded,
  );
}

/// The last 12 months of payouts; starts over when the account changes.
final payoutHistoryProvider =
    StateNotifierProvider<PayoutHistoryNotifier, PayoutHistoryState>((ref) {
      ref.watch(isSignedInProvider);
      return PayoutHistoryNotifier(ref);
    });

class PayoutHistoryNotifier extends StateNotifier<PayoutHistoryState> {
  PayoutHistoryNotifier(
    this._ref, {
    DateTime Function()? clock,
    PayoutHistoryCache cache = const PayoutHistoryCache(),
  }) : _clock = clock ?? DateTime.now,
       _cache = cache,
       super(const PayoutHistoryState());

  final Ref _ref;
  final DateTime Function() _clock;
  final PayoutHistoryCache _cache;
  Future<void>? _inFlight;
  bool _readSaved = false;

  /// Shows saved payouts, then asks RevenueCat only for ones paid since.
  ///
  /// A payout is kept as it was first fetched after its pay date: the store
  /// has sent that money, and later refunds come out of a later payout.
  Future<void> load() =>
      _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    final account = _ref.read(rcMeProvider)?.distinctId;
    var amounts = state.amounts;
    if (!_readSaved && account != null) {
      _readSaved = true;
      amounts = {...await _cache.read(account), ...amounts};
      if (!mounted) return;
    }

    final paid = [
      for (final store in PayoutStore.values) ...paidPayouts(store, _clock()),
    ];
    final missing = [
      for (final p in paid)
        if (!amounts.containsKey(p.id)) p,
    ];
    if (missing.isEmpty) {
      state = state.copyWith(
        amounts: amounts,
        isLoading: false,
        hasLoaded: true,
      );
      return;
    }

    state = state.copyWith(amounts: amounts, isLoading: true);
    try {
      final daily = await _fetchDaily(missing);
      if (!mounted) return;
      if (daily == null) {
        state = state.copyWith(
          isLoading: false,
          storeSplitUnavailable: true,
          hasLoaded: true,
        );
        return;
      }
      // Keeps saved totals as they were and drops months past the window.
      final next = {
        for (final p in paid)
          p.id: amounts[p.id] ?? payoutTotal(p, daily[p.store]!),
      };
      state = state.copyWith(
        amounts: next,
        isLoading: false,
        storeSplitUnavailable: false,
        hasLoaded: true,
      );
      await _cache.write(account, next);
    } on DioException catch (e) {
      if (!mounted) return;
      final rcError = _ref.read(rcApiServiceProvider).parseError(e);
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: friendlyApiErrorMessage(e, serverMessage: rcError?.message),
      );
    } catch (e) {
      _log.warning('Payout load failed: $e');
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        hasLoaded: true,
        error: friendlyApiErrorMessage(e),
      );
    }
  }

  /// Daily proceeds per store over the days [missing] covers, or null when
  /// RevenueCat ignored the store filter.
  Future<Map<PayoutStore, Map<String, double>>?> _fetchDaily(
    List<PayoutPeriod> missing,
  ) async {
    final api = _ref.read(rcApiServiceProvider);
    final daily = {for (final s in PayoutStore.values) s: <String, double>{}};
    for (final range in chartRangesFor(missing)) {
      // Both stores every time: comparing them is how an ignored filter shows.
      final responses = await Future.wait([
        for (final store in PayoutStore.values)
          _retryAfterRateLimit(
            () => api.charts(
              name: 'revenue',
              startDate: dayKey(range.start),
              endDate: dayKey(range.end),
              revenueType: 'proceeds',
              filters: {'store': store.chartStores},
            ),
          ),
      ]);
      final ignored = {for (final r in responses) ...r.ignoredParams};
      final apple = dailyProceeds(responses[0]);
      final google = dailyProceeds(responses[1]);
      if (ignored.contains('store') || storeFilterIgnored(apple, google)) {
        _log.warning('RevenueCat ignored the chart store filter: $ignored');
        return null;
      }
      daily[PayoutStore.apple]!.addAll(apple);
      daily[PayoutStore.google]!.addAll(google);
    }
    return daily;
  }

  /// Retries once after a 429, waiting as long as RevenueCat asks (1–10 s).
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
