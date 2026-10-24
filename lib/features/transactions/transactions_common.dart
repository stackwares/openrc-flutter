import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_derived.dart';
import 'package:openrc/models/transaction_list_sort_mode.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:easy_localization/easy_localization.dart';

export 'package:openrc/core/utils/app_identity.dart'
    show appKeyForTransaction, appLabelForTransaction;

import 'package:openrc/core/utils/app_identity.dart';

/// Background preload pages after the first fetch (Revenue tab progress).
const int kRealtimeBackfillMaxPages = 100;

/// Internal “done” value for realtime preload step (not a predictable page total in the UI).
const int kRealtimeLoadTarget = 1 + kRealtimeBackfillMaxPages;

/// Month-to-date label above the Revenue tab MTD total (local calendar month).
String get kRealtimeWindowSubtitle =>
    'transactions.realtimeWindowSubtitle'.tr();

final RegExp _isoCalendarDayKeyRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isIsoCalendarDayKey(String key) => _isoCalendarDayKeyRe.hasMatch(key);

/// Dedupe key when merging paginated `/me/transactions` responses (Kedi-style).
/// Built once per row; see [RcTransactionDerived.mergeKey].
String? rcTransactionDedupKey(RcTransaction tx) => tx.mergeKey;

/// Local calendar day of [tx.purchaseDate], or null when the date is missing.
///
/// Parsed once per row ([RcTransactionDerived.purchaseLocalDay]); the loaded
/// feed is re-walked for every rebuild and every background page.
DateTime? localPurchaseCalendarDay(RcTransaction tx) => tx.purchaseLocalDay;

/// Local midnight of [date]'s calendar day, for range comparisons.
DateTime localCalendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// True when [tx]'s local purchase day sits in [[start], [end]], inclusive.
bool localPurchaseDayInInclusiveRange(
  RcTransaction tx,
  DateTime start,
  DateTime end,
) => localPurchaseDayInDayRange(
  tx,
  localCalendarDay(start),
  localCalendarDay(end),
);

/// [localPurchaseDayInInclusiveRange] for a caller that already reduced the
/// bounds to [localCalendarDay]s.
///
/// Building a local `DateTime` is not free, and the payout estimate checks
/// the same two bounds against every loaded row; the caller can hoist them.
bool localPurchaseDayInDayRange(
  RcTransaction tx,
  DateTime startDay,
  DateTime endDay,
) {
  final day = localPurchaseCalendarDay(tx);
  if (day == null) return false;
  return !day.isBefore(startDay) && !day.isAfter(endDay);
}

/// Deduped rows whose local purchase day is in [[start], [end]], inclusive.
List<RcTransaction> collectTransactionsInLocalInclusiveRange(
  Iterable<RcTransaction> transactions, {
  required DateTime start,
  required DateTime end,
}) {
  final startDay = localCalendarDay(start);
  final endDay = localCalendarDay(end);
  final out = <RcTransaction>[];
  final seen = <String>{};
  for (final tx in transactions) {
    final dedup = rcTransactionDedupKey(tx);
    if (dedup != null && seen.contains(dedup)) continue;
    if (!localPurchaseDayInDayRange(tx, startDay, endDay)) continue;
    if (dedup != null) seen.add(dedup);
    out.add(tx);
  }
  return out;
}

/// Oldest local purchase day in [transactions], or null if none parse.
DateTime? oldestLocalPurchaseCalendarDay(Iterable<RcTransaction> transactions) {
  DateTime? oldest;
  for (final tx in transactions) {
    final day = localPurchaseCalendarDay(tx);
    if (day == null) continue;
    if (oldest == null || day.isBefore(oldest)) oldest = day;
  }
  return oldest;
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
      final day = tx.purchaseLocalDay;
      if (day == null) continue;
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
      final day = tx.purchaseLocalDay;
      if (day == null) continue;
      if (oldest == null || day.isBefore(oldest)) oldest = day;
    }
  }
  return oldest;
}

