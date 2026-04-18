import 'package:intl/intl.dart';
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

/// Background preload pages after the first fetch (Realtime progress).
const int kRealtimeBackfillMaxPages = 100;

/// First successful fetch + up to [kRealtimeBackfillMaxPages] backfill pages.
const int kRealtimeLoadTarget = 1 + kRealtimeBackfillMaxPages;

/// Subtitle under the Realtime app bar (month-to-date, local timezone).
const String kRealtimeWindowSubtitle = 'This month · local';

final RegExp _isoCalendarDayKeyRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isIsoCalendarDayKey(String key) => _isoCalendarDayKeyRe.hasMatch(key);

/// Dedupe key when merging paginated `/me/transactions` responses (Kedi-style).
String? rcTransactionDedupKey(RcTransaction tx) {
  final stid = tx.storeTransactionIdentifier?.trim();
  if (stid != null && stid.isNotEmpty) return 'stid:$stid';
  final sub = tx.subscriberId?.trim();
  final prod = tx.productIdentifier?.trim();
  final pd = tx.purchaseDate?.trim();
  if (sub != null &&
      sub.isNotEmpty &&
      prod != null &&
      prod.isNotEmpty &&
      pd != null &&
      pd.isNotEmpty) {
    return 'cmp:$sub|$prod|$pd';
  }
  return null;
}

/// Gross revenue: sum of [RcTransaction.revenue] (null → 0), before store commission.
double grossRevenueSum(Iterable<RcTransaction> transactions) {
  return transactions.fold(0.0, (sum, tx) => sum + (tx.revenue ?? 0));
}

/// Net revenue: sum of [RcTransaction.revenue] (null → 0), with optional store commission.
double netRevenueSum(
  Iterable<RcTransaction> transactions,
  CommissionSettings commission,
) {
  return transactions.fold(0.0, (sum, tx) {
    final gross = tx.revenue ?? 0;
    return sum +
        adjustUsdForDisplay(
          gross: gross,
          settings: commission,
          store: tx.storeForCommission,
        );
  });
}

/// Loaded `/me/transactions` rows whose **local** [RcTransaction.purchaseDate] calendar day
/// falls in the last [inclusiveDays] days ending today (inclusive).
///
/// Walks every list in [grouped] and filters by each row’s purchase timestamp — not by map
/// bucket keys and **not** from overview / `charts_v2` revenue (which can differ).
List<RcTransaction> collectTransactionsInLastLocalDays(
  Map<String, List<RcTransaction>> grouped,
  int inclusiveDays,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(Duration(days: inclusiveDays - 1));
  final out = <RcTransaction>[];
  final seen = <String>{};

  for (final list in grouped.values) {
    for (final tx in list) {
      final dedup = rcTransactionDedupKey(tx);
      if (dedup != null) {
        if (seen.contains(dedup)) continue;
      }
      final pd = tx.purchaseDate?.trim();
      if (pd == null || pd.isEmpty) continue;
      final parsed = DateTime.tryParse(pd);
      if (parsed == null) continue;
      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day.isBefore(start) || day.isAfter(today)) continue;
      if (dedup != null) seen.add(dedup);
      out.add(tx);
    }
  }
  return out;
}

/// Local midnight at the first day of the current calendar month.
DateTime localStartOfCurrentMonth() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, 1);
}

/// Oldest purchase **local calendar day** in [grouped], or null if no parseable dates.
DateTime? oldestPurchaseLocalCalendarDay(
  Map<String, List<RcTransaction>> grouped,
) {
  DateTime? oldest;
  for (final list in grouped.values) {
    for (final tx in list) {
      final pd = tx.purchaseDate?.trim();
      if (pd == null || pd.isEmpty) continue;
      final parsed = DateTime.tryParse(pd);
      if (parsed == null) continue;
      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (oldest == null || day.isBefore(oldest)) oldest = day;
    }
  }
  return oldest;
}

/// True once pagination has loaded at least one transaction on a local day **before**
/// [monthStartLocal] (exclusive), so month-to-date rows should be complete.
bool realtimeMonthBackfillBoundaryReached(
  Map<String, List<RcTransaction>> grouped,
  DateTime monthStartLocal,
) {
  final oldest = oldestPurchaseLocalCalendarDay(grouped);
  if (oldest == null) return true;
  return oldest.isBefore(monthStartLocal);
}

