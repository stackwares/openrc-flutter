import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/payout_history_provider.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/services/payout_history_cache.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers revenue charts with a fixed amount per day for each store.
class _ChartsApi extends RcApiService {
  _ChartsApi({
    this.ignoreFilter = false,
    this.flagStoreUnsupported = false,
    this.fail = false,
  });

  static const appleDaily = 10.0;
  static const googleDaily = 2.0;

  /// Sends every store's total for each store, silently.
  final bool ignoreFilter;

  /// Lists `store` under `unsupported_params`, as RevenueCat does.
  final bool flagStoreUnsupported;
  final bool fail;
  final requests = <String>[];

  @override
  Future<RcChartResponse> charts({
    required String name,
    int resolution = 0,
    String? startDate,
    String? endDate,
    String? revenueType,
    Map<String, List<String>>? filters,
  }) async {
    final stores = filters?['store'] ?? const <String>[];
    requests.add('$name|$revenueType|${stores.join(',')}|$startDate|$endDate');
    if (fail) {
      throw DioException(
        requestOptions: RequestOptions(path: '/me/charts_v2/$name'),
        type: DioExceptionType.connectionError,
      );
    }
    final perDay = ignoreFilter
        ? appleDaily + googleDaily
        : stores.contains('app_store')
        ? appleDaily
        : googleDaily;
    final start = DateTime.parse(startDate!);
    final end = DateTime.parse(endDate!);
    return RcChartResponse(
      values: [
        for (
          var d = DateTime.utc(start.year, start.month, start.day);
          !d.isAfter(DateTime.utc(end.year, end.month, end.day));
          d = d.add(const Duration(days: 1))
        )
          RcChartDataPoint(
            cohort: d.millisecondsSinceEpoch ~/ 1000,
            measure: 0,
            value: perDay,
          ),
      ],
      unsupportedParams: flagStoreUnsupported
          ? const {
              'filters': ['store'],
            }
          : null,
    );
  }
}

/// One app session's payout history.
class _Session {
  _Session(this._container);

  final ProviderContainer _container;

  Future<void> load() => _container.read(payoutHistoryProvider.notifier).load();

  PayoutHistoryState get state => _container.read(payoutHistoryProvider);
}

/// A fresh app session: its own notifier, the same saved preferences.
_Session _session(
  _ChartsApi api, {
  DateTime? today,
  String? account = 'acct_1',
}) {
  final container = ProviderContainer(
    overrides: [
      rcApiServiceProvider.overrideWithValue(api),
      rcMeProvider.overrideWith(
        (ref) => account == null ? null : RcMeResponse(distinctId: account),
      ),
      payoutHistoryProvider.overrideWith(
        (ref) => PayoutHistoryNotifier(
          ref,
          clock: () => today ?? DateTime(2026, 10, 23),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Keep the notifier alive for the whole test.
  container.listen(payoutHistoryProvider, (_, _) {});
  return _Session(container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final today = DateTime(2026, 10, 23);
  final lastApple = paidPayouts(PayoutStore.apple, today).last;
  final lastGoogle = paidPayouts(PayoutStore.google, today).last;

  test(
    'first load asks both stores for proceeds and totals each payout',
    () async {
      final api = _ChartsApi();
      final history = _session(api);
      await history.load();

      // A year of days needs two requests per store.
      expect(api.requests, hasLength(4));
      expect(api.requests, everyElement(startsWith('revenue|proceeds|')));
      expect(
        api.requests.where((r) => r.contains('|app_store,mac_app_store|')),
        hasLength(2),
      );
      expect(
        api.requests.where((r) => r.contains('|play_store|')),
        hasLength(2),
      );

      final state = history.state;
      expect(state.hasLoaded, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.amounts, hasLength(11 + 12));
      // Aug 2–29: 28 days; September: 30 days.
      expect(state.amounts[lastApple.id], 28 * _ChartsApi.appleDaily);
      expect(state.amounts[lastGoogle.id], 30 * _ChartsApi.googleDaily);
    },
  );

  test('saved payouts are never fetched again', () async {
    await _session(_ChartsApi()).load();

    final api = _ChartsApi();
    final history = _session(api);
    await history.load();
    expect(api.requests, isEmpty);
    expect(history.state.amounts, hasLength(23));
    expect(history.state.hasLoaded, isTrue);
  });

  test('after a payday only that payout is fetched', () async {
    await _session(_ChartsApi()).load();

    // The App Store paid Aug 30–Sep 26 on Oct 29.
    final api = _ChartsApi();
    final history = _session(api, today: DateTime(2026, 10, 30));
    await history.load();
    expect(api.requests, [
      'revenue|proceeds|app_store,mac_app_store|2026-08-30|2026-09-26',
      'revenue|proceeds|play_store|2026-08-30|2026-09-26',
    ]);
    expect(history.state.amounts['apple:2026-08-30'], 280);
    expect(history.state.amounts[lastApple.id], 280);
  });

  test('another account starts over', () async {
    await _session(_ChartsApi()).load();

    final api = _ChartsApi();
    await _session(api, account: 'acct_2').load();
    expect(api.requests, hasLength(4));
  });

  test('without a known account nothing is read or saved', () async {
    await _session(_ChartsApi(), account: null).load();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('signing out clears saved payouts', () async {
    await _session(_ChartsApi()).load();
    await PayoutHistoryCache.clear();

    final api = _ChartsApi();
    await _session(api).load();
    expect(api.requests, hasLength(4));
  });

  test(
    'an ignored store filter shows as unavailable and saves nothing',
    () async {
      final history = _session(_ChartsApi(ignoreFilter: true));
      await history.load();
      expect(history.state.storeSplitUnavailable, isTrue);
      expect(history.state.amounts, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test(
    'a store filter RevenueCat flags as unsupported is not trusted',
    () async {
      final history = _session(_ChartsApi(flagStoreUnsupported: true));
      await history.load();
      expect(history.state.storeSplitUnavailable, isTrue);
      expect(history.state.amounts, isEmpty);
    },
  );

  test('a failed request keeps saved payouts and reports it', () async {
    await _session(_ChartsApi()).load();

    final history = _session(
      _ChartsApi(fail: true),
      today: DateTime(2026, 10, 30),
    );
    await history.load();
    expect(history.state.error, isNotNull);
    expect(history.state.isLoading, isFalse);
    expect(history.state.amounts, hasLength(23));
  });

  test('loads at the same time share one request set', () async {
    final api = _ChartsApi();
    final history = _session(api);
    await Future.wait([history.load(), history.load()]);
    expect(api.requests, hasLength(4));
  });
}
