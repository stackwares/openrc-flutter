import 'package:easy_localization/easy_localization.dart';

/// Local time for list rows. Past days: `8:54AM`. Today / future (scheduled):
/// `Today · …`, `Tomorrow · …`, `In 2 days · …`, or short `In 45m` — aligned with
/// [Kedi](https://github.com/sereisoglu/Kedi) (`isToday || isFuture` → relative).
String formatTransactionListTime(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '—';
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return dateStr;
  final local = dt.toLocal();
  final now = DateTime.now();
  if (_isSameLocalDayOrFuture(local, now)) {
    return _formatTransactionListTimeUpcomingStyle(local, now);
  }
  return _formatTime12(local);
}

bool _isSameLocalDayOrFuture(DateTime local, DateTime now) {
  final t0 = DateTime(now.year, now.month, now.day);
  final d = DateTime(local.year, local.month, local.day);
  return !d.isBefore(t0);
}

String _formatTransactionListTimeUpcomingStyle(DateTime local, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = _formatTime12(local);
  if (day.isAfter(today)) {
    final days = day.difference(today).inDays;
    if (days == 1) return 'time.tomorrow'.tr(namedArgs: {'time': time});
    if (days < 7) return 'time.inDays'.plural(days, namedArgs: {'time': time});
    return 'time.dateAndTime'.tr(
      namedArgs: {'date': DateFormat.MMMd().format(local), 'time': time},
    );
  }
  if (local.isAfter(now)) {
    final until = local.difference(now);
    if (until.inMinutes < 1) return 'time.soon'.tr();
    if (until.inMinutes < 60) {
      return 'time.inMinutesShort'.tr(
        namedArgs: {'count': '${until.inMinutes}'},
      );
    }
    if (until.inHours < 24) {
      return 'time.inHoursShort'.tr(namedArgs: {'count': '${until.inHours}'});
    }
  }
  return 'time.todayAt'.tr(namedArgs: {'time': time});
}

String _formatTime12(DateTime local) {
  // Other languages use their own clock style (e.g. 17:39).
  final locale = Intl.defaultLocale ?? 'en';
  if (!locale.startsWith('en')) return DateFormat.jm().format(local);
  final h24 = local.hour;
  final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
  final m = local.minute.toString().padLeft(2, '0');
  final ap = h24 < 12 ? 'AM' : 'PM';
  return '$h12:$m$ap';
}

/// Compact relative times: `24min ago`, `1h ago`, `1d ago`, `1mon ago`, `1y ago`.
String formatRelativeTimeShort(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '—';
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return dateStr;

  final now = DateTime.now();
  var diff = now.difference(dt);
  if (diff.isNegative) diff = Duration.zero;

  final minutes = diff.inMinutes;
  final hours = diff.inHours;
  final days = diff.inDays;

  if (minutes < 1) return 'time.justNow'.tr();
  if (minutes < 60) {
    return 'time.minutesAgo'.tr(namedArgs: {'count': '$minutes'});
  }
  if (hours < 24) return 'time.hoursAgo'.tr(namedArgs: {'count': '$hours'});
  if (days < 30) return 'time.daysAgoShort'.tr(namedArgs: {'count': '$days'});

  var months = (now.year - dt.year) * 12 + now.month - dt.month;
  if (now.day < dt.day) months -= 1;

  if (months < 1) return 'time.daysAgoShort'.tr(namedArgs: {'count': '$days'});
  if (months < 12) {
    return 'time.monthsAgoShort'.tr(namedArgs: {'count': '$months'});
  }
  return 'time.yearsAgoShort'.tr(namedArgs: {'count': '${months ~/ 12}'});
}

/// Shown next to an entitlement expiry: future `in 3 days` / `in 2h`; past uses
/// [formatRelativeTimeShort] (`1d ago`, …).
String formatEntitlementExpiresInLabel(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return '';

  final local = dt.toLocal();
  final now = DateTime.now();
  if (local.isAfter(now)) {
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(local.year, local.month, local.day);
    final calDays = expDay.difference(today).inDays;
    if (calDays >= 1) {
      return 'time.expiresInDays'.plural(calDays);
    }
    final until = local.difference(now);
    if (until.inHours >= 1) {
      return 'time.inHoursLower'.tr(namedArgs: {'count': '${until.inHours}'});
    }
    if (until.inMinutes >= 1) {
      return 'time.inMinutesLower'.tr(
        namedArgs: {'count': '${until.inMinutes}'},
      );
    }
    return 'time.soonLower'.tr();
  }
  return formatRelativeTimeShort(dateStr);
}