/// `/me/transactions` rows in the **current local calendar month** up to now:
/// scheduled (future-dated) rows later today haven't happened yet.
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
      final day = tx.purchaseLocalDay;
      final instant = tx.purchaseLocalInstant;
      if (day == null || instant == null) continue;
      if (day.isBefore(monthStart) || day.isAfter(today)) continue;
      if (instant.isAfter(now)) continue;
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

/// [countryCodes] null or empty → no country restriction. Otherwise a row
/// matches if its country is in the set or (when `'__'` is included) country is unknown.
bool transactionMatchesCountryFilters(
  RcTransaction tx,
  Set<String>? countryCodes,
) {
  if (countryCodes == null || countryCodes.isEmpty) return true;
  final cc = tx.subscriberCountryCode?.trim().toUpperCase();
  final unknown = cc == null || cc.isEmpty;
  if (unknown) return countryCodes.contains('__');
  return countryCodes.contains(cc);
}

/// Store source filter for transaction lists. `null` means no store restriction.
///
/// There is no sandbox option: transactions are always requested with
/// `sandbox_mode=false`, so a sandbox filter could never match.
enum TransactionPlatformFilter { apple, google, web }

bool _transactionStoreLooksLikeWebBilling(RcTransaction tx) {
  final raw = tx.store?.trim();
  if (raw == null || raw.isEmpty) return false;
  if (classifyStore(raw) != StoreCommissionPlatform.other) return false;
  final s = raw.toLowerCase().replaceAll(' ', '_');
  if (s.contains('stripe')) return true;
  if (s.contains('promotional')) return true;
  if (s.contains('amazon')) return true;
  if (s.contains('paddle')) return true;
  if (s.contains('rc_billing') || s.contains('rcbilling')) return true;
  if (s.contains('web')) return true;
  return false;
}

bool _transactionMatchesOnePlatformFilter(
  RcTransaction tx,
  TransactionPlatformFilter platform,
) {
  switch (platform) {
    case TransactionPlatformFilter.apple:
      return classifyStore(tx.storeForCommission) ==
          StoreCommissionPlatform.apple;
    case TransactionPlatformFilter.google:
      return classifyStore(tx.storeForCommission) ==
          StoreCommissionPlatform.google;
    case TransactionPlatformFilter.web:
      return _transactionStoreLooksLikeWebBilling(tx);
  }
}

/// [platforms] null or empty → no restriction. Otherwise the row matches if it
/// satisfies any selected platform (OR).
bool transactionMatchesPlatformFilter(
  RcTransaction tx,
  Set<TransactionPlatformFilter>? platforms,
) {
  if (platforms == null || platforms.isEmpty) return true;
  for (final p in platforms) {
    if (_transactionMatchesOnePlatformFilter(tx, p)) return true;
  }
  return false;
}

/// Single store bucket per transaction for day-summary **count** distribution.
/// Sandbox rows are omitted from distribution ([platformCountsByDaySection] skips them).
/// Web-style billing uses the same heuristic as [TransactionPlatformFilter.web].
enum TransactionDaySummaryPlatform { apple, google, web, other }

TransactionDaySummaryPlatform transactionDaySummaryPlatform(RcTransaction tx) {
  switch (classifyStore(tx.storeForCommission)) {
    case StoreCommissionPlatform.apple:
      return TransactionDaySummaryPlatform.apple;
    case StoreCommissionPlatform.google:
      return TransactionDaySummaryPlatform.google;
    case StoreCommissionPlatform.other:
      break;
  }
  if (_transactionStoreLooksLikeWebBilling(tx)) {
    return TransactionDaySummaryPlatform.web;
  }
  return TransactionDaySummaryPlatform.other;
}

