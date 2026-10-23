import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';

class DayRevenueStripDay {
  const DayRevenueStripDay({
    required this.dayKey,
    required this.date,
    required this.total,
  });

  /// `yyyy-MM-dd`.
  final String dayKey;
  final DateTime date;

  /// Net revenue for the day; null while that day isn't fully loaded yet.
  final double? total;
}

/// Small bar chart of daily revenue (oldest → newest). The selected day is
/// drawn in the accent color; tapping a bar selects that day.
class DayRevenueStrip extends StatelessWidget {
  const DayRevenueStrip({
    super.key,
    required this.days,
    required this.selectedDayKey,
    required this.formatAmount,
    this.onDaySelected,
    this.barAreaHeight = 44,
  });

  final List<DayRevenueStripDay> days;
  final String selectedDayKey;

  /// Formats a total for the accessibility label.
  final String Function(double amount) formatAmount;
  final ValueChanged<String>? onDaySelected;
  final double barAreaHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final maxTotal = days
        .map((d) => d.total ?? 0)
        .fold<double>(0, (m, v) => v > m ? v : m);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final weekday = DateFormat('EEEEE');
    final longDate = DateFormat('EEE, MMM d');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              button: onDaySelected != null,
              selected: d.dayKey == selectedDayKey,
              label: d.total == null
                  ? '${longDate.format(d.date)}: not loaded yet'
                  : '${longDate.format(d.date)}: ${formatAmount(d.total!)}',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('day_strip_${d.dayKey}'),
                borderRadius: BorderRadius.circular(8),
                onTap: onDaySelected == null || d.dayKey == selectedDayKey
                    ? null
                    : () => onDaySelected!(d.dayKey),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: barAreaHeight,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            height: _barHeight(d.total, maxTotal),
                            decoration: BoxDecoration(
                              color: _barColor(context, d),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        weekday.format(d.date),
                        style: context.textTheme.labelSmall?.copyWith(
                          color: d.dayKey == selectedDayKey
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant.withValues(
                                  alpha: d.total == null ? 0.5 : 1,
                                ),
                          fontWeight: d.dayKey == selectedDayKey
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  double _barHeight(double? total, double maxTotal) {
    const minimum = 4.0;
    if (total == null || maxTotal <= 0 || total <= 0) return minimum;
    return (total / maxTotal * barAreaHeight).clamp(minimum, barAreaHeight);
  }

  Color _barColor(BuildContext context, DayRevenueStripDay d) {
    final scheme = context.colorScheme;
    if (d.dayKey == selectedDayKey) return scheme.primary;
    if (d.total == null) return context.appColors.hairline;
    return scheme.onSurfaceVariant.withValues(alpha: 0.32);
  }
}
