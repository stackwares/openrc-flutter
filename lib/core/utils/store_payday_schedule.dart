import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:easy_localization/easy_localization.dart';

/// Apple App Store fiscal-month payout schedule (same data as [Kedi](https://github.com/sereisoglu/Kedi)).
class AppStorePayday {
  AppStorePayday({
    required this.fiscalYear,
    required this.fiscalMonthStart,
    required this.startDate,
    required this.endDate,
    required this.paymentDate,
    this.isProjected = false,
  });

  final int fiscalYear;
  final DateTime fiscalMonthStart;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime paymentDate;

  /// Computed from Apple's fiscal rules rather than a published calendar.
  final bool isProjected;

  /// Published calendar, then projected fiscal years after it so the next
  /// payout is never missing when the table runs out.
  static final List<AppStorePayday> _all = () {
    final published = _parseEmbedded();
    final lastYear = published.last.fiscalYear;
    return [
      ...published,
      for (var fy = lastYear + 1; fy <= lastYear + 5; fy++)
        ...projectFiscalYear(fy),
    ];
  }();

  static List<AppStorePayday> get all => List.unmodifiable(_all);

  /// Rows from the published calendar only.
  @visibleForTesting
  static List<AppStorePayday> get published =>
      _all.where((p) => !p.isProjected).toList();

  static AppStorePayday? get upcoming => upcomingOn(DateTime.now());

  /// First payout on or after [now]'s calendar day.
  static AppStorePayday? upcomingOn(DateTime now) {
    for (final p in _all) {
      if (_isSameCalendarDay(p.paymentDate, now) ||
          p.paymentDate.isAfter(_startOfDay(now))) {
        return p;
      }
    }
    return null;
  }

  /// Last Saturday of September of [fiscalYear]: Apple's fiscal year end.
  static DateTime fiscalYearEnd(int fiscalYear) {
    var d = DateTime(fiscalYear, 9, 30);
    while (d.weekday != DateTime.saturday) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return d;
  }

  /// One fiscal year of payout periods from Apple's rules: quarters of 5, 4
  /// and 4 weeks (a 53-week year adds a week to December), paid 33 days
  /// after each period closes. Matches every published row in the table.
  static List<AppStorePayday> projectFiscalYear(int fiscalYear) {
    final start = _addDays(fiscalYearEnd(fiscalYear - 1), 1);
    final end = fiscalYearEnd(fiscalYear);
    final weeks = (end.difference(start).inDays + 1) ~/ 7;
    final pattern = [5, 4, 4, 5, 4, 4, 5, 4, 4, 5, 4, 4];
    if (weeks == 53) pattern[2] = 5;
    final out = <AppStorePayday>[];
    var periodStart = start;
    for (var i = 0; i < pattern.length; i++) {
      final periodEnd = _addDays(periodStart, pattern[i] * 7 - 1);
      out.add(
        AppStorePayday(
          fiscalYear: fiscalYear,
          fiscalMonthStart: DateTime(fiscalYear - 1, 10 + i, 1),
          startDate: periodStart,
          endDate: periodEnd,
          paymentDate: _addDays(periodEnd, 33),
          isProjected: true,
        ),
      );
      periodStart = _addDays(periodEnd, 1);
    }
    return out;
  }

  PaydayProximityState proximityState(DateTime now) {
    if (_isSameCalendarDay(paymentDate, now)) return PaydayProximityState.today;
    if (_isTomorrow(paymentDate, now)) return PaydayProximityState.tomorrow;
    final u = upcoming;
    if (u != null && _isSameCalendarDay(paymentDate, u.paymentDate)) {
      return PaydayProximityState.upcoming;
    }
    final ps = DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
    final t = DateTime(now.year, now.month, now.day);
    if (ps.isAfter(t)) return PaydayProximityState.future;
    return PaydayProximityState.past;
  }

  static List<AppStorePayday> groupedYearDescending(int fiscalYear) =>
      _all.where((e) => e.fiscalYear == fiscalYear).toList();

  static List<int> get fiscalYearsDescending {
    final y = _all.map((e) => e.fiscalYear).toSet().toList()..sort((a, b) => b.compareTo(a));
    return y;
  }
}

/// Google Play: prior calendar month’s earnings are typically initiated around the 15th of the
/// next month; weekends roll forward (see
/// [Play Console Help](https://support.google.com/googleplay/android-developer/answer/137997)).
class GooglePlayPayday {
  GooglePlayPayday({
    required this.earningsYear,
    required this.earningsMonth,
    required this.earningsStart,
    required this.earningsEnd,
    required this.paymentDate,
  });

