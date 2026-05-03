import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class _PresetRanges {
  static DateTime _todayLocal() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// [MaterialLocalizations.firstDayOfWeekIndex]: 0 = Sunday … 6 = Saturday.
  static int _dartWeekdayFromMaterialFirstDay(int materialFirstDayIndex) {
    if (materialFirstDayIndex == 0) return DateTime.sunday;
    return materialFirstDayIndex;
  }

  /// First calendar day of the week that contains [day] (locale week start).
  static DateTime _startOfWeekContaining(
    DateTime day,
    int materialFirstDayIndex,
  ) {
    final d = DateTime(day.year, day.month, day.day);
    final firstWd = _dartWeekdayFromMaterialFirstDay(materialFirstDayIndex);
    var delta = d.weekday - firstWd;
    if (delta < 0) delta += 7;
    return d.subtract(Duration(days: delta));
  }

  /// Start of locale week through today (inclusive).
  static DateTimeRange thisWeek(int materialFirstDayIndex) {
    final end = _todayLocal();
    final start = _startOfWeekContaining(end, materialFirstDayIndex);
    return DateTimeRange(start: start, end: end);
  }

  /// First day of month through today (inclusive).
  static DateTimeRange thisMonth() {
    final end = _todayLocal();
    final start = DateTime(end.year, end.month, 1);
    return DateTimeRange(start: start, end: end);
  }

  /// January 1 through today (inclusive).
  static DateTimeRange thisYear() {
    final end = _todayLocal();
    final start = DateTime(end.year, 1, 1);
    return DateTimeRange(start: start, end: end);
  }

  /// Trailing 7 days ending today (inclusive).
  static DateTimeRange last7Days() {
    final end = _todayLocal();
    final start = end.subtract(const Duration(days: 6));
    return DateTimeRange(start: start, end: end);
  }

  /// Trailing 30 days ending today (inclusive).
  static DateTimeRange last30Days() {
    final end = _todayLocal();
    final start = end.subtract(const Duration(days: 29));
    return DateTimeRange(start: start, end: end);
  }

}

/// Modal bottom sheet: quick presets plus custom range.
class HomeChartDateRangeSheet extends StatelessWidget {
  const HomeChartDateRangeSheet({
    super.key,
    required this.chartRangeStart,
    required this.chartRangeEnd,
  });

  /// Inclusive range using **local** calendar dates (midnight local).
  final DateTime chartRangeStart;
  final DateTime chartRangeEnd;

  static Future<DateTimeRange?> show(
    BuildContext context, {
    required DateTime chartRangeStart,
    required DateTime chartRangeEnd,
  }) {
    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => HomeChartDateRangeSheet(
        chartRangeStart: chartRangeStart,
        chartRangeEnd: chartRangeEnd,
      ),
    );
  }

  bool _matchesPreset(DateTimeRange preset) {
    DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

    final ps = dateOnly(preset.start);
    final pe = dateOnly(preset.end);
    final cs = dateOnly(chartRangeStart);
    final ce = dateOnly(chartRangeEnd);
    return ps == cs && pe == ce;
  }

  String _formatRange(DateTimeRange r) {
    final a = r.start;
    final b = r.end;
    final ymd = DateFormat.yMMMd();
    if (a.year == b.year) {
      return '${DateFormat.MMMd().format(a)} – ${ymd.format(b)}';
    }
    return '${ymd.format(a)} – ${ymd.format(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weekStarts =
        MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final presets = <({
      String title,
      String hint,
      DateTimeRange range,
      IconData icon,
    })>[
      (
        title: 'Last 7 days',
        hint: 'Through today',
        range: _PresetRanges.last7Days(),
        icon: Icons.view_week_outlined,
      ),
      (
        title: 'Last 30 days',
        hint: 'Through today · default',
        range: _PresetRanges.last30Days(),
        icon: Icons.calendar_month_outlined,
      ),
      (
        title: 'This week',
        hint: 'Start of week through today',
        range: _PresetRanges.thisWeek(weekStarts),
        icon: Icons.today_outlined,
      ),
      (
        title: 'This month',
        hint: 'Month to date',
        range: _PresetRanges.thisMonth(),
        icon: Icons.calendar_view_month_outlined,
      ),
      (
        title: 'This year',
        hint: 'Year to date',
        range: _PresetRanges.thisYear(),
        icon: Icons.event_note_outlined,
      ),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                'Chart date range',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final p in presets)
              ListTile(
                leading: Icon(p.icon),
                title: Text(p.title),
                subtitle: Text(
                  '${p.hint}\n${_formatRange(p.range)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                isThreeLine: true,
                trailing: _matchesPreset(p.range)
                    ? Icon(Icons.check_circle, color: scheme.primary, size: 22)
                    : null,
                onTap: () => Navigator.pop(context, p.range),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Custom range'),
              subtitle: Text(
                _formatRange(
                  DateTimeRange(
                    start: chartRangeStart,
                    end: chartRangeEnd,
                  ),
                ),
              ),
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: DateTimeRange(
                    start: chartRangeStart,
                    end: chartRangeEnd,
                  ),
                  firstDate: DateTime(2019, 1, 1),
                  lastDate: DateTime.now(),
                  helpText: 'Charts & period metrics',
                );
                if (picked != null && context.mounted) {
                  Navigator.pop(context, picked);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
