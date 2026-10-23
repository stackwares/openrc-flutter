import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/charts/home_notifier.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
import 'package:revenuecat/models/rc_chart_response.dart';
import 'package:revenuecat/models/rc_overview_response.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingApi extends RcApiService {
  final requested = <String>[];

  @override
  Future<RcOverviewResponse> overview() async => const RcOverviewResponse();

  @override
  Future<RcChartResponse> charts({
    required String name,
    int resolution = 0,
    String? startDate,
    String? endDate,
    String? revenueType,
  }) async {
    requested.add('$name|${revenueType ?? ''}');
    return const RcChartResponse();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each distinct chart is requested once per load', () async {
    final api = _CountingApi();
    final container = ProviderContainer(
      overrides: [rcApiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(homeProvider.notifier).fetchData();

    final distinct = OverviewMetricType.values
        .map((m) => '${m.chartName}|${m.chartRevenueTypeParam ?? ''}')
        .toSet();
    expect(api.requested.length, distinct.length);
    expect(api.requested.toSet(), distinct);
    expect(api.requested.length, lessThan(OverviewMetricType.values.length));
    // Every metric still gets its chart.
    final charts = container.read(homeProvider).charts;
    expect(charts.keys.toSet(), OverviewMetricType.values.toSet());
  });
}