  final int earningsYear;
  final int earningsMonth;
  final DateTime earningsStart;
  final DateTime earningsEnd;
  final DateTime paymentDate;

  /// The payout for one month of earnings; months past 12 roll into the
  /// next year.
  factory GooglePlayPayday.forEarningsMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    return GooglePlayPayday(
      earningsYear: start.year,
      earningsMonth: start.month,
      earningsStart: start,
      earningsEnd: DateTime(start.year, start.month + 1, 0),
      paymentDate: _paymentDateForPriorEarningsMonth(start.year, start.month),
    );
  }

  static List<GooglePlayPayday> _range({
    required int startYear,
    required int startMonth,
    required int months,
  }) {
    final out = <GooglePlayPayday>[];
    var y = startYear;
    var m = startMonth;
    for (var i = 0; i < months; i++) {
      final start = DateTime(y, m, 1);
      final end = DateTime(y, m + 1, 0);
      final pay = _paymentDateForPriorEarningsMonth(y, m);
      out.add(
        GooglePlayPayday(
          earningsYear: y,
          earningsMonth: m,
          earningsStart: start,
          earningsEnd: end,
          paymentDate: pay,
        ),
      );
      if (m == 12) {
        m = 1;
        y++;
      } else {
        m++;
      }
    }
    return out;
  }

  static List<GooglePlayPayday> get all {
    final now = DateTime.now();
    final startY = now.year - 1;
    final startM = 1;
    return _range(startYear: startY, startMonth: startM, months: 36);
  }

  static GooglePlayPayday? get upcoming {
    final now = DateTime.now();
    for (final p in all) {
      if (_isSameCalendarDay(p.paymentDate, now) ||
          p.paymentDate.isAfter(_startOfDay(now))) {
        return p;
      }
    }
    return null;
  }

  PaydayProximityState proximityState(DateTime now) {
    if (_isSameCalendarDay(paymentDate, now)) return PaydayProximityState.today;
    if (_isTomorrow(paymentDate, now)) return PaydayProximityState.tomorrow;
    final u = upcoming;
    if (u != null && _isSameCalendarDay(paymentDate, u.paymentDate)) {
      return PaydayProximityState.upcoming;
    }
    final ps = DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
    final t = DateTime(now.year, now.month, now.day);
    if (ps.isAfter(t)) return PaydayProximityState.future;
    return PaydayProximityState.past;
  }

  static Map<int, List<GooglePlayPayday>> byEarningsYear(List<GooglePlayPayday> list) {
    final map = <int, List<GooglePlayPayday>>{};
    for (final p in list) {
      map.putIfAbsent(p.earningsYear, () => []).add(p);
    }
    for (final e in map.entries) {
      e.value.sort((a, b) => a.paymentDate.compareTo(b.paymentDate));
    }
    return map;
  }
}

enum PaydayProximityState {
  today,
  tomorrow,
  upcoming,
  future,
  past;

  String get title => switch (this) {
        PaydayProximityState.today => 'revenue.payday.today'.tr(),
        PaydayProximityState.tomorrow => 'revenue.payday.tomorrow'.tr(),
        PaydayProximityState.upcoming => 'revenue.payday.upcoming'.tr(),
        PaydayProximityState.future => 'revenue.payday.future'.tr(),
        PaydayProximityState.past => 'revenue.payday.past'.tr(),
      };