/// `/me/transactions` rows in the **current local calendar month** through today (inclusive).
List<RcTransaction> collectTransactionsInCurrentLocalMonth(
  Map<String, List<RcTransaction>> grouped,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monthStart = DateTime(now.year, now.month, 1);
  final out = <RcTransaction>[];
  final seen = <String>{};

  for (final list in grouped.values) {
    for (final tx in list) {
      final dedup = rcTransactionDedupKey(tx);
      if (dedup != null) {
        if (seen.contains(dedup)) continue;
      }
      final pd = tx.purchaseDate?.trim();
      if (pd == null || pd.isEmpty) continue;
      final parsed = DateTime.tryParse(pd);
      if (parsed == null) continue;
      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day.isBefore(monthStart) || day.isAfter(today)) continue;
      if (dedup != null) seen.add(dedup);
      out.add(tx);
    }
  }
  return out;
}

/// Every row in [grouped], deduped with [rcTransactionDedupKey] (same key as list merges).
List<RcTransaction> flattenGroupedTransactionsDeduped(
  Map<String, List<RcTransaction>> grouped,
) {
  final seen = <String>{};
  final out = <RcTransaction>[];
  for (final list in grouped.values) {
    for (final tx in list) {
      final k = rcTransactionDedupKey(tx);
      if (k != null) {
        if (seen.contains(k)) continue;
        seen.add(k);
      }
      out.add(tx);
    }
  }
  return out;
}

Map<String, List<RcTransaction>> filteredGroupedByApps(
  Map<String, List<RcTransaction>> grouped,
  Set<String>? appFilter,
) {
  if (appFilter == null) return grouped;
  final out = <String, List<RcTransaction>>{};
  for (final e in grouped.entries) {
    final filtered = e.value
        .where((tx) => appFilter.contains(appKeyForTransaction(tx)))
        .toList();
    if (filtered.isNotEmpty) {
      out[e.key] = filtered;
    }
  }
  return out;
}

Map<String, double> dailyTotalsForGrouped(
  Map<String, List<RcTransaction>> grouped,
  CommissionSettings commission,
) {
  final totals = <String, double>{};
  for (final entry in grouped.entries) {
    totals[entry.key] = netRevenueSum(entry.value, commission);
  }
  return totals;
}

String appKeyForTransaction(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return '';
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return '';
}

String appLabelForTransaction(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return 'Unknown app';
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  return 'Unknown app';
}

class AppFilterOption {
  final String key;
  final String label;
  final String? appId;

  const AppFilterOption(this.key, this.label, this.appId);
}

List<AppFilterOption> collectAppFilterOptions(
  Map<String, List<RcTransaction>> grouped,
) {
  final labelByKey = <String, String>{};
  final appIdByKey = <String, String>{};
  for (final list in grouped.values) {
    for (final tx in list) {
      final k = appKeyForTransaction(tx);
      labelByKey.putIfAbsent(k, () => appLabelForTransaction(tx));
      final aid = tx.app?.id?.trim();
      if (aid != null && aid.isNotEmpty) {
        appIdByKey.putIfAbsent(k, () => aid);
      }
    }
  }
  final out = labelByKey.entries
      .map((e) => AppFilterOption(e.key, e.value, appIdByKey[e.key]))
      .toList();
  out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return out;
}

String localTodayDayKey() {
  final n = DateTime.now();
  return DateFormat('yyyy-MM-dd').format(DateTime(n.year, n.month, n.day));
}

/// Day header grid categories (Transactions day view + Realtime).
enum TransactionDaySectionFilter {
  trial,
  conversion,
  renewal,
  subscription,
  refunded,
  cancelled,
}

bool transactionMatchesSectionFilter(
  RcTransaction tx,
  TransactionDaySectionFilter filter,
) {
  final t = tx.type;
  switch (filter) {
    case TransactionDaySectionFilter.trial:
      return t == RcTransactionType.trial;
    case TransactionDaySectionFilter.conversion:
      return t == RcTransactionType.conversion;
    case TransactionDaySectionFilter.renewal:
      return t == RcTransactionType.renewal;
    case TransactionDaySectionFilter.subscription:
      return t == RcTransactionType.newSubscription ||
          t == RcTransactionType.oneTimePurchase;
    case TransactionDaySectionFilter.refunded:
      return t == RcTransactionType.refund;
    case TransactionDaySectionFilter.cancelled:
      return tx.isCancelledSummaryBadge;
  }
}

/// Label text matching the summary grid cells.
String transactionDaySectionGridLabel(TransactionDaySectionFilter filter) {
  return switch (filter) {
    TransactionDaySectionFilter.trial => 'Trials',
    TransactionDaySectionFilter.conversion => 'Conversions',
    TransactionDaySectionFilter.renewal => 'Renewals',
    TransactionDaySectionFilter.subscription => 'Purchases',
    TransactionDaySectionFilter.refunded => 'Refunds',
    TransactionDaySectionFilter.cancelled => 'Cancellations',
  };
}
