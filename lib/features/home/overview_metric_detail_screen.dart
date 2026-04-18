import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/shell_insets.dart';
import 'package:revenuecat/features/home/home_notifier.dart';
import 'package:revenuecat/services/commission_settings_store.dart';
import 'package:revenuecat/features/home/widgets/overview_detail_line_chart.dart';
import 'package:revenuecat/models/overview_metric_type.dart';
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
    final selectedDay = points.isEmpty
        ? null
        : notifier.dateForChartPoint(safeIdx);
    final dateStr = selectedDay == null
        ? ''
        : DateFormat.yMMMEd().format(selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.metric.label),
            Text(
              rangeLabel,
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + mainShellFloatingTabBarScrollPadding(context),
        ),
        children: [
          Text(
            'Summary',
            style: context.textTheme.labelMedium?.copyWith(
              color: context.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (state.isLoading && state.overview == null)
            const LinearProgressIndicator()
          else if (widget.metric.isCurrency &&
              notifier.getValue(widget.metric) is num)
            DualCurrencyCompactText(
              amount: (notifier.getValue(widget.metric) as num).toDouble(),
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            )
          else
            Text(
              widget.metric.formatValue(notifier.getValue(widget.metric)),
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 28),
          Text(
            'Daily trend',
            style: context.textTheme.labelMedium?.copyWith(
              color: context.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No daily series for this metric in this range.',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
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
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected day',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Value',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (widget.metric.isCurrency &&
                        selectedPoint?.value != null)
                      DualCurrencyCompactText(
                        amount: selectedPoint!.value!,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        widget.metric.formatValue(selectedPoint?.value),
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
