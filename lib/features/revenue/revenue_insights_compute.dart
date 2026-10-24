import 'package:easy_localization/easy_localization.dart';
import 'package:openrc/core/utils/plan_display.dart';
import 'package:openrc/core/utils/region_display_name.dart';
import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';

const _kRevenueInsightsTopN = 7;

class RevenueInsightAppLine {
  final String label;
  final double pct;
  final double revenue;
  final String? appId;

  const RevenueInsightAppLine({
    required this.label,
    required this.pct,
    required this.revenue,
    this.appId,
  });
}

class RevenueInsightCountryLine {
  /// Aggregation key: ISO country code or `'__'` for unknown.
  final String countryKey;

  /// Localized name only (no flag); Revenue insights row title uses this.
  final String name;
  final double pct;
  final double revenue;

  const RevenueInsightCountryLine({
    required this.countryKey,
    required this.name,
    required this.pct,
    required this.revenue,
  });

  /// Flag + name for chip-style labels (day insights).
  String get badgeLabel {
    final flag = countryInsightLeadingEmoji(countryKey);
    return '$flag $name';
  }
}

class RevenueInsightsSnapshot {
  final List<RevenueInsightAppLine> topApps;
  final List<RevenueInsightCountryLine> topCountries;
  final double applePct;
  final double googlePct;
  final double appleRevenue;
  final double googleRevenue;

  /// Web billing (Stripe, Paddle, RevenueCat Billing) and any other store,
  /// so the store shares add up to the whole.
  final double otherStoresPct;
  final double otherStoresRevenue;
  final double newPct;
  final double renewalPct;
  final double newRevenue;
  final double renewalRevenue;

  const RevenueInsightsSnapshot({
    required this.topApps,
    required this.topCountries,
    required this.applePct,
    required this.googlePct,
    required this.appleRevenue,
    required this.googleRevenue,
    this.otherStoresPct = 0,
    this.otherStoresRevenue = 0,
    required this.newPct,
    required this.renewalPct,
    required this.newRevenue,
    required this.renewalRevenue,
  });
}

enum _StorePlatformBucket { apple, google, other }

_StorePlatformBucket _storePlatformBucket(String? store) {
  final s = store?.trim().toLowerCase().replaceAll(' ', '_') ?? '';
  if (s == 'app_store' ||
      s == 'mac_app_store' ||
      s == 'appstore' ||
      s == 'apple') {
    return _StorePlatformBucket.apple;
  }
  if (s == 'play_store' ||
      s == 'google_play' ||
      s == 'playstore' ||
      s == 'android') {
    return _StorePlatformBucket.google;
  }
  return _StorePlatformBucket.other;
}

