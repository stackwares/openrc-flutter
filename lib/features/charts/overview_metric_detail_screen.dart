import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/features/charts/home_notifier.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/features/charts/widgets/overview_detail_line_chart.dart';
import 'package:revenuecat/features/charts/widgets/overview_item_card.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/app_card.dart';
import 'package:revenuecat/widgets/dual_currency_text.dart';

class OverviewMetricDetailScreen extends ConsumerStatefulWidget {
  final OverviewMetricType metric;

  const OverviewMetricDetailScreen({super.key, required this.metric});

  @override
  ConsumerState<OverviewMetricDetailScreen> createState() =>
      _OverviewMetricDetailScreenState();
}

class _OverviewMetricDetailScreenState
    extends ConsumerState<OverviewMetricDetailScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    final d =
        ref.read(homeProvider.notifier).getChartData(widget.metric) ?? [];
    _selectedIndex = d.isEmpty ? 0 : d.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(commissionSettingsProvider);
    ref.listen<HomeState>(homeProvider, (prev, next) {
      final notifier = ref.read(homeProvider.notifier);
      final p = notifier.getChartData(widget.metric) ?? [];
      if (p.isEmpty) return;
      final prevChart = prev?.charts[widget.metric];
      final nextChart = next.charts[widget.metric];
      final dataChanged = prevChart != nextChart;
      final rangeChanged =
          prev?.chartRangeStart != next.chartRangeStart ||
              prev?.chartRangeEnd != next.chartRangeEnd;
      if (dataChanged || rangeChanged) {
        setState(() => _selectedIndex = p.length - 1);
      }
    });

    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);
    final points = notifier.getChartData(widget.metric) ?? [];
    final color = widget.metric.color(context.colorScheme);
    final rangeLabel = notifier.formatChartRangeLabel();

    final safeIdx =
        points.isEmpty ? 0 : _selectedIndex.clamp(0, points.length - 1);
    final selectedPoint = points.isEmpty ? null : points[safeIdx];
    final selectedDay = points.isEmpty || selectedPoint == null
        ? null
        : notifier.dateForChartDataPoint(selectedPoint, safeIdx);
    final dateStr = selectedDay == null
        ? ''
        : DateFormat.yMMMEd().format(selectedDay);

    final value = notifier.getValue(widget.metric);
    final delta = overviewRangeDelta(widget.metric, points, filled: true);
    final valueStyle = AppText.amount(context, size: 34);
    final selectedStyle = AppText.amount(context, size: 22);
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(widget.metric.label)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(rangeLabel, style: muted),
          const SizedBox(height: 6),
          if (state.isLoading && state.overview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            )
          else if (widget.metric.isCurrency && value is num)
            DualCurrencyCompactText(amount: value.toDouble(), style: valueStyle)
          else
            Text(widget.metric.formatValue(value), style: valueStyle),
          if (delta != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                delta,
                const SizedBox(width: 6),
                Text('over this range', style: muted),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (points.isEmpty)
            AppCard(
              child: Text(
                'No daily series for this metric in this range.',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr, style: muted),
                  const SizedBox(height: 2),
                  if (widget.metric.isCurrency && selectedPoint?.value != null)
                    DualCurrencyCompactText(
                      amount: selectedPoint!.value!,
                      style: selectedStyle,
                    )
                  else
                    Text(
                      widget.metric.formatValue(selectedPoint?.value),
                      style: selectedStyle,
                    ),
                  const SizedBox(height: 16),
                  OverviewDetailLineChart(
                    dataPoints: points,
                    lineColor: color,
                    metric: widget.metric,
                    rangeStart: state.chartRangeStart,
                    selectedIndex: safeIdx,
                    onIndexChanged: (i) {
                      setState(() => _selectedIndex = i);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text('Drag across the chart to see each day.', style: muted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
