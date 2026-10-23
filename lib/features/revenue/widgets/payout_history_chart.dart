import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/animations/app_motion.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/services/display_currency_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/utilities_service.dart';

/// Payouts per month as bars stacked by store; tap a bar to pick its month.
class PayoutHistoryChart extends ConsumerWidget {
  const PayoutHistoryChart({
    super.key,
    required this.months,
    required this.stores,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// Oldest first.
  final List<PayoutMonth> months;

  /// Stores to stack, bottom first.
  final List<PayoutStore> stores;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _height = 200.0;
  static const _axisWidth = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colorScheme;
    final colors = context.appColors;
    final labelStyle = context.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 10,
    );

    // Gridlines fall on round amounts in the display currency, like every
    // amount around them; bars stay in USD.
    final currency = ref.watch(displayCurrencyProvider);
    final rate = currency == 'USD'
        ? null
        : ref.watch(usdExchangeRatesProvider).asData?.value[currency
              .toLowerCase()];
    final shown = rate == null || rate == 0 ? 'USD' : currency;
    final perUsd = shown == 'USD' ? 1.0 : rate!;

    Color colorFor(PayoutStore store) => switch (store) {
      PayoutStore.apple => colors.apple,
      PayoutStore.google => colors.google,
    };

    // Refunds can push a month below zero; bars start at zero.
    double stacked(PayoutMonth m) =>
        stores.fold(0.0, (sum, s) => sum + math.max(0.0, m.totalFor(s)));
    final peak = months.fold(0.0, (top, m) => math.max(top, stacked(m)));
    final shownStep = _niceStep(peak * perUsd / 3);
    final step = shownStep / perUsd;
    var maxY = peak <= 0 ? step : (peak / step).ceil() * step;
    if (peak > maxY * 0.92) maxY += step;
    String axisLabel(double usd) => _axisAmount(
      (usd * perUsd / shownStep).round() * shownStep,
      currencySymbolFor(shown),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = (constraints.maxWidth - _axisWidth) / months.length;
        final barWidth = (slot * 0.56).clamp(6.0, 22.0);
        // Narrow windows get one-letter months.
        final monthFormat = slot < 30 ? DateFormat('MMMMM') : DateFormat.MMM();

        BarChartGroupData group(int i) {
          final selected = i == selectedIndex;
          final items = <BarChartRodStackItem>[];
          var top = 0.0;
          for (final store in stores) {
            final v = math.max(0.0, months[i].totalFor(store));
            if (v <= 0) continue;
            final color = colorFor(store);
            items.add(
              BarChartRodStackItem(
                top,
                top + v,
                selected ? color : color.withValues(alpha: 0.5),
              ),
            );
            top += v;
          }
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: top,
                width: barWidth,
                color: Colors.transparent,
                rodStackItems: items,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(math.min(4, barWidth / 2)),
                ),
                // A full-height track so a tap anywhere in the column counts.
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: selected
                      ? scheme.onSurface.withValues(alpha: 0.06)
                      : Colors.transparent,
                ),
              ),
            ],
          );
        }

        return RepaintBoundary(
          child: SizedBox(
            height: _height,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  handleBuiltInTouches: false,
                  allowTouchBarBackDraw: true,
                  touchExtraThreshold: EdgeInsets.symmetric(
                    horizontal: slot / 4,
                  ),
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions) return;
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (i == null || i == selectedIndex) return;
                    UtilitiesService.hapticSelection();
                    onSelected(i);
                  },
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _axisWidth,
                      interval: step,
                      getTitlesWidget: (value, meta) {
                        if (value <= 0 || value > meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          axisLabel(value),
                          style: labelStyle,
                          maxLines: 1,
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= months.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            monthFormat.format(months[i].month),
                            style: i == selectedIndex
                                ? labelStyle?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  )
                                : labelStyle,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [for (var i = 0; i < months.length; i++) group(i)],
              ),
              duration: AppMotion.of(context, AppMotion.duration),
              curve: AppMotion.curve,
            ),
          ),
        );
      },
    );
  }
}

/// A round axis amount, short: `₱600K`, `$1.5M`, `€40`.
String _axisAmount(double v, String symbol) {
  String digits(double x) =>
      x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
  String scaled(double x, String suffixKey) {
    final suffix = suffixKey.tr();
    return '$symbol${digits(x)}${suffix.length > 1 ? ' ' : ''}$suffix';
  }

  if (v >= 1e6) return scaled(v / 1e6, 'common.suffixMillion');
  if (v >= 1e3) return scaled(v / 1e3, 'common.suffixThousand');
  return '$symbol${digits(v)}';
}

/// 1, 2 or 5 times a power of ten, at least [raw]: round gridline steps.
double _niceStep(double raw) {
  if (raw <= 0) return 1;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final f = raw / magnitude;
  final nice = f <= 1
      ? 1
      : f <= 2
      ? 2
      : f <= 5
      ? 5
      : 10;
  return nice * magnitude;
}
