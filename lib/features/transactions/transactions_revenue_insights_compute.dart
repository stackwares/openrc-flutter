import 'package:revenuecat/core/utils/region_display_name.dart';
import 'package:revenuecat/core/utils/store_commission.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

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

  /// English name only (no flag); Realtime row title uses this.
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
  if (a == null) return 'Unknown app';
  final name = a.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  final bid = a.bundleId?.trim();
  if (bid != null && bid.isNotEmpty) return bid;
  final id = a.id?.trim();
  if (id != null && id.isNotEmpty) return id;
  return 'Unknown app';
}

String _countryFlagEmoji(String code) {
  if (code.length != 2) return '🏳️';
  return String.fromCharCodes(
    code.toUpperCase().codeUnits.map((c) => c + 127397),
  );
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
    final name = e.key == '__'
        ? 'Unknown'
        : regionDisplayNameForCompactBadge(e.key);
    final displayName = name.isNotEmpty ? name : e.key;
    topCountries.add(
      RevenueInsightCountryLine(
        countryKey: e.key,
        name: displayName,
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
    newPct: pctOf(newRev),
    renewalPct: pctOf(renewalRev),
    newRevenue: newRev,
    renewalRevenue: renewalRev,
  );
}
