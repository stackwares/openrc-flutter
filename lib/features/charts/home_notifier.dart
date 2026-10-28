import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/models/rc_overview_response.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';

final _homeLog = Logger('HomeNotifier');

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

  /// Prefer API [RcChartDataPoint.cohort] (Unix s or ms) when present; else [dateForChartPoint].
  DateTime dateForChartDataPoint(RcChartDataPoint point, int indexFallback) {
    final c = point.cohort;
    if (c != null && c > 0) {
      final ms = c < 10000000000 ? c * 1000 : c;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    return dateForChartPoint(indexFallback);
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

  /// Incremented per [fetchData]; responses from older calls are dropped so a
  /// slow request for a previous date range can't overwrite newer data.
  int _fetchGeneration = 0;

  bool _isCurrent(int generation) => mounted && generation == _fetchGeneration;

  Future<void> fetchData() async {
    final generation = ++_fetchGeneration;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final (overview, charts) = await _load();
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        overview: overview,
        charts: {
          for (final MapEntry(:key, :value) in charts.entries)
            key: value ?? const RcChartResponse(),
        },
        isLoading: false,
      );
    } on DioException catch (e, st) {
      if (!_isCurrent(generation)) return;
      _handleAuthError(e);
      final msg = _extractErrorMessage(e);
      _homeLog.severe(
        'Home load failed (overview/charts): $msg | '
        '${e.type} HTTP ${e.response?.statusCode} ${e.requestOptions.uri}',
        e,
        st,
      );
      state = state.copyWith(
        isLoading: false,
        error: msg,
      );
    } catch (e, st) {
      _homeLog.severe('Home load failed (unexpected)', e, st);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        isLoading: false,
        error: 'charts.errors.loadOverview'.tr(),
      );
    }
  }

  /// A refresh the user didn't ask for (back in the app, a sale arrived):
  /// what's on screen stays, with no loading state, until new numbers land,
  /// and stays if the refresh fails. Skipped before the first load and while
  /// another load runs.
  Future<void> refreshQuietly() async {
    if (state.overview == null || state.isLoading) return;
    final generation = ++_fetchGeneration;
    try {
      final (overview, charts) = await _load();
      if (!_isCurrent(generation)) return;
      final previous = state.charts;
      state = state.copyWith(
        overview: overview,
        charts: {
          for (final MapEntry(:key, :value) in charts.entries)
            key: value ?? previous[key] ?? const RcChartResponse(),
        },
      );
    } on DioException catch (e, st) {
      if (!_isCurrent(generation)) return;
      _handleAuthError(e);
      _homeLog.warning(
        'Background home refresh failed: ${e.type} '
        'HTTP ${e.response?.statusCode} ${e.requestOptions.uri}',
        e,
        st,
      );
    } catch (e, st) {
      _homeLog.warning('Background home refresh failed (unexpected)', e, st);
    }
  }

  /// The overview and every metric's chart; a chart that failed is `null`.
  Future<(RcOverviewResponse, Map<OverviewMetricType, RcChartResponse?>)>
  _load() async {
    final api = _ref.read(rcApiServiceProvider);
    final overviewResp = await api.overview();

    // Several metrics read different series of the same chart (e.g.
    // Subscriptions and Users are both `actives`): request each chart once.
    final requests = <String, Future<RcChartResponse?>>{};
    for (final metric in OverviewMetricType.values) {
      requests.putIfAbsent(
        '${metric.chartName}|${metric.chartRevenueTypeParam ?? ''}',
        () => _fetchChart(api, metric),
      );
    }
    final responses = await Future.wait(requests.values);
    final byKey = Map.fromIterables(requests.keys, responses);
    return (
      overviewResp,
      {
        for (final metric in OverviewMetricType.values)
          metric:
              byKey['${metric.chartName}|${metric.chartRevenueTypeParam ?? ''}'],
      },
    );
  }

  Future<RcChartResponse?> _fetchChart(
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
        revenueType: metric.chartRevenueTypeParam,
      );
      return response;
    } catch (e, st) {
      _homeLog.severe(
        'Home chart failed (${metric.name} / ${metric.chartName})',
        e,
        st,
      );
      return null;
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
      list = List<RcChartDataPoint>.from(values);
    }

    list.sort((a, b) => (a.cohort ?? 0).compareTo(b.cohort ?? 0));

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
      _ref
          .read(rcAuthServiceProvider)
          .signOut(reason: SignOutReason.sessionExpired);
    }
  }

  String? _extractErrorMessage(DioException e) {
    final rcError = _ref.read(rcApiServiceProvider).parseError(e);
    return friendlyApiErrorMessage(e, serverMessage: rcError?.message);
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier(ref);
});
