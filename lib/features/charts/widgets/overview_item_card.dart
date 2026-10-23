import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/charts/widgets/overview_sparkline_chart.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
import 'package:revenuecat/models/rc_chart_response.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/delta_badge.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

/// Change across the chart range for "live" metrics (MRR, subscriptions, …);
/// null for totals, where first→last of a daily series means nothing.
DeltaBadge? overviewRangeDelta(
  OverviewMetricType metric,
  List<RcChartDataPoint>? points, {
  bool filled = false,
}) {
  if (metric.valueType != OverviewMetricValueType.live) return null;
  final values = points?.map((p) => p.value).nonNulls.toList() ?? const [];
  if (values.length < 2 || values.first.abs() < 1e-9) return null;
  return DeltaBadge.percent(
    current: values.last,
    previous: values.first,
    higherIsBetter: metric.higherIsBetter,
    filled: filled,
    comparison: 'the start of this range',
  );
}

class OverviewItemCard extends ConsumerWidget {
  final OverviewMetricType metric;
  final dynamic value;
  final List<RcChartDataPoint>? chartData;
  final bool isLoading;

  /// Replaces [OverviewMetricType.subtitle] when set (e.g. selected chart date range).
  final String? chartPeriodLabel;

  final VoidCallback? onTap;

  /// Full-width hero version with a larger value and chart.
  final bool featured;

  const OverviewItemCard({
    super.key,
    required this.metric,
    this.value,
    this.chartData,
    this.isLoading = false,
    this.chartPeriodLabel,
    this.onTap,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final color = metric.color(scheme);
    final subtitleText = chartPeriodLabel ?? metric.subtitle;
    final valueStyle = AppText.amount(context, size: featured ? 30 : 20);
    final delta = isLoading
        ? null
        : overviewRangeDelta(metric, chartData, filled: featured);
    final hasChart = chartData != null && chartData!.isNotEmpty;

    final Widget valueText;
    if (isLoading) {
      valueText = Container(
        height: featured ? 30 : 20,
        width: featured ? 120 : 72,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    } else if (metric.isCurrency && value is num) {
      valueText =
          DualCurrencyCompactText(
            amount: (value as num).toDouble(),
            style: valueStyle,
          ).appValueReveal(
            key: ValueKey('ov_${metric.name}_${value}_$subtitleText'),
          );
    } else {
      valueText =
          Text(
            metric.formatValue(value),
            style: valueStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ).appValueReveal(
            key: ValueKey(
              'ov_${metric.name}_${metric.formatValue(value)}_$subtitleText',
            ),
          );
    }

    final label = Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (featured && onTap != null)
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
      ],
    );

    final footer = hasChart
        ? OverviewSparklineChart(
            dataPoints: chartData!,
            lineColor: color,
            height: featured ? 72 : 34,
          )
        : Text(
            subtitleText,
            style: context.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    return AppCard(
      onTap: isLoading ? null : onTap,
      radius: featured ? AppRadius.card : AppRadius.tile,
      padding: EdgeInsets.fromLTRB(14, 12, 14, featured ? 12 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          SizedBox(height: featured ? 6 : 4),
          if (featured)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                valueText,
                if (delta != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      delta,
                      const SizedBox(width: 6),
                      Text(
                        'over this range',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(child: valueText),
                if (delta != null) ...[const SizedBox(width: 6), delta],
              ],
            ),
          if (featured) const SizedBox(height: 12) else const Spacer(),
          footer,
        ],
      ),
    );
  }
}
