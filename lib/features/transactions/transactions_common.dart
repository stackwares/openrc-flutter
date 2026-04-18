import 'package:intl/intl.dart';
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

/// Background preload pages after the first fetch (Revenue tab progress).
const int kRealtimeBackfillMaxPages = 100;

/// Internal “done” value for realtime preload step (not a predictable page total in the UI).
const int kRealtimeLoadTarget = 1 + kRealtimeBackfillMaxPages;

/// Month-to-date label above the Revenue tab MTD total (local calendar month).
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
enum TransactionPlatformFilter {
  apple,
  google,
  web,
  test,
}

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
    case TransactionPlatformFilter.test:
      return tx.isSandbox == true;
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

  for (final opt in collectAppFilterOptions(filterSource)) {
    byKey.putIfAbsent(opt.key, () => opt);
  }

  final onScreenOrdered = collectAppFilterOptions(filterSource)
      .map((o) => o.key)
      .toList();
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

String localTodayDayKey() {
  final n = DateTime.now();
  return DateFormat('yyyy-MM-dd').format(DateTime(n.year, n.month, n.day));
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
