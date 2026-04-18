import 'package:revenuecat/models/rc_transaction.dart';

/// Local calendar date from an ISO-8601 timestamp ([purchaseDate] / subscriber created).
DateTime? purchaseLocalCalendarDayFromIso(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;
  final d = DateTime.tryParse(iso.trim());
  if (d == null) return null;
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Earliest [RcTransaction.purchaseDate] per subscriber across [transactions] (loaded feed).
Map<String, DateTime> earliestPurchaseLocalDayBySubscriberId(
  Iterable<RcTransaction> transactions,
) {
  final out = <String, DateTime>{};
  for (final tx in transactions) {
    final id = tx.subscriberId?.trim();
    if (id == null || id.isEmpty) continue;
    final day = purchaseLocalCalendarDayFromIso(tx.purchaseDate);
    if (day == null) continue;
    final prev = out[id];
    if (prev == null || day.isBefore(prev)) out[id] = day;
  }
  return out;
}

/// e.g. `New user`, `Since 1 day ago`, `Since 22 days ago` (local calendar).
String? formatSubscriberTenureSubtitle({
  required String? subscriberCreatedAtIso,
  required DateTime? fallbackFirstPurchaseLocalDay,
}) {
  var anchor = purchaseLocalCalendarDayFromIso(subscriberCreatedAtIso);
  anchor ??= fallbackFirstPurchaseLocalDay;
  if (anchor == null) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var days = today.difference(anchor).inDays;
  if (days < 0) days = 0;

  if (days == 0) return 'New user';
  if (days == 1) return 'Since 1 day ago';
  return 'Since $days days ago';
}