Map<String, List<RcTransaction>> filteredGroupedByTransactionMeta(
  Map<String, List<RcTransaction>> grouped, {
  Set<String>? countryCodes,
  Set<TransactionPlatformFilter>? platforms,
}) {
  final countryActive = countryCodes != null && countryCodes.isNotEmpty;
  final platformActive = platforms != null && platforms.isNotEmpty;
  if (!countryActive && !platformActive) return grouped;
  final out = <String, List<RcTransaction>>{};
  for (final e in grouped.entries) {
    final filtered = e.value.where((tx) {
      if (!transactionMatchesCountryFilters(tx, countryCodes)) return false;
      if (!transactionMatchesPlatformFilter(tx, platforms)) return false;
      return true;
    }).toList();
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

int _transactionPurchaseDateMs(RcTransaction tx) {
  final s = tx.purchaseDate?.trim();
  if (s == null || s.isEmpty) return 0;
  return DateTime.tryParse(s)?.millisecondsSinceEpoch ?? 0;
}

/// Sorts [list] in place according to [mode]. Uses [RcTransaction.tileDisplayRevenue]
/// for amount modes (matches list tile amounts, including refund display rules).
void sortMutableTransactionList(
  List<RcTransaction> list,
  TransactionListSortMode mode,
) {
  switch (mode) {
    case TransactionListSortMode.purchaseNewestFirst:
      list.sort(
        (a, b) => _transactionPurchaseDateMs(
          b,
        ).compareTo(_transactionPurchaseDateMs(a)),
      );
    case TransactionListSortMode.purchaseOldestFirst:
      list.sort(
        (a, b) => _transactionPurchaseDateMs(
          a,
        ).compareTo(_transactionPurchaseDateMs(b)),
      );
    case TransactionListSortMode.revenueHighToLow:
      list.sort((a, b) {
        final cmp = (b.tileDisplayRevenue ?? 0.0).compareTo(
          a.tileDisplayRevenue ?? 0.0,
        );
        if (cmp != 0) return cmp;
        return _transactionPurchaseDateMs(
          b,
        ).compareTo(_transactionPurchaseDateMs(a));
      });
    case TransactionListSortMode.revenueLowToHigh:
      list.sort((a, b) {
        final cmp = (a.tileDisplayRevenue ?? 0.0).compareTo(
          b.tileDisplayRevenue ?? 0.0,
        );
        if (cmp != 0) return cmp;
        return _transactionPurchaseDateMs(
          b,
        ).compareTo(_transactionPurchaseDateMs(a));
      });
  }
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

/// Apps shown in the filter sheet: every dashboard [projects] row, plus any extra
/// keys seen only in [filterSource] (e.g. legacy bundle-id keys).
List<AppFilterOption> collectAppFilterOptionsWithProjects(
  Map<String, List<RcTransaction>> filterSource,
  List<RcProject> projects,
) {
  if (projects.isEmpty) {
    return collectAppFilterOptions(filterSource);
  }

  final byKey = <String, AppFilterOption>{};
  for (final p in projects) {
    final id = p.id?.trim();
    if (id == null || id.isEmpty) continue;
    final name = p.name?.trim();
    final label = (name != null && name.isNotEmpty) ? name : id;
    byKey[id] = AppFilterOption(id, label, id);
  }

  // One pass over [filterSource]: this runs from `build`, so scanning and
  // sorting its apps twice would be wasted work on every frame.
  final onScreen = collectAppFilterOptions(filterSource);
  for (final opt in onScreen) {
    byKey.putIfAbsent(opt.key, () => opt);
  }

  final onScreenOrdered = onScreen.map((o) => o.key).toList();
  final seen = <String>{};
  final out = <AppFilterOption>[];
  for (final k in onScreenOrdered) {
    final o = byKey[k];
    if (o != null) {
      out.add(o);
      seen.add(k);
    }
  }
  final restKeys = byKey.keys.where((k) => !seen.contains(k)).toList()
    ..sort(
      (a, b) => byKey[a]!.label.toLowerCase().compareTo(
        byKey[b]!.label.toLowerCase(),
      ),
    );
  for (final k in restKeys) {
    out.add(byKey[k]!);
  }
  return out;
}

/// `yyyy-MM-dd` for the local calendar day of [date].
///
/// Built by hand rather than with [DateFormat]: day keys are compared and
/// reversed as strings (and matched against [isIsoCalendarDayKey]), so they
/// always need ASCII digits, and a formatter per call is work the day view
/// cannot spare.
String isoLocalDayKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String localTodayDayKey() {
  final n = DateTime.now();
  return isoLocalDayKey(DateTime(n.year, n.month, n.day));
}

/// Day header grid categories (Transactions day view + Revenue tab).
enum TransactionDaySectionFilter {
  trial,
  conversion,
  renewal,
  subscription,
  refunded,
  cancelled,
}

/// [filters] empty → no section restriction (matches all).
bool transactionMatchesAnySectionFilters(
  RcTransaction tx,
  Set<TransactionDaySectionFilter> filters,
) {
  if (filters.isEmpty) return true;
  for (final f in filters) {
    if (transactionMatchesSectionFilter(tx, f)) return true;
  }
  return false;
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

/// Per–section-filter platform counts for the day summary grid (a row may match
/// more than one section, same as the headline counts).
Map<TransactionDaySectionFilter, Map<TransactionDaySummaryPlatform, int>>
platformCountsByDaySection(List<RcTransaction> transactions) {
  final platforms = TransactionDaySummaryPlatform.values;
  final out =
      <TransactionDaySectionFilter, Map<TransactionDaySummaryPlatform, int>>{
        for (final f in TransactionDaySectionFilter.values)
          f: {for (final p in platforms) p: 0},
      };
  for (final tx in transactions) {
    if (tx.isSandbox == true) continue;
    final bucket = transactionDaySummaryPlatform(tx);
    for (final f in TransactionDaySectionFilter.values) {
      if (transactionMatchesSectionFilter(tx, f)) {
        out[f]![bucket] = out[f]![bucket]! + 1;
      }
    }
  }
  return out;
}

/// Label text matching the summary grid cells.
String transactionDaySectionGridLabel(TransactionDaySectionFilter filter) {
  return switch (filter) {
    TransactionDaySectionFilter.trial => 'transactions.trials'.tr(),
    TransactionDaySectionFilter.conversion => 'transactions.conversions'.tr(),
    TransactionDaySectionFilter.renewal => 'transactions.renewals'.tr(),
    TransactionDaySectionFilter.subscription => 'transactions.purchases'.tr(),
    TransactionDaySectionFilter.refunded => 'transactions.refunds'.tr(),
    TransactionDaySectionFilter.cancelled => 'transactions.cancellations'.tr(),
  };
}

/// Category counts for a day, as shown in the summary tiles and the home
/// screen widget. A cancelled trial counts as a trial and as a cancellation.
class DayTxnCounts {
  final int trials;
  final int conversions;
  final int renewals;
  final int purchases;
  final int refunds;
  final int cancelled;

  DayTxnCounts({
    required this.trials,
    required this.conversions,
    required this.renewals,
    required this.purchases,
    required this.refunds,
    required this.cancelled,
  });
}

DayTxnCounts aggregateDayCounts(List<RcTransaction> transactions) {
  var trials = 0;
  var conversions = 0;
  var renewals = 0;
  var purchases = 0;
  var refunds = 0;
  var cancelled = 0;
  for (final tx in transactions) {
    if (tx.type == RcTransactionType.refund) {
      refunds++;
    } else if (tx.isCancelledSummaryBadge) {
      cancelled++;
    }
    switch (tx.type) {
      case RcTransactionType.trial:
        trials++;
        break;
      case RcTransactionType.conversion:
        conversions++;
        break;
      case RcTransactionType.renewal:
        renewals++;
        break;
      case RcTransactionType.newSubscription:
      case RcTransactionType.oneTimePurchase:
        purchases++;
        break;
      case RcTransactionType.refund:
      case RcTransactionType.unknown:
        break;
    }
  }
  return DayTxnCounts(
    trials: trials,
    conversions: conversions,
    renewals: renewals,
    purchases: purchases,
    refunds: refunds,
    cancelled: cancelled,
  );
}
