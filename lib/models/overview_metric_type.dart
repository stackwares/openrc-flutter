import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum OverviewMetricValueType { live, total, last }

enum OverviewMetricType {
  mrr(
    icon: Icons.autorenew_rounded,
    label: 'MRR',
    valueType: OverviewMetricValueType.live,
  ),
  subscriptions(
    icon: Icons.repeat_rounded,
    label: 'SUBSCRIPTIONS',
    valueType: OverviewMetricValueType.live,
  ),
  trials(
    icon: Icons.access_time_rounded,
    label: 'TRIALS',
    valueType: OverviewMetricValueType.live,
  ),
  revenue(
    icon: Icons.attach_money_rounded,
    label: 'REVENUE',
    valueType: OverviewMetricValueType.total,
  ),
  users(
    icon: Icons.people_rounded,
    label: 'USERS',
    valueType: OverviewMetricValueType.total,
  ),
  newUsers(
    icon: Icons.person_add_rounded,
    label: 'NEW USERS',
    valueType: OverviewMetricValueType.total,
  ),
  arr(
    icon: Icons.autorenew_rounded,
    label: 'ARR',
    valueType: OverviewMetricValueType.live,
  ),
  proceeds(
    icon: Icons.attach_money_rounded,
    label: 'PROCEEDS',
    valueType: OverviewMetricValueType.total,
  ),
  churnRate(
    icon: Icons.people_outline_rounded,
    label: 'CHURN RATE',
    valueType: OverviewMetricValueType.last,
  ),
  subsLost(
    icon: Icons.people_outline_rounded,
    label: 'SUBS. LOST',
    valueType: OverviewMetricValueType.last,
  ),
  transactions(
    icon: Icons.swap_horiz_rounded,
    label: 'TRANSACTIONS',
    valueType: OverviewMetricValueType.total,
  );

  final IconData icon;
  final String label;
  final OverviewMetricValueType valueType;

  const OverviewMetricType({
    required this.icon,
    required this.label,
    required this.valueType,
  });

  String get subtitle {
    switch (valueType) {
      case OverviewMetricValueType.live:
        return '';
      case OverviewMetricValueType.last:
        return 'This month';
      case OverviewMetricValueType.total:
        return 'Last 30 days';
    }
  }

  String get chartName {
    switch (this) {
      case OverviewMetricType.mrr:
        return 'mrr';
      case OverviewMetricType.subscriptions:
        return 'actives';
      case OverviewMetricType.trials:
        return 'trials';
      case OverviewMetricType.revenue:
        return 'revenue';
      case OverviewMetricType.users:
        return 'actives';
      case OverviewMetricType.newUsers:
        return 'customers_new';
      case OverviewMetricType.arr:
        return 'arr';
      case OverviewMetricType.proceeds:
        return 'revenue';
      case OverviewMetricType.churnRate:
        return 'churn';
      case OverviewMetricType.subsLost:
        return 'churn';
      case OverviewMetricType.transactions:
        return 'revenue';
    }
  }

  /// Series index within `charts_v2` payload `values` (matches [Kedi `OverviewItemType.chartIndex`](https://github.com/sereisoglu/Kedi)).
  int? get chartIndex {
    switch (this) {
      case OverviewMetricType.mrr:
      case OverviewMetricType.trials:
      case OverviewMetricType.revenue:
      case OverviewMetricType.newUsers:
      case OverviewMetricType.arr:
      case OverviewMetricType.proceeds:
      case OverviewMetricType.subscriptions:
      case OverviewMetricType.users:
        return 0;
      case OverviewMetricType.transactions:
      case OverviewMetricType.subsLost:
        return 1;
      case OverviewMetricType.churnRate:
        return 2;
    }
  }

  /// `revenue_type` query param for `charts_v2/revenue` (see Kedi `RCChartRevenueType`).
  String? get chartRevenueTypeParam {
    switch (this) {
      case OverviewMetricType.revenue:
      case OverviewMetricType.transactions:
        return 'revenue';
      case OverviewMetricType.proceeds:
        return 'proceeds';
      default:
        return null;
    }
  }

  bool get hasChart => true;

  bool get isCurrency {
    switch (this) {
      case OverviewMetricType.mrr:
      case OverviewMetricType.revenue:
      case OverviewMetricType.arr:
      case OverviewMetricType.proceeds:
        return true;
      default:
        return false;
    }
  }

  bool get isPercentage => this == OverviewMetricType.churnRate;

  String formatValue(dynamic value) {
    if (value == null) return '—';
    if (isPercentage) {
      final v = (value as num).toDouble();
      return '${v.toStringAsFixed(1)}%';
    }
    if (isCurrency) {
      final v = (value as num).toDouble();
      if (v >= 1000000) {
        return '\$${(v / 1000000).toStringAsFixed(2)}M';
      }
      if (v >= 1000) {
        return '\$${(v / 1000).toStringAsFixed(1)}K';
      }
      return '\$${v.toStringAsFixed(2)}';
    }
    return _formatGroupedCount(value as num);
  }

  Color color(ColorScheme colorScheme) {
    switch (this) {
      case OverviewMetricType.mrr:
        return colorScheme.primary;
      case OverviewMetricType.subscriptions:
        return Colors.blue;
      case OverviewMetricType.trials:
        return Colors.orange;
      case OverviewMetricType.revenue:
        return Colors.green;
      case OverviewMetricType.users:
        return Colors.purple;
      case OverviewMetricType.newUsers:
        return Colors.teal;
      case OverviewMetricType.arr:
        return colorScheme.primary;
      case OverviewMetricType.proceeds:
        return Colors.green;
      case OverviewMetricType.churnRate:
        return Colors.red;
      case OverviewMetricType.subsLost:
        return Colors.red;
      case OverviewMetricType.transactions:
        return Colors.blue;
    }
  }
}

/// Thousands separators for overview counts (e.g. 50000 → 50,000).
String _formatGroupedCount(num n) {
  final d = n.toDouble();
  if (d.isNaN || d.isInfinite) return '—';
  if (d == d.roundToDouble()) {
    return NumberFormat.decimalPatternDigits(
      locale: 'en_US',
      decimalDigits: 0,
    ).format(n.round());
  }
  return NumberFormat('#,##0.##', 'en_US').format(d);
}
