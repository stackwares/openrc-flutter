import 'package:openrc/core/utils/app_identity.dart';
import 'package:openrc/core/utils/store_commission.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_derived.dart';
import 'package:openrc/services/commission_settings_store.dart';

/// What a subscription is expected to do when its current period ends.
enum UpcomingKind {
  /// Paid period ends with auto-renew on: a renewal charge.
  renewal,

  /// Free trial ends with auto-renew on: a first charge.
  trialConversion,

  /// Free trial ends with auto-renew off: no charge.
  trialEnding,

  /// Paid period ends with auto-renew off: the subscription lapses.
  expiring,
}

/// Charges and lapses projected from loaded transactions.
class UpcomingEvent {
  const UpcomingEvent({
    required this.source,
    required this.kind,
    required this.dueAt,
    required this.amountUsd,
  });

  /// The subscription's latest loaded transaction.
  final RcTransaction source;
  final UpcomingKind kind;

  /// Local instant the current period ends (or a later repeat of it).
  final DateTime dueAt;

  /// Gross USD expected to be charged ([UpcomingKind.renewal],
  /// [UpcomingKind.trialConversion]) or lost ([UpcomingKind.expiring]).
  /// Null when the product's price isn't known from loaded transactions.
  /// Always null for [UpcomingKind.trialEnding].
  final double? amountUsd;

  /// Counts toward the expected total.
  bool get isCharge =>
      kind == UpcomingKind.renewal || kind == UpcomingKind.trialConversion;

  /// Counts toward revenue at risk.
  bool get isAtRisk =>
      kind == UpcomingKind.expiring || kind == UpcomingKind.trialEnding;
}

/// Shortest repeat interval projected for one subscription. Shorter
/// periods (sandbox-style minutes) are shown once.
const _minRepeatPeriod = Duration(days: 1);

/// Every renewal, conversion and lapse due after [now] and no later than
/// [now] + [horizon], soonest first.
///
/// Each subscription (subscriber + app) is projected from its newest loaded
/// transaction, so a later renewal, upgrade or refund replaces older rows.
/// Renewals repeat inside the window (a weekly plan renews four times in 30
/// days); conversions and lapses happen once.
List<UpcomingEvent> projectUpcoming(
  Iterable<RcTransaction> transactions, {
  required DateTime now,
  required Duration horizon,
}) {
  final end = now.add(horizon);
  final latest = <String, RcTransaction>{};
  final listPrices = _ListPrices();
  for (final tx in transactions) {
    listPrices.add(tx);
    final key = _subscriptionKey(tx);
    if (key == null) continue;
    final current = latest[key];
    if (current == null || _isNewer(tx, current)) latest[key] = tx;
  }

  final out = <UpcomingEvent>[];
  for (final tx in latest.values) {
    if (tx.wasRefunded == true || tx.isSandbox == true) continue;
    if (tx.type == RcTransactionType.oneTimePurchase) continue;
    final expires = tx.expiresLocalInstant;
    if (expires == null || !expires.isAfter(now) || expires.isAfter(end)) {
      continue;
    }
    final cancelled = _isCancelled(tx);
    final isTrial = tx.type == RcTransactionType.trial;
    if (isTrial) {
      out.add(
        UpcomingEvent(
          source: tx,
          kind: cancelled
              ? UpcomingKind.trialEnding
              : UpcomingKind.trialConversion,
          dueAt: expires,
          amountUsd: cancelled ? null : listPrices.priceFor(tx),
        ),
      );
      continue;
    }

    final paid = tx.revenue;
    final price = tx.isInIntroductoryPricePeriod == true
        ? listPrices.priceFor(tx) ?? _positive(paid)
        : _positive(paid) ?? listPrices.priceFor(tx);
    if (cancelled) {
      out.add(
        UpcomingEvent(
          source: tx,
          kind: UpcomingKind.expiring,
          dueAt: expires,
          amountUsd: price,
        ),
      );
      continue;
    }

    final purchased = tx.purchaseLocalInstant;
    final period = purchased == null ? null : expires.difference(purchased);
    var due = expires;
    while (!due.isAfter(end)) {
      out.add(
        UpcomingEvent(
          source: tx,
          kind: UpcomingKind.renewal,
          dueAt: due,
          amountUsd: price,
        ),
      );
      if (period == null || period < _minRepeatPeriod) break;
      due = _addPeriod(due, period);
    }
  }
  out.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return out;
}

/// Totals for one set of [UpcomingEvent]s.
class UpcomingSummary {
  const UpcomingSummary({
    required this.expectedUsd,
    required this.atRiskUsd,
    required this.renewals,
    required this.trialConversions,
    required this.trialsEnding,
    required this.expiring,
    required this.unpriced,
  });

  factory UpcomingSummary.of(
    Iterable<UpcomingEvent> events, {
    CommissionSettings? commission,
  }) {
    double amount(UpcomingEvent e) {
      final gross = e.amountUsd ?? 0;
      if (commission == null) return gross;
      return adjustUsdForDisplay(
        gross: gross,
        settings: commission,
        store: e.source.storeForCommission,
      );
    }

    var expected = 0.0;
    var atRisk = 0.0;
    var renewals = 0;
    var conversions = 0;
    var trialsEnding = 0;
    var expiring = 0;
    var unpriced = 0;
    for (final e in events) {
      switch (e.kind) {
        case UpcomingKind.renewal:
          renewals++;
        case UpcomingKind.trialConversion:
          conversions++;
        case UpcomingKind.trialEnding:
          trialsEnding++;
        case UpcomingKind.expiring:
          expiring++;
      }
      if (e.kind != UpcomingKind.trialEnding && e.amountUsd == null) {
        unpriced++;
      }
      if (e.isCharge) expected += amount(e);
      if (e.kind == UpcomingKind.expiring) atRisk += amount(e);
    }
    return UpcomingSummary(
      expectedUsd: expected,
      atRiskUsd: atRisk,
      renewals: renewals,
      trialConversions: conversions,
      trialsEnding: trialsEnding,
      expiring: expiring,
      unpriced: unpriced,
    );
  }

