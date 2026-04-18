/// Local 12-hour time for dense list rows, e.g. `8:54AM`, `12:21PM`.
String formatTransactionListTime(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '—';
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return dateStr;
  final local = dt.toLocal();
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