String _txAppKey(RcTransaction tx) {
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

String _txAppLabel(RcTransaction tx) {
  final a = tx.app;
  if (a == null) return 'revenue.unknownApp'.tr();
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  return 'revenue.unknownApp'.tr();
}

String _countryFlagEmoji(String code) =>
    code.length != 2 ? '🏳️' : countryFlagEmoji(code);

/// Localized name for a country key; `'__'` is the unknown bucket.
String _countryName(String countryKey) {
  final name = countryKey == '__'
      ? 'revenue.unknown'.tr()
      : regionDisplayNameForCompactBadge(countryKey);
  return name.isNotEmpty ? name : countryKey;
}

/// Flag / region glyph for insights (`__` → globe).
String countryInsightLeadingEmoji(String countryKey) {
  if (countryKey == '__') return '🌍';
  return _countryFlagEmoji(countryKey);
}

/// Aggregates revenue breakdown for [txs] (same logic as the day insights card).
RevenueInsightsSnapshot computeRevenueInsights(
  List<RcTransaction> txs,
  CommissionSettings commission,
) {
  double total = 0;
  final byApp = <String, double>{};
  final appLabel = <String, String>{};
  final appIdByKey = <String, String?>{};
  final byCountry = <String, double>{};
  double appleRev = 0;
  double googleRev = 0;
  double otherStoresRev = 0;
  double renewalRev = 0;
  double newRev = 0;

  for (final tx in txs) {
    final gross = tx.revenue ?? 0;
    final r = adjustUsdForDisplay(
      gross: gross,
      settings: commission,
      store: tx.storeForCommission,
    );
    total += r;

    final rawKey = _txAppKey(tx);
    final appKey = rawKey.isEmpty ? '__app' : rawKey;
    final label = _txAppLabel(tx);
    byApp.update(appKey, (v) => v + r, ifAbsent: () => r);
    appLabel.putIfAbsent(appKey, () => label);

    final aid = tx.app?.id?.trim();
    if (aid != null && aid.isNotEmpty) {
      final existing = appIdByKey[appKey];
      if (existing == null || existing.isEmpty) {
        appIdByKey[appKey] = aid;
      }
    }
    appIdByKey.putIfAbsent(appKey, () => null);

    final rawCc = tx.subscriberCountryCode?.trim().toUpperCase();
    final cKey = (rawCc != null && rawCc.isNotEmpty) ? rawCc : '__';
    byCountry.update(cKey, (v) => v + r, ifAbsent: () => r);

    switch (_storePlatformBucket(tx.storeForCommission)) {
      case _StorePlatformBucket.apple:
        appleRev += r;
        break;
      case _StorePlatformBucket.google:
        googleRev += r;
        break;
      case _StorePlatformBucket.other:
        otherStoresRev += r;
        break;
    }

    if (tx.type == RcTransactionType.renewal) {
      renewalRev += r;
    } else {
      newRev += r;
    }
  }

  final totalNonZero = total.abs() > 1e-9;
  double pctOf(double part) => totalNonZero ? (part / total * 100) : 0.0;

  final appEntries = byApp.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  const revEps = 1e-9;
  final topApps = <RevenueInsightAppLine>[];
  for (
    var i = 0;
    i < appEntries.length && topApps.length < _kRevenueInsightsTopN;
    i++
  ) {
    final e = appEntries[i];
    if (e.value.abs() <= revEps) continue;
    topApps.add(
      RevenueInsightAppLine(
        label: appLabel[e.key] ?? e.key,
        pct: pctOf(e.value),
        revenue: e.value,
        appId: appIdByKey[e.key],
      ),
    );
  }

  final countryEntries = byCountry.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final topCountries = <RevenueInsightCountryLine>[];
  for (
    var i = 0;
    i < countryEntries.length && topCountries.length < _kRevenueInsightsTopN;
    i++
  ) {
    final e = countryEntries[i];
    if (e.value.abs() <= revEps) continue;
    topCountries.add(
      RevenueInsightCountryLine(
        countryKey: e.key,
        name: _countryName(e.key),
        pct: pctOf(e.value),
        revenue: e.value,
      ),
    );
  }

  return RevenueInsightsSnapshot(
    topApps: topApps,
    topCountries: topCountries,
    applePct: pctOf(appleRev),
    googlePct: pctOf(googleRev),
    appleRevenue: appleRev,
    googleRevenue: googleRev,
    otherStoresPct: pctOf(otherStoresRev),
    otherStoresRevenue: otherStoresRev,
    newPct: pctOf(newRev),
    renewalPct: pctOf(renewalRev),
    newRevenue: newRev,
    renewalRevenue: renewalRev,
  );
}

/// One share of the trials: an app, a country or a plan.
class TrialInsightLine {
  /// App key, country key (ISO code or `'__'`), or plan title.
  final String key;
  final String label;
  final int count;
  final double pct;

  /// App lines only, for the icon.
  final String? appId;

  const TrialInsightLine({
    required this.key,
    required this.label,
    required this.count,
    required this.pct,
    this.appId,
  });
}

/// Trials counted by status, store, app, country and plan. Trials earn
/// nothing, so a revenue breakdown of them is all zeros.
class TrialInsightsSnapshot {
  final int total;
  final int autoRenewing;
  final int cancelled;
  final int apple;
  final int google;

  /// Web billing and any other store.
  final int otherStores;
  final List<TrialInsightLine> topApps;
  final List<TrialInsightLine> topCountries;
  final List<TrialInsightLine> topPlans;

  const TrialInsightsSnapshot({
    required this.total,
    required this.autoRenewing,
    required this.cancelled,
    required this.apple,
    required this.google,
    required this.otherStores,
    required this.topApps,
    required this.topCountries,
    required this.topPlans,
  });

  /// Share of [total], 0–100.
  double pctOf(int count) => total == 0 ? 0 : count / total * 100;
}

/// Every row is a trial, so the breakdown counts trials instead of revenue.
bool isTrialsOnly(List<RcTransaction> txs) =>
    txs.isNotEmpty && txs.every((tx) => tx.type == RcTransactionType.trial);

/// Counts [txs] (trials) the way [computeRevenueInsights] adds up revenue.
TrialInsightsSnapshot computeTrialInsights(List<RcTransaction> txs) {
  var cancelled = 0;
  var apple = 0;
  var google = 0;
  var otherStores = 0;
  final byApp = <String, int>{};
  final appLabel = <String, String>{};
  final appIdByKey = <String, String>{};
  final byCountry = <String, int>{};
  final byPlan = <String, int>{};

  for (final tx in txs) {
    if (tx.isCanceledTrial) cancelled++;

    switch (_storePlatformBucket(tx.storeForCommission)) {
      case _StorePlatformBucket.apple:
        apple++;
      case _StorePlatformBucket.google:
        google++;
      case _StorePlatformBucket.other:
        otherStores++;
    }

    final rawKey = _txAppKey(tx);
    final appKey = rawKey.isEmpty ? '__app' : rawKey;
    byApp.update(appKey, (v) => v + 1, ifAbsent: () => 1);
    appLabel.putIfAbsent(appKey, () => _txAppLabel(tx));
    final aid = tx.app?.id?.trim();
    if (aid != null && aid.isNotEmpty) {
      appIdByKey.putIfAbsent(appKey, () => aid);
    }

    final rawCc = tx.subscriberCountryCode?.trim().toUpperCase();
    final cKey = (rawCc != null && rawCc.isNotEmpty) ? rawCc : '__';
    byCountry.update(cKey, (v) => v + 1, ifAbsent: () => 1);

    final plan = planProductId(tx);
    byPlan.update(plan, (v) => v + 1, ifAbsent: () => 1);
  }

  final total = txs.length;
  double pctOf(int count) => total == 0 ? 0 : count / total * 100;

  // Most trials first; ties by key so the order holds between rebuilds.
  List<TrialInsightLine> top(
    Map<String, int> counts,
    String Function(String key) label, {
    Map<String, String> appIds = const {},
  }) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [
      for (final e in entries.take(_kRevenueInsightsTopN))
        TrialInsightLine(
          key: e.key,
          label: label(e.key),
          count: e.value,
          pct: pctOf(e.value),
          appId: appIds[e.key],
        ),
    ];
  }

  return TrialInsightsSnapshot(
    total: total,
    autoRenewing: total - cancelled,
    cancelled: cancelled,
    apple: apple,
    google: google,
    otherStores: otherStores,
    topApps: top(byApp, (k) => appLabel[k] ?? k, appIds: appIdByKey),
    topCountries: top(byCountry, _countryName),
    topPlans: top(byPlan, (k) => k),
  );
}