  String get emoji => switch (this) {
        PaydayProximityState.today => '🤑',
        PaydayProximityState.tomorrow => '🔥',
        PaydayProximityState.upcoming => '⏳',
        PaydayProximityState.future => '☑️',
        PaydayProximityState.past => '✅',
      };
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic that stays at midnight across DST changes.
DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

bool _isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isTomorrow(DateTime payment, DateTime now) {
  final t = _startOfDay(now).add(const Duration(days: 1));
  return _isSameCalendarDay(payment, t);
}

/// Next business day on or after [year]-[month]-[day] (weekends only).
DateTime _firstBusinessDayOnOrAfter(int year, int month, int day) {
  var d = DateTime(year, month, day);
  while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return DateTime(d.year, d.month, d.day);
}

DateTime _paymentDateForPriorEarningsMonth(int earningsYear, int earningsMonth) {
  final payMonth = earningsMonth == 12 ? 1 : earningsMonth + 1;
  final payYear = earningsMonth == 12 ? earningsYear + 1 : earningsYear;
  return _firstBusinessDayOnOrAfter(payYear, payMonth, 15);
}

List<AppStorePayday> _parseEmbedded() {
  const jsonStr = '''
[
  {"fiscalYear":2024,"fiscalMonth":"2023-10","startDate":"2023-10-01","endDate":"2023-11-04","paymentDate":"2023-12-07"},
  {"fiscalYear":2024,"fiscalMonth":"2023-11","startDate":"2023-11-05","endDate":"2023-12-02","paymentDate":"2024-01-04"},
  {"fiscalYear":2024,"fiscalMonth":"2023-12","startDate":"2023-12-03","endDate":"2023-12-30","paymentDate":"2024-02-01"},
  {"fiscalYear":2024,"fiscalMonth":"2024-01","startDate":"2023-12-31","endDate":"2024-02-03","paymentDate":"2024-03-07"},
  {"fiscalYear":2024,"fiscalMonth":"2024-02","startDate":"2024-02-04","endDate":"2024-03-02","paymentDate":"2024-04-04"},
  {"fiscalYear":2024,"fiscalMonth":"2024-03","startDate":"2024-03-03","endDate":"2024-03-30","paymentDate":"2024-05-02"},
  {"fiscalYear":2024,"fiscalMonth":"2024-04","startDate":"2024-03-31","endDate":"2024-05-04","paymentDate":"2024-06-06"},
  {"fiscalYear":2024,"fiscalMonth":"2024-05","startDate":"2024-05-05","endDate":"2024-06-01","paymentDate":"2024-07-04"},
  {"fiscalYear":2024,"fiscalMonth":"2024-06","startDate":"2024-06-02","endDate":"2024-06-29","paymentDate":"2024-08-01"},
  {"fiscalYear":2024,"fiscalMonth":"2024-07","startDate":"2024-06-30","endDate":"2024-08-03","paymentDate":"2024-09-05"},
  {"fiscalYear":2024,"fiscalMonth":"2024-08","startDate":"2024-08-04","endDate":"2024-08-31","paymentDate":"2024-10-03"},
  {"fiscalYear":2024,"fiscalMonth":"2024-09","startDate":"2024-09-01","endDate":"2024-09-28","paymentDate":"2024-10-31"},
  {"fiscalYear":2025,"fiscalMonth":"2024-10","startDate":"2024-09-29","endDate":"2024-11-02","paymentDate":"2024-12-05"},
  {"fiscalYear":2025,"fiscalMonth":"2024-11","startDate":"2024-11-03","endDate":"2024-11-30","paymentDate":"2025-01-02"},
  {"fiscalYear":2025,"fiscalMonth":"2024-12","startDate":"2024-12-01","endDate":"2024-12-28","paymentDate":"2025-01-30"},
  {"fiscalYear":2025,"fiscalMonth":"2025-01","startDate":"2024-12-29","endDate":"2025-02-01","paymentDate":"2025-03-06"},
  {"fiscalYear":2025,"fiscalMonth":"2025-02","startDate":"2025-02-02","endDate":"2025-03-01","paymentDate":"2025-04-03"},
  {"fiscalYear":2025,"fiscalMonth":"2025-03","startDate":"2025-03-02","endDate":"2025-03-29","paymentDate":"2025-05-01"},
  {"fiscalYear":2025,"fiscalMonth":"2025-04","startDate":"2025-03-30","endDate":"2025-05-03","paymentDate":"2025-06-05"},
  {"fiscalYear":2025,"fiscalMonth":"2025-05","startDate":"2025-05-04","endDate":"2025-05-31","paymentDate":"2025-07-03"},
  {"fiscalYear":2025,"fiscalMonth":"2025-06","startDate":"2025-06-01","endDate":"2025-06-28","paymentDate":"2025-07-31"},
  {"fiscalYear":2025,"fiscalMonth":"2025-07","startDate":"2025-06-29","endDate":"2025-08-02","paymentDate":"2025-09-04"},
  {"fiscalYear":2025,"fiscalMonth":"2025-08","startDate":"2025-08-03","endDate":"2025-08-30","paymentDate":"2025-10-02"},
  {"fiscalYear":2025,"fiscalMonth":"2025-09","startDate":"2025-08-31","endDate":"2025-09-27","paymentDate":"2025-10-30"},
  {"fiscalYear":2026,"fiscalMonth":"2025-10","startDate":"2025-09-28","endDate":"2025-11-01","paymentDate":"2025-12-04"},
  {"fiscalYear":2026,"fiscalMonth":"2025-11","startDate":"2025-11-02","endDate":"2025-11-29","paymentDate":"2026-01-01"},
  {"fiscalYear":2026,"fiscalMonth":"2025-12","startDate":"2025-11-30","endDate":"2025-12-27","paymentDate":"2026-01-29"},
  {"fiscalYear":2026,"fiscalMonth":"2026-01","startDate":"2025-12-28","endDate":"2026-01-31","paymentDate":"2026-03-05"},
  {"fiscalYear":2026,"fiscalMonth":"2026-02","startDate":"2026-02-01","endDate":"2026-02-28","paymentDate":"2026-04-02"},
  {"fiscalYear":2026,"fiscalMonth":"2026-03","startDate":"2026-03-01","endDate":"2026-03-28","paymentDate":"2026-04-30"},
  {"fiscalYear":2026,"fiscalMonth":"2026-04","startDate":"2026-03-29","endDate":"2026-05-02","paymentDate":"2026-06-04"},
  {"fiscalYear":2026,"fiscalMonth":"2026-05","startDate":"2026-05-03","endDate":"2026-05-30","paymentDate":"2026-07-02"},
  {"fiscalYear":2026,"fiscalMonth":"2026-06","startDate":"2026-05-31","endDate":"2026-06-27","paymentDate":"2026-07-30"},
  {"fiscalYear":2026,"fiscalMonth":"2026-07","startDate":"2026-06-28","endDate":"2026-08-01","paymentDate":"2026-09-03"},
  {"fiscalYear":2026,"fiscalMonth":"2026-08","startDate":"2026-08-02","endDate":"2026-08-29","paymentDate":"2026-10-01"},
  {"fiscalYear":2026,"fiscalMonth":"2026-09","startDate":"2026-08-30","endDate":"2026-09-26","paymentDate":"2026-10-29"}
]
''';
  final raw = jsonDecode(jsonStr) as List<dynamic>;
  final out = <AppStorePayday>[];
  for (final e in raw) {
    final m = e as Map<String, dynamic>;
    final fm = m['fiscalMonth'] as String;
    final fy = m['fiscalYear'] as int;
    final fmParts = fm.split('-');
    final fiscalMonthStart = DateTime(
      int.parse(fmParts[0]),
      int.parse(fmParts[1]),
      1,
    );
    out.add(
      AppStorePayday(
        fiscalYear: fy,
        fiscalMonthStart: fiscalMonthStart,
        startDate: _parseYmd(m['startDate'] as String),
        endDate: _parseYmd(m['endDate'] as String),
        paymentDate: _parseYmd(m['paymentDate'] as String),
      ),
    );
  }
  return out;
}

DateTime _parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

final _abbrevDate = DateFormat.yMMMd();

String formatPaydayAbbrev(DateTime d) => _abbrevDate.format(d);

String formatPaydayMonthYear(DateTime d) => DateFormat.yMMMM().format(d);

/// An earnings period, short: `Aug 2–Aug 29`.
String formatPaydayRange(DateTime start, DateTime end) {
  final f = DateFormat.MMMd();
  return '${f.format(start)}–${f.format(end)}';
}

String paydayRelativeLine(DateTime paymentDate, DateTime now) {
  if (_isSameCalendarDay(paymentDate, now)) return 'revenue.payday.today'.tr();
  if (_isTomorrow(paymentDate, now)) return 'revenue.payday.tomorrow'.tr();
  final t = DateTime(now.year, now.month, now.day);
  final p = DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
  final days = p.difference(t).inDays;
  if (days > 1) return 'revenue.payday.inDays'.plural(days);
  return formatPaydayAbbrev(paymentDate);
}

/// Local-calendar days from [now] to [paymentDate] (midnight to midnight).
int paydayCalendarDaysUntil(DateTime paymentDate, DateTime now) {
  final t = DateTime(now.year, now.month, now.day);
  final p = DateTime(paymentDate.year, paymentDate.month, paymentDate.day);
  return p.difference(t).inDays;
}

/// Short label for countdown UIs (e.g. settings payout preview).
String paydayDaysToGoLabel(DateTime paymentDate, DateTime now) {
  final d = paydayCalendarDaysUntil(paymentDate, now);
  if (d < 0) return 'revenue.payday.pastDate'.tr();
  if (d == 0) return 'revenue.payday.today'.tr();
  return 'revenue.payday.daysToGo'.plural(d);
}
