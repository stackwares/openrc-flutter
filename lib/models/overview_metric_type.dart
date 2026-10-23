import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/theme/app_colors.dart';

enum OverviewMetricValueType { live, total, last }

enum OverviewMetricType {
  mrr(
    icon: Icons.autorenew_rounded,
    labelKey: 'charts.metric.mrr',
    valueType: OverviewMetricValueType.live,
  ),
  subscriptions(
    icon: Icons.repeat_rounded,
    labelKey: 'charts.metric.subscriptions',
    valueType: OverviewMetricValueType.live,
  ),
  trials(
    icon: Icons.access_time_rounded,
    labelKey: 'charts.metric.trials',
    valueType: OverviewMetricValueType.live,
  ),
  revenue(
    icon: Icons.attach_money_rounded,
    labelKey: 'charts.metric.revenue',
    valueType: OverviewMetricValueType.total,
  ),
  users(
    icon: Icons.people_rounded,
    labelKey: 'charts.metric.users',
    valueType: OverviewMetricValueType.total,
  ),
  newUsers(
    icon: Icons.person_add_rounded,
    labelKey: 'charts.metric.newUsers',
    valueType: OverviewMetricValueType.total,
  ),
  arr(
    icon: Icons.autorenew_rounded,
    labelKey: 'charts.metric.arr',
    valueType: OverviewMetricValueType.live,
  ),
  proceeds(
    icon: Icons.attach_money_rounded,
    labelKey: 'charts.metric.proceeds',
    valueType: OverviewMetricValueType.total,
  ),
  churnRate(
    icon: Icons.people_outline_rounded,
    labelKey: 'charts.metric.churnRate',
    valueType: OverviewMetricValueType.last,
  ),
  subsLost(
    icon: Icons.people_outline_rounded,
    labelKey: 'charts.metric.subsLost',
    valueType: OverviewMetricValueType.last,
  ),
  transactions(
    icon: Icons.swap_horiz_rounded,
    labelKey: 'charts.metric.transactions',
    valueType: OverviewMetricValueType.total,
  );

  final IconData icon;

  /// Translation key for [label] (see `charts.metric.*` in `en.json`).
  final String labelKey;
  final OverviewMetricValueType valueType;

  const OverviewMetricType({
    required this.icon,
    required this.labelKey,
    required this.valueType,
  });

  String get label => labelKey.tr();

  String get subtitle {
    switch (valueType) {
      case OverviewMetricValueType.live:
        return '';
      case OverviewMetricValueType.last:
        return 'charts.presets.thisMonth'.tr();
      case OverviewMetricValueType.total:
        return 'charts.presets.last30Days'.tr();
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
    final c = AppColors.forBrightness(colorScheme.brightness);
    switch (this) {
      case OverviewMetricType.mrr:
      case OverviewMetricType.arr:
        return colorScheme.primary;
      case OverviewMetricType.subscriptions:
      case OverviewMetricType.transactions:
        return c.purchase;
      case OverviewMetricType.trials:
        return c.trial;
      case OverviewMetricType.revenue:
      case OverviewMetricType.proceeds:
        return c.positive;
      case OverviewMetricType.users:
        return c.oneTimePurchase;
      case OverviewMetricType.newUsers:
        return c.conversion;
      case OverviewMetricType.churnRate:
      case OverviewMetricType.subsLost:
        return c.negative;
    }
  }

  /// Higher values are good news (false for churn and lost subscriptions).
  bool get higherIsBetter =>
      this != OverviewMetricType.churnRate &&
      this != OverviewMetricType.subsLost;
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
