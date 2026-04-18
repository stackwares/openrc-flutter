import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
import 'package:revenuecat/models/rc_chart_response.dart';
import 'package:revenuecat/models/rc_overview_response.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/talker_service.dart';

DateTime _localToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class HomeState {
  /// Inclusive chart API range (**device local** calendar dates, midnight local).
  final DateTime chartRangeStart;
  final DateTime chartRangeEnd;

  final RcOverviewResponse? overview;
  final Map<OverviewMetricType, RcChartResponse> charts;
  final bool isLoading;
  final String? error;

  const HomeState({
    required this.chartRangeStart,
    required this.chartRangeEnd,
    this.overview,
    this.charts = const {},
    this.isLoading = false,
    this.error,
  });

  factory HomeState.initial() {
    final end = _localToday();
    final start = end.subtract(const Duration(days: 29));
    return HomeState(chartRangeStart: start, chartRangeEnd: end);
  }

  HomeState copyWith({
    DateTime? chartRangeStart,
    DateTime? chartRangeEnd,
    RcOverviewResponse? overview,
    Map<OverviewMetricType, RcChartResponse>? charts,
    bool? isLoading,
    String? error,
  }) =>
      HomeState(
        chartRangeStart: chartRangeStart ?? this.chartRangeStart,
        chartRangeEnd: chartRangeEnd ?? this.chartRangeEnd,
        overview: overview ?? this.overview,
        charts: charts ?? this.charts,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class HomeNotifier extends StateNotifier<HomeState> {
  final Ref _ref;

  HomeNotifier(this._ref) : super(HomeState.initial());

  static const int maxChartRangeDays = 366;

  /// Local calendar date for the [index]th daily bucket in chart data (day resolution, ordered points).
  DateTime dateForChartPoint(int index) {
    return state.chartRangeStart.add(Duration(days: index));
  }

  /// Label for cards / app bar (localizable date formatting).
  String formatChartRangeLabel() {
    final start = state.chartRangeStart;
    final end = state.chartRangeEnd;
    final ymd = DateFormat.yMMMd();
    if (start.year == end.year) {
      final md = DateFormat.MMMd();
      return '${md.format(start)} – ${ymd.format(end)}';
    }
    return '${ymd.format(start)} – ${ymd.format(end)}';
  }

  void setChartDateRange(DateTime start, DateTime end) {
    var s = DateTime(start.year, start.month, start.day);
    var e = DateTime(end.year, end.month, end.day);
    if (s.isAfter(e)) {
      final t = s;
      s = e;
      e = t;
    }
    final span = e.difference(s).inDays;
    if (span > maxChartRangeDays) {
      e = s.add(Duration(days: maxChartRangeDays));
    }
    state = state.copyWith(chartRangeStart: s, chartRangeEnd: e);
    fetchData();
  }

  Future<void> fetchData() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final api = _ref.read(rcApiServiceProvider);
      final overviewResp = await api.overview();

      final chartFutures = <Future<MapEntry<OverviewMetricType, RcChartResponse>>>[];
      for (final metric in OverviewMetricType.values) {
        chartFutures.add(_fetchChart(api, metric));
      }

      final chartResults = await Future.wait(chartFutures);
      final chartsMap = <OverviewMetricType, RcChartResponse>{};
      for (final entry in chartResults) {
        chartsMap[entry.key] = entry.value;
      }

      state = state.copyWith(
        overview: overviewResp,
        charts: chartsMap,
        isLoading: false,
      );
    } on DioException catch (e, st) {
      _handleAuthError(e);
      final msg = _extractErrorMessage(e);
      _ref.read(talkerProvider).handle(
            e,
            st,
            'Home load failed (overview/charts): $msg | '
            '${e.type} HTTP ${e.response?.statusCode} ${e.requestOptions.uri}',
          );
      state = state.copyWith(
        isLoading: false,
        error: msg,
      );
    } catch (e, st) {
      _ref.read(talkerProvider).handle(e, st, 'Home load failed (unexpected)');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load overview',
      );
    }
  }

  Future<MapEntry<OverviewMetricType, RcChartResponse>> _fetchChart(
    RcApiService api,
    OverviewMetricType metric,
  ) async {
    try {
      final start = state.chartRangeStart;
      final end = state.chartRangeEnd;
      final ymd = DateFormat('yyyy-MM-dd');
      final response = await api.charts(
        name: metric.chartName,
        resolution: 0,
        startDate: ymd.format(start),
        endDate: ymd.format(end),
      );
      return MapEntry(metric, response);
    } catch (e, st) {
      _ref.read(talkerProvider).handle(
            e,
            st,
            'Home chart failed (${metric.name} / ${metric.chartName})',
          );
      return MapEntry(metric, const RcChartResponse());
    }
  }

  double? _adjustOverviewMoney(double? v) {
    if (v == null) return null;
    final s = _ref.read(commissionSettingsProvider);
    return adjustUsdForDisplay(gross: v, settings: s, useBlended: true);
  }

  dynamic getValue(OverviewMetricType metric) {
    final overview = state.overview;
    if (overview == null) return null;

    switch (metric) {
      case OverviewMetricType.mrr:
        return _adjustOverviewMoney(overview.mrr);
      case OverviewMetricType.subscriptions:
        return overview.subscriptions;
      case OverviewMetricType.trials:
        return overview.trials;
      case OverviewMetricType.revenue:
        return _adjustOverviewMoney(overview.revenue);
      case OverviewMetricType.users:
        return overview.users;
      case OverviewMetricType.newUsers:
        return overview.newUsers;
      case OverviewMetricType.arr:
        final mrr = overview.mrr;
        if (mrr == null) return null;
        final netMrr = _adjustOverviewMoney(mrr);
        return netMrr != null ? netMrr * 12 : null;
      case OverviewMetricType.proceeds:
        final chart = state.charts[OverviewMetricType.proceeds];
        return _adjustOverviewMoney(chart?.getSummaryValue('total', 'Proceeds'));
      case OverviewMetricType.churnRate:
        final chart = state.charts[OverviewMetricType.churnRate];
        final values = chart?.values;
        if (values != null && values.isNotEmpty) {
          final last = values.last;
          return last.value;
        }
        return null;
      case OverviewMetricType.subsLost:
        final chart = state.charts[OverviewMetricType.subsLost];
        final values = chart?.values;
        if (values != null && values.isNotEmpty) {
          final last = values.last;
          return last.value;
        }
        return null;
      case OverviewMetricType.transactions:
        final chart = state.charts[OverviewMetricType.transactions];
        return chart?.getSummaryInt('total', 'Transactions');
    }
  }

  List<RcChartDataPoint>? getChartData(OverviewMetricType metric) {
    final chart = state.charts[metric];
    final values = chart?.values;
    if (values == null || values.isEmpty) return null;

    final index = metric.chartIndex;
    List<RcChartDataPoint> list;
    if (index != null) {
      list = values.where((p) => p.measure == index).toList();
    } else {
      list = values;
    }

    if (!metric.isCurrency) return list;

    final c = _ref.read(commissionSettingsProvider);
    if (!c.adjustmentEnabled) return list;

    final mult = netMultiplierBlended(c);
    return list
        .map(
          (p) => RcChartDataPoint(
            cohort: p.cohort,
            measure: p.measure,
            value: p.value == null ? null : p.value! * mult,
          ),
        )
        .toList();
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
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier(ref);
});
