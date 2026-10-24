import 'package:openrc/models/agent_block.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/models/rc_chart_response.dart';

/// Reads `present` / tool payloads without depending on widgets.
class AgentBlockPayload {
  const AgentBlockPayload(this.raw);

  final Map<String, dynamic> raw;

  Map<String, dynamic> get overview =>
      (raw['overview'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};

  Map<String, dynamic> get overviewUsd =>
      (raw['overview_usd'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};

  Map<String, dynamic>? get chart =>
      (raw['chart'] as Map?)?.cast<String, dynamic>();

  List<dynamic> get values => chart?['values'] as List? ?? const [];

  List<dynamic> get transactions => raw['transactions'] as List? ?? const [];

  List<dynamic> get payouts => raw['payouts'] as List? ?? const [];

  List<dynamic> get nextPaydays => raw['next_paydays'] as List? ?? const [];

  List<dynamic> get rows => raw['rows'] as List? ?? const [];

  List<String> get columns => [
        for (final c in raw['columns'] as List? ?? const [])
          if (c != null) '$c',
      ];

  String? get markdown => raw['markdown'] as String?;

  String? get metricName => raw['metric'] as String?;

  OverviewMetricType metricType() {
    final name = metricName ?? '';
    return OverviewMetricType.values.firstWhere(
      (m) => m.chartName == name || m.name == name,
      orElse: () => OverviewMetricType.mrr,
    );
  }

  List<RcChartDataPoint> chartPoints() {
    return [
      for (final item in values)
        if (item is Map)
          RcChartDataPoint(
            cohort: (item['cohort'] as num?)?.toInt(),
            measure: (item['measure'] as num?)?.toInt(),
            value: (item['value'] as num?)?.toDouble(),
          ),
    ];
  }

  DateTime rangeStart() {
    final rawStart = raw['range_start'] as String?;
    if (rawStart != null) {
      final parsed = DateTime.tryParse(rawStart);
      if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final points = chartPoints();
    final cohort = points.isEmpty ? null : points.first.cohort;
    if (cohort != null && cohort > 0) {
      final ms = cohort > 20000000000 ? cohort : cohort * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
    final end = DateTime.now();
    return DateTime(end.year, end.month, end.day).subtract(const Duration(days: 29));
  }

  /// The day each chart point covers: its cohort timestamp, else counted
  /// from [rangeStart].
  List<DateTime> chartPointDays() {
    final points = chartPoints();
    final start = rangeStart();
    return [
      for (var i = 0; i < points.length; i++)
        _cohortDay(points[i].cohort) ??
            DateTime(start.year, start.month, start.day + i),
    ];
  }

  static DateTime? _cohortDay(int? cohort) {
    if (cohort == null || cohort <= 0) return null;
    final ms = cohort > 20000000000 ? cohort : cohort * 1000;
    // Cohorts start a UTC day; keep that calendar day.
    final utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// The view that can show this payload: [requested] when its data is
  /// here, otherwise the one that matches what the tool returned. Models
  /// sometimes ask for a table of transactions or a chart of the overview.
  AgentPresentationType resolveView(AgentPresentationType requested) {
    final hasChart = chartPoints().isNotEmpty;
    final hasOverview = overviewMetricKeys.keys.any(
      (k) => overviewUsd[k] is num || overview[k] is num,
    );
    final hasTransactions = transactions.isNotEmpty;
    final hasPayouts = payouts.isNotEmpty || nextPaydays.isNotEmpty;
    final hasRows = rows.isNotEmpty || values.isNotEmpty;
    final fits = switch (requested) {
      AgentPresentationType.markdown => (markdown ?? '').trim().isNotEmpty,
      AgentPresentationType.metricCards => hasOverview,
      AgentPresentationType.lineChart => hasChart,
      AgentPresentationType.barChart => hasPayouts,
      AgentPresentationType.dataTable => hasRows,
      AgentPresentationType.transactionList => hasTransactions,
    };
    if (fits) return requested;
    if (hasTransactions) return AgentPresentationType.transactionList;
    if (hasChart) return AgentPresentationType.lineChart;
    if (hasOverview) return AgentPresentationType.metricCards;
    if (hasPayouts) return AgentPresentationType.barChart;
    return requested;
  }

  static const overviewMetricKeys = <String, OverviewMetricType>{
    'mrr': OverviewMetricType.mrr,
    'revenue': OverviewMetricType.revenue,
    'subscriptions': OverviewMetricType.subscriptions,
    'trials': OverviewMetricType.trials,
    'users': OverviewMetricType.users,
    'new_users': OverviewMetricType.newUsers,
  };
}
