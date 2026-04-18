import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/core/utils/region_display_name.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_leading_avatar.dart';
import 'package:revenuecat/features/transactions/widgets/transaction_type_badge.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';

/// Revenue breakdown for a list of transactions (e.g. one calendar day).
class TransactionsRevenueInsightsCard extends StatefulWidget {
  final List<RcTransaction> transactions;

  const TransactionsRevenueInsightsCard({
    super.key,
    required this.transactions,
  });

  @override
  State<TransactionsRevenueInsightsCard> createState() =>
      _TransactionsRevenueInsightsCardState();
}

class _TransactionsRevenueInsightsCardState
    extends State<TransactionsRevenueInsightsCard> {
  bool _expanded = false;

  static const _animDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final transactions = widget.transactions;
    final data = _computeInsights(transactions);
    final scheme = context.colorScheme;

    if (transactions.isEmpty) {
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No transactions for insights',
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        final appIconOverrides = ref.watch(appIconOverridesProvider);
        return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'REVENUE INSIGHTS',
                        style: context.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: _animDuration,
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: _animDuration,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(context, 'Top apps'),
                        const SizedBox(height: 8),
                        _insightBadgeWrap(
                          context,
                          data.topApps
                              .map(
                                (e) => _InsightBadgeSpec(
                                  label: e.label,
                                  pct: e.pct,
                                  color: scheme.primary,
                                  appIdForIcon: e.appId,
                                  maxLabelWidth: 248,
                                ),
                              )
                              .toList(),
                          emptyHint: 'No app revenue',
                          appIconOverrides: appIconOverrides,
                        ),
                        const SizedBox(height: 14),
                        _sectionLabel(context, 'Top countries'),
                        const SizedBox(height: 8),
                        _insightBadgeWrap(
                          context,
                          data.topCountries
                              .map(
                                (e) => _InsightBadgeSpec(
                                  label: e.label,
                                  pct: e.pct,
                                  color: scheme.tertiary,
                                  maxLines: 2,
                                  maxLabelWidth: 300,
                                ),
                              )
                              .toList(),
                          emptyHint: 'No country data',
                        ),
                        const SizedBox(height: 14),
                        _sectionLabel(context, 'Platform'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _distributionBadge(
                              context,
                              label: 'Apple',
                              pct: data.applePct,
                              color: scheme.onSurfaceVariant,
                              leadingIcon: Icons.apple,
                            ),
                            _distributionBadge(
                              context,
                              label: 'Google',
                              pct: data.googlePct,
                              color: scheme.onSurfaceVariant,
                              leadingIcon: Icons.android,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _sectionLabel(context, 'New vs renewals'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _distributionBadge(
                              context,
                              label: 'New',
                              pct: data.newPct,
                              color: scheme.onSurfaceVariant,
                              leadingIcon: Icons.add_circle_outline,
                            ),
                            _distributionBadge(
                              context,
                              label: 'Renewals',
                              pct: data.renewalPct,
                              color: scheme.onSurfaceVariant,
                              leadingIcon: Icons.autorenew,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
      },
    );
  }

  static Widget _sectionLabel(BuildContext context, String title) {
    return Text(
      title,
      style: context.textTheme.labelSmall?.copyWith(
        color: context.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  static Widget _insightBadgeWrap(
    BuildContext context,
    List<_InsightBadgeSpec> specs, {
    required String emptyHint,
    Map<String, String>? appIconOverrides,
  }) {
    if (specs.isEmpty) {
      return Text(
        emptyHint,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: specs
          .map(
            (s) => _insightPill(
              context,
              s,
              appIconOverrides: appIconOverrides,
            ),
          )
          .toList(),
    );
  }

  static Widget _insightPill(
    BuildContext context,
    _InsightBadgeSpec spec, {
    Map<String, String>? appIconOverrides,
  }) {
    final pctStr = '${spec.pct.toStringAsFixed(1)}%';
    final text = Text(
      '${spec.label} $pctStr',
      maxLines: spec.maxLines,
      overflow: TextOverflow.ellipsis,
      style: TransactionPillStyle.textStyle(spec.color),
    );

    final Widget inner;
    if (appIconOverrides != null) {
      final url = spec.appIdForIcon != null
          ? appIconOverrides[spec.appIdForIcon!]
          : null;
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TransactionLeadingAvatar(
            imageUrl: url,
            size: 18,
            borderRadius: 5,
            tintColor: spec.color,
            fallback: Icon(
              Icons.apps_outlined,
              size: 11,
              color: spec.color,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(child: text),
        ],
      );
    } else {
      inner = text;
    }

    return Container(
      padding: TransactionPillStyle.padding,
      decoration: TransactionPillStyle.decoration(spec.color),
      constraints: BoxConstraints(maxWidth: spec.maxLabelWidth),
      child: inner,
    );
  }

  static Widget _distributionBadge(
    BuildContext context, {
    required String label,
    required double pct,
    required Color color,
    IconData? leadingIcon,
  }) {
    final pctStr = '${pct.toStringAsFixed(1)}%';
    final text = Text(
      '$label $pctStr',
      style: TransactionPillStyle.textStyle(color),
    );
    return Container(
      padding: TransactionPillStyle.padding,
      decoration: TransactionPillStyle.decoration(color),
      child: leadingIcon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  leadingIcon,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                text,
              ],
            ),
    );
  }
}

class _InsightBadgeSpec {
  final String label;
  final double pct;
  final Color color;
  final int maxLines;
  final double maxLabelWidth;
  /// RevenueCat app id for [appIconOverridesProvider] lookup; may be null.
  final String? appIdForIcon;

  const _InsightBadgeSpec({
    required this.label,
    required this.pct,
    required this.color,
    this.maxLines = 1,
    this.maxLabelWidth = 220,
    this.appIdForIcon,
  });
}

class _RankedApp {
  final String label;
  final double pct;
  final String? appId;

  const _RankedApp({
    required this.label,
    required this.pct,
    required this.appId,
  });
}

class _RankedCountry {
  /// Flag emoji + full English country name (or "Unknown" when missing).
  final String label;
  final double pct;

  const _RankedCountry({
    required this.label,
    required this.pct,
  });
}

class _InsightsComputed {
  final List<_RankedApp> topApps;
  final List<_RankedCountry> topCountries;
  final double applePct;
  final double googlePct;
  final double newPct;
  final double renewalPct;

  const _InsightsComputed({
    required this.topApps,
    required this.topCountries,
    required this.applePct,
    required this.googlePct,
    required this.newPct,
    required this.renewalPct,
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

_InsightsComputed _computeInsights(List<RcTransaction> txs) {
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
    final r = tx.revenue ?? 0;
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
    final cKey =
        (rawCc != null && rawCc.isNotEmpty) ? rawCc : '__';
    byCountry.update(cKey, (v) => v + r, ifAbsent: () => r);

    switch (_storePlatformBucket(tx.store)) {
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
  double pctOf(double part) =>
      totalNonZero ? (part / total * 100) : 0.0;

  final appEntries = byApp.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final topApps = <_RankedApp>[];
  for (var i = 0; i < appEntries.length && topApps.length < 5; i++) {
    final e = appEntries[i];
    topApps.add(
      _RankedApp(
        label: appLabel[e.key] ?? e.key,
        pct: pctOf(e.value),
        appId: appIdByKey[e.key],
      ),
    );
  }

  final countryEntries = byCountry.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final topCountries = <_RankedCountry>[];
  for (var i = 0; i < countryEntries.length && topCountries.length < 5; i++) {
    final e = countryEntries[i];
    final flag = e.key == '__' ? '🌍' : _countryFlagEmoji(e.key);
    final name = e.key == '__'
        ? 'Unknown'
        : regionDisplayNameForCompactBadge(e.key);
    final displayName = name.isNotEmpty ? name : e.key;
    topCountries.add(
      _RankedCountry(
        label: '$flag $displayName',
        pct: pctOf(e.value),
      ),
    );
  }

  return _InsightsComputed(
    topApps: topApps,
    topCountries: topCountries,
    applePct: pctOf(appleRev),
    googlePct: pctOf(googleRev),
    newPct: pctOf(newRev),
    renewalPct: pctOf(renewalRev),
  );
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
