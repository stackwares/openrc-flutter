import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class _PresetRanges {
  static DateTime _todayLocal() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
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

  /// Same span as the overview default (28 days back from today).
  static DateTimeRange last28Days() {
    final end = _todayLocal();
    final start = end.subtract(const Duration(days: 28));
    return DateTimeRange(start: start, end: end);
  }
}

/// Modal bottom sheet: quick presets plus custom range.
class HomeChartDateRangeSheet extends StatelessWidget {
  const HomeChartDateRangeSheet({
    super.key,
    required this.chartRangeStartUtc,
    required this.chartRangeEndUtc,
  });

  final DateTime chartRangeStartUtc;
  final DateTime chartRangeEndUtc;

  static Future<DateTimeRange?> show(
    BuildContext context, {
    required DateTime chartRangeStartUtc,
    required DateTime chartRangeEndUtc,
  }) {
    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => HomeChartDateRangeSheet(
        chartRangeStartUtc: chartRangeStartUtc,
        chartRangeEndUtc: chartRangeEndUtc,
      ),
    );
  }

  bool _matchesPreset(DateTimeRange preset) {
    final ps = DateTime.utc(
      preset.start.year,
      preset.start.month,
      preset.start.day,
    );
    final pe = DateTime.utc(
      preset.end.year,
      preset.end.month,
      preset.end.day,
    );
    return ps == chartRangeStartUtc && pe == chartRangeEndUtc;
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
        hint: 'Through today',
        range: _PresetRanges.last30Days(),
        icon: Icons.calendar_month_outlined,
      ),
      (
        title: 'Last 28 days',
        hint: 'Matches default overview window',
        range: _PresetRanges.last28Days(),
        icon: Icons.date_range_outlined,
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
                    start: chartRangeStartUtc.toLocal(),
                    end: chartRangeEndUtc.toLocal(),
                  ),
                ),
              ),
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: DateTimeRange(
                    start: chartRangeStartUtc.toLocal(),
                    end: chartRangeEndUtc.toLocal(),
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