  /// Renewals and trial conversions, after store fees when a commission
  /// setting was given.
  final double expectedUsd;

  /// Paid subscriptions set to lapse, after store fees when given.
  final double atRiskUsd;
  final int renewals;
  final int trialConversions;
  final int trialsEnding;
  final int expiring;

  /// Charges and lapses whose price isn't known from loaded transactions.
  final int unpriced;

  int get total => renewals + trialConversions + trialsEnding + expiring;
}

/// Purchase-date windows (inclusive local days) that hold the transactions
/// whose current period ends within [horizon] of [now].
///
/// A plan of length P renews inside the window when it was bought between
/// `now - P` and `now - P + horizon`. The first window covers weekly and
/// monthly plans and trials; the others cover 2-, 3- and 6-month and annual
/// plans. Each is padded a few days for calendar-month and time-zone drift,
/// and overlapping windows are merged. Newest first.
List<UpcomingWindow> upcomingFetchWindows({
  required DateTime now,
  required Duration horizon,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final horizonDays = horizon.inDays + 1;
  const pad = 3;
  final windows = <UpcomingWindow>[
    UpcomingWindow(
      start: today.subtract(const Duration(days: 31 + pad)),
      end: today,
    ),
    for (final months in const [2, 3, 6, 12])
      () {
        final anchor = DateTime(today.year, today.month - months, today.day);
        return UpcomingWindow(
          start: anchor.subtract(const Duration(days: pad)),
          end: anchor.add(Duration(days: horizonDays + pad)),
        );
      }(),
  ];
  windows.sort((a, b) => b.end.compareTo(a.end));
  final merged = <UpcomingWindow>[];
  for (final w in windows) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null && !w.end.isBefore(last.start.subtract(_oneDay))) {
      merged[merged.length - 1] = UpcomingWindow(
        start: w.start.isBefore(last.start) ? w.start : last.start,
        end: last.end,
      );
    } else {
      merged.add(w);
    }
  }
  return merged;
}

const _oneDay = Duration(days: 1);

/// Inclusive local-day purchase range for one `/me/transactions` sweep.
class UpcomingWindow {
  const UpcomingWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is UpcomingWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'UpcomingWindow($start – $end)';
}

String? _subscriptionKey(RcTransaction tx) {
  final sid = tx.subscriberId?.trim();
  if (sid == null || sid.isEmpty) return null;
  return '$sid|${appKeyForTransaction(tx)}';
}

bool _isNewer(RcTransaction a, RcTransaction b) {
  final pa = a.purchaseLocalInstant;
  final pb = b.purchaseLocalInstant;
  if (pa == null) return false;
  if (pb == null) return true;
  if (pa != pb) return pa.isAfter(pb);
  // Same instant (a refund row beside its charge): prefer the later expiry.
  final ea = a.expiresLocalInstant;
  final eb = b.expiresLocalInstant;
  if (ea == null) return false;
  return eb == null || ea.isAfter(eb);
}

bool _isCancelled(RcTransaction tx) {
  if (tx.isAutoRenewing == false) return true;
  final unsub = tx.unsubscribeDetectedAt?.trim();
  if (unsub != null && unsub.isNotEmpty) return true;
  final cancel = tx.cancellationDate?.trim();
  return cancel != null && cancel.isNotEmpty;
}

double? _positive(double? v) => v != null && v > 0.005 ? v : null;

/// Steps [from] by [period], keeping calendar months and years aligned when
/// the period is one (28–31 days, or 365–366).
DateTime _addPeriod(DateTime from, Duration period) {
  final days = period.inHours / 24;
  int? months;
  if (days >= 27.5 && days <= 31.5) months = 1;
  if (days >= 364.5 && days <= 366.5) months = 12;
  if (months == null) return from.add(period);
  return DateTime(
    from.year,
    from.month + months,
    from.day,
    from.hour,
    from.minute,
    from.second,
  );
}

/// Full (non-trial, non-intro) price per product, from the newest paid row.
class _ListPrices {
  final _byStoreProduct = <String, (DateTime, double)>{};
  final _byProduct = <String, (DateTime, double)>{};

  void add(RcTransaction tx) {
    final product = tx.productIdentifier?.trim();
    if (product == null || product.isEmpty) return;
    if (tx.wasRefunded == true ||
        tx.isTrialPeriod == true ||
        tx.isInIntroductoryPricePeriod == true) {
      return;
    }
    final revenue = _positive(tx.revenue);
    final at = tx.purchaseLocalInstant;
    if (revenue == null || at == null) return;
    void put(Map<String, (DateTime, double)> map, String key) {
      final current = map[key];
      if (current == null || at.isAfter(current.$1)) map[key] = (at, revenue);
    }

    put(_byStoreProduct, '${tx.store}|$product');
    put(_byProduct, product);
  }

  double? priceFor(RcTransaction tx) {
    final product = tx.productIdentifier?.trim();
    if (product == null || product.isEmpty) return null;
    return (_byStoreProduct['${tx.store}|$product'] ?? _byProduct[product])?.$2;
  }
}
