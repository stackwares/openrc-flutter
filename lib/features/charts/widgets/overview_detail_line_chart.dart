import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openrc/models/overview_metric_type.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/services/utilities_service.dart';

/// Larger interactive line chart for overview metric detail (daily buckets).
class OverviewDetailLineChart extends StatelessWidget {
  final List<RcChartDataPoint> dataPoints;
  final Color lineColor;
  final OverviewMetricType metric;
  /// First day of the chart range (local calendar midnight).
  final DateTime rangeStart;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;

  const OverviewDetailLineChart({
    super.key,
    required this.dataPoints,
    required this.lineColor,
    required this.metric,
    required this.rangeStart,
    required this.selectedIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    double? minY;
    double? maxY;

    for (var i = 0; i < dataPoints.length; i++) {
      final v = dataPoints[i].value ?? 0;
      spots.add(FlSpot(i.toDouble(), v));
      minY = minY == null || v < minY ? v : minY;
      maxY = maxY == null || v > maxY ? v : maxY;
    }

    final yRange = (maxY ?? 0) - (minY ?? 0);
    final padding = yRange == 0 ? 1.0 : yRange * 0.12;
    final maxX = (spots.length - 1).toDouble();
    final safeSelected = selectedIndex.clamp(0, spots.length - 1);

    final dateFmt = DateFormat.MMMd();
    final labelInterval = spots.length <= 1
        ? 1
        : spots.length <= 7
            ? 1
            : (spots.length / 5).ceil().clamp(1, spots.length - 1);

    return RepaintBoundary(
      child: SizedBox(
        height: 260,
        child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (event, touchResponse) {
              if (!event.isInterestedForInteractions) return;
              final spotsTouch = touchResponse?.lineBarSpots;
              if (spotsTouch == null || spotsTouch.isEmpty) return;
              final idx = spotsTouch.first.spotIndex.clamp(0, dataPoints.length - 1);
              if (idx != selectedIndex) {
                UtilitiesService.hapticSelection();
                onIndexChanged(idx);
              }
            },
            getTouchedSpotIndicator: (barData, spotIndexes) {
              return spotIndexes.map((index) {
                return TouchedSpotIndicatorData(
                  FlLine(color: lineColor.withValues(alpha: 0.6), strokeWidth: 1.5),
                  FlDotData(
                    getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                      radius: 5,
                      color: lineColor,
                      strokeWidth: 2,
                      strokeColor: scheme.surfaceContainerLow,
                    ),
                  ),
                );
              }).toList();
            },
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yRange > 0 ? null : 1,
            getDrawingHorizontalLine: (v) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) {
                  if (value < meta.min || value > meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    metric.isPercentage
                        ? '${value.toStringAsFixed(0)}%'
                        : (value >= 1000
                            ? '${(value / 1000).toStringAsFixed(1)}k'
                            : value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: labelInterval.toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= dataPoints.length) {
                    return const SizedBox.shrink();
                  }
                  if (i % labelInterval != 0 && i != dataPoints.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final d = rangeStart.add(Duration(days: i));
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      dateFmt.format(d),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          minX: 0,
          maxX: maxX,
          minY: (minY ?? 0) - padding,
          maxY: (maxY ?? 0) + padding,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              preventCurveOverShooting: true,
              color: lineColor,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  final isSel = index == safeSelected;
                  return FlDotCirclePainter(
                    radius: isSel ? 5 : 0,
                    color: lineColor,
                    strokeWidth: 2,
                    strokeColor: scheme.surfaceContainerLow,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.22),
                    lineColor.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    ),
  );
}
}
