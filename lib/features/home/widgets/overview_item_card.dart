import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/home/widgets/overview_sparkline_chart.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
import 'package:revenuecat/models/rc_chart_response.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

class OverviewItemCard extends ConsumerWidget {
  final OverviewMetricType metric;
  final dynamic value;
  final List<RcChartDataPoint>? chartData;
  final bool isLoading;

  /// Replaces [OverviewMetricType.subtitle] when set (e.g. selected chart date range).
  final String? chartPeriodLabel;

  final VoidCallback? onTap;

  const OverviewItemCard({
    super.key,
    required this.metric,
    this.value,
    this.chartData,
    this.isLoading = false,
    this.chartPeriodLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final color = metric.color(scheme);
    final subtitleText = chartPeriodLabel ?? metric.subtitle;
    final cardSurface =
        Color.lerp(scheme.surface, color, 0.07) ?? scheme.surface;

    return Card(
      margin: const EdgeInsets.all(4),
      color: cardSurface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(metric.icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    metric.label,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (isLoading)
              _buildShimmerValue(context)
            else if (metric.isCurrency && value is num)
              DualCurrencyCompactText(
                amount: (value as num).toDouble(),
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ).appValueReveal(
                key: ValueKey('ov_${metric.name}_${value}_$subtitleText'),
              )
            else
              Text(
                metric.formatValue(value),
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).appValueReveal(
                key: ValueKey(
                  'ov_${metric.name}_${metric.formatValue(value)}_$subtitleText',
                ),
              ),
            const SizedBox(height: 4),
            if (chartData != null && chartData!.isNotEmpty)
              OverviewSparklineChart(
                dataPoints: chartData!,
                lineColor: color,
              )
            else if (subtitleText.isNotEmpty)
              Text(
                subtitleText,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildShimmerValue(BuildContext context) {
    return Container(
      height: 20,
      width: 80,
      decoration: BoxDecoration(
        color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
