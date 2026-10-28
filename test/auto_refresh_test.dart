import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/app/auto_refresh.dart';
import 'package:openrc/features/charts/home_notifier.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/models/rc_overview_response.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends RcApiService {
  double mrr = 100;
  bool offline = false;
  bool chartsFail = false;
  int overviewCalls = 0;

  DioException _down() => DioException.connectionError(
    requestOptions: RequestOptions(path: '/overview'),
    reason: 'offline',
  );

  @override
  Future<RcOverviewResponse> overview() async {
    overviewCalls++;
    if (offline) throw _down();
    return RcOverviewResponse(mrr: mrr);
  }

  @override
  Future<RcChartResponse> charts({
    required String name,
    int resolution = 0,
    String? startDate,
    String? endDate,
    String? revenueType,
    Map<String, List<String>>? filters,
  }) async {
    if (chartsFail) throw _down();
    return RcChartResponse(values: [RcChartDataPoint(cohort: 1, value: mrr)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoRefreshPolicy', () {
    late DateTime now;
    late AutoRefreshPolicy policy;

    setUp(() {
      now = DateTime(2026, 10, 28, 9);
      policy = AutoRefreshPolicy(clock: () => now);
    });

    test('reloads after being away long enough', () {
      policy.left();
      now = now.add(AutoRefreshPolicy.staleAfter);
      expect(policy.returned(), isTrue);
    });

    test('a quick app switch does not reload', () {
      policy.left();
      now = now.add(const Duration(minutes: 1));
      expect(policy.returned(), isFalse);
    });

    test('time away counts from when the app first left', () {
      policy.left();
      now = now.add(const Duration(minutes: 4));
      // hidden, then paused: still the same trip away.
      policy.left();
      now = now.add(const Duration(minutes: 1));
      expect(policy.returned(), isTrue);
    });

    test('resuming without having left does not reload', () {
      expect(policy.returned(), isFalse);
      policy.left();
      now = now.add(const Duration(hours: 1));
      expect(policy.returned(), isTrue);
      // The trip away is used up.
      expect(policy.returned(), isFalse);
    });
  });

  group('HomeNotifier.refreshQuietly', () {
    late _Api api;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = _Api();
      container = ProviderContainer(
        overrides: [rcApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
    });

    HomeNotifier notifier() => container.read(homeProvider.notifier);
    HomeState state() => container.read(homeProvider);

    test('does nothing before the first load', () async {
      await notifier().refreshQuietly();
      expect(api.overviewCalls, 0);
      expect(state().overview, isNull);
    });

    test('updates the numbers without a loading state', () async {
      await notifier().fetchData();
      api.mrr = 250;
      final loading = <bool>[];
      container.listen(homeProvider, (_, next) => loading.add(next.isLoading));

      await notifier().refreshQuietly();

      expect(loading, everyElement(isFalse));
      expect(state().overview?.mrr, 250);
      expect(state().charts[OverviewMetricType.mrr]?.values?.single.value, 250);
    });

    test('keeps what is shown when the refresh fails', () async {
      await notifier().fetchData();
      api.offline = true;

      await notifier().refreshQuietly();

      expect(state().overview?.mrr, 100);
      expect(state().error, isNull);
      expect(state().isLoading, isFalse);
    });

    test('keeps the last charts when only the charts fail', () async {
      await notifier().fetchData();
      api
        ..mrr = 300
        ..chartsFail = true;

      await notifier().refreshQuietly();

      expect(state().overview?.mrr, 300);
      expect(state().charts[OverviewMetricType.mrr]?.values?.single.value, 100);
    });
  });
}
