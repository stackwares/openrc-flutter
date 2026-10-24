import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_derived.dart';

/// Local calendar date from an ISO-8601 timestamp ([purchaseDate] / subscriber created).
DateTime? purchaseLocalCalendarDayFromIso(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;
  final d = DateTime.tryParse(iso.trim());
  if (d == null) return null;
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Earliest [RcTransaction.purchaseDate] per subscriber across [transactions] (loaded feed).
///
/// Walks the whole feed, so it reads the row's memoized day
/// ([RcTransactionDerived.purchaseLocalDay]) instead of re-parsing every date.
Map<String, DateTime> earliestPurchaseLocalDayBySubscriberId(
  Iterable<RcTransaction> transactions,
) {
  final out = <String, DateTime>{};
  for (final tx in transactions) {
    final id = tx.subscriberId?.trim();
    if (id == null || id.isEmpty) continue;
    final day = tx.purchaseLocalDay;
    if (day == null) continue;
    final prev = out[id];
    if (prev == null || day.isBefore(prev)) out[id] = day;
  }
  return out;
}

/// Earliest [RcTransaction.purchaseDate] **instant** (local) per subscriber — used for
/// same-day `Xs ago` when [subscriberCreatedAt] is missing or date-only (avoids anchoring
/// at local midnight, which yields bogus multi-hour offsets).
Map<String, DateTime> earliestPurchaseLocalInstantBySubscriberId(
  Iterable<RcTransaction> transactions,
) {
  final out = <String, DateTime>{};
  for (final tx in transactions) {
    final id = tx.subscriberId?.trim();
    if (id == null || id.isEmpty) continue;
    final local = tx.purchaseLocalInstant;
    if (local == null) continue;
    final prev = out[id];
    if (prev == null || local.isBefore(prev)) out[id] = local;
  }
  return out;
}

/// e.g. `42s ago`, `Since 1 day ago`, `Since 22 days ago` (local calendar).
/// Same calendar day: seconds / minutes / hours since the best anchor:
/// [subscriberCreatedAtIso] when it carries a real time, else
/// [fallbackFirstPurchaseLocalInstant] (earliest loaded [purchaseDate]).
String? formatSubscriberTenureSubtitle({
  required String? subscriberCreatedAtIso,
  required DateTime? fallbackFirstPurchaseLocalDay,
  DateTime? fallbackFirstPurchaseLocalInstant,
}) {
  var anchorDay = purchaseLocalCalendarDayFromIso(subscriberCreatedAtIso);
  anchorDay ??= fallbackFirstPurchaseLocalDay;
  if (anchorDay == null) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var days = today.difference(anchorDay).inDays;
  if (days < 0) days = 0;

  if (days == 0) {
    return _formatSinceSameCalendarDay(
      subscriberCreatedAtIso: subscriberCreatedAtIso,
      anchorLocalMidnight: anchorDay,
      fallbackFirstPurchaseLocalInstant: fallbackFirstPurchaseLocalInstant,
    );
  }
  return 'time.sinceDays'.plural(days);
}

bool _isDateOnlyIsoString(String iso) {
  final t = iso.trim();
  if (t.contains('T')) return false;
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t);
}

bool _isLikelyStartOfDayPlaceholder(
  DateTime createdLocal,
  DateTime anchorLocalMidnight,
) {
  return createdLocal.year == anchorLocalMidnight.year &&
      createdLocal.month == anchorLocalMidnight.month &&
      createdLocal.day == anchorLocalMidnight.day &&
      createdLocal.hour == 0 &&
      createdLocal.minute == 0 &&
      createdLocal.second == 0 &&
      createdLocal.millisecond == 0 &&
      createdLocal.microsecond == 0;
}

DateTime _anchorInstantForSameDayTenure({
  required String? subscriberCreatedAtIso,
  required DateTime anchorLocalMidnight,
  DateTime? fallbackFirstPurchaseLocalInstant,
}) {
  final iso = subscriberCreatedAtIso?.trim();
  final purchase = fallbackFirstPurchaseLocalInstant;
  final purchaseSameCalendarDay = purchase != null &&
      purchase.year == anchorLocalMidnight.year &&
      purchase.month == anchorLocalMidnight.month &&
      purchase.day == anchorLocalMidnight.day;

  if (iso == null || iso.isEmpty) {
    if (purchaseSameCalendarDay) return purchase;
    return anchorLocalMidnight;
  }

  if (_isDateOnlyIsoString(iso)) {
    if (purchaseSameCalendarDay) return purchase;
    return anchorLocalMidnight;
  }

  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    if (purchaseSameCalendarDay) return purchase;
    return anchorLocalMidnight;
  }

  final created = parsed.toLocal();

  if (purchaseSameCalendarDay &&
      _isLikelyStartOfDayPlaceholder(created, anchorLocalMidnight) &&
      purchase.isAfter(created)) {
    return purchase;
  }

  return created;
}

String _formatSinceSameCalendarDay({
  required String? subscriberCreatedAtIso,
  required DateTime anchorLocalMidnight,
  DateTime? fallbackFirstPurchaseLocalInstant,
}) {
  final anchorInstant = _anchorInstantForSameDayTenure(
    subscriberCreatedAtIso: subscriberCreatedAtIso,
    anchorLocalMidnight: anchorLocalMidnight,
    fallbackFirstPurchaseLocalInstant: fallbackFirstPurchaseLocalInstant,
  );

  var diff = DateTime.now().difference(anchorInstant);
  if (diff.isNegative) diff = Duration.zero;

  final secs = diff.inSeconds;
  if (secs < 60) return 'time.secondsAgo'.tr(namedArgs: {'count': '$secs'});
  final mins = diff.inMinutes;
  if (mins < 60) {
    return 'time.minutesAgoCompact'.tr(namedArgs: {'count': '$mins'});
  }
  return 'time.hoursAgo'.tr(namedArgs: {'count': '${diff.inHours}'});
}
