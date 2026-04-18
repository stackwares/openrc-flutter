import 'package:intl/intl.dart';

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
    if (days == 1) return 'Tomorrow · $time';
    if (days < 7) return 'In $days days · $time';
    return '${DateFormat('MMM d').format(local)} · $time';
  }
  if (local.isAfter(now)) {
    final until = local.difference(now);
    if (until.inMinutes < 1) return 'Soon';
    if (until.inMinutes < 60) return 'In ${until.inMinutes}m';
    if (until.inHours < 24) return 'In ${until.inHours}h';
  }
  return 'Today · $time';
}

String _formatTime12(DateTime local) {
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

  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}min ago';
  if (hours < 24) return '${hours}h ago';
  if (days < 30) return '${days}d ago';

  var months = (now.year - dt.year) * 12 + now.month - dt.month;
  if (now.day < dt.day) months -= 1;

  if (months < 1) return '${days}d ago';
  if (months < 12) return '${months}mon ago';
  return '${months ~/ 12}y ago';
}
