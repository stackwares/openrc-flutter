import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:revenuecat/models/rc_chart_response.dart';

class OverviewSparklineChart extends StatelessWidget {
  final List<RcChartDataPoint> dataPoints;
  final Color lineColor;
  final double height;

  const OverviewSparklineChart({
    super.key,
    required this.dataPoints,
    required this.lineColor,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) return const SizedBox.shrink();

    if (dataPoints.length == 1) {
      final spot = FlSpot(0, dataPoints.first.value ?? 0);
      return SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            lineTouchData: const LineTouchData(enabled: false),
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            minX: -0.5,
            maxX: 0.5,
            minY: (spot.y) - 1,
            maxY: (spot.y) + 1,
            lineBarsData: [
              LineChartBarData(
                spots: [spot],
                isCurved: false,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, a, b, c) => FlDotCirclePainter(
                    radius: 3,
                    color: lineColor,
                    strokeWidth: 0,
                  ),
                ),
                belowBarData: BarAreaData(show: false),
                barWidth: 0,
              ),
            ],
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    double? minY;
    double? maxY;

    for (var i = 0; i < dataPoints.length; i++) {
      final v = dataPoints[i].value ?? 0;
      spots.add(FlSpot(i.toDouble(), v));
      if (minY == null || v < minY) minY = v;
      if (maxY == null || v > maxY) maxY = v;
    }

    final yRange = (maxY ?? 0) - (minY ?? 0);
    final padding = yRange == 0 ? 1.0 : yRange * 0.1;

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            lineTouchData: const LineTouchData(enabled: false),
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (spots.length - 1).toDouble(),
            minY: (minY ?? 0) - padding,
            maxY: (maxY ?? 0) + padding,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                preventCurveOverShooting: true,
                color: lineColor,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      lineColor.withValues(alpha: 0.22),
                      lineColor.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
