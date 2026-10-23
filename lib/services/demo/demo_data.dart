import 'dart:math';

/// Made-up RevenueCat data for demo builds (`--dart-define=OPENRC_DEMO=true`).
///
/// A fictional studio with four apps and a healthy, growing business. It is
/// generated from fixed seeds relative to today, so every run looks alike and
/// nothing here is real account data.
class DemoData {
  DemoData._() {
    _buildTransactions();
  }

  static final DemoData instance = DemoData._();

  static const mrr = 184260.0;
  static const _historyDays = 60;

  static const projects = [
    DemoApp('proj_lumen', 'Lumen Habits', 'studio.demo.lumenhabits', 0.38),
    DemoApp('proj_pilot', 'Pixel Pilot', 'studio.demo.pixelpilot', 0.27),
    DemoApp('proj_dose', 'Daily Dose', 'studio.demo.dailydose', 0.21),
    DemoApp('proj_tidy', 'Tidy Notes', 'studio.demo.tidynotes', 0.14),
  ];

  static const _prices = [
    _Price(4.99, 'weekly', 0.06),
    _Price(9.99, 'monthly', 0.28),
    _Price(14.99, 'monthly_plus', 0.15),
    _Price(29.99, 'quarterly', 0.10),
    _Price(49.99, 'annual_lite', 0.12),
    _Price(59.99, 'annual', 0.17),
    _Price(79.99, 'annual_plus', 0.08),
    _Price(99.99, 'lifetime', 0.04),
  ];

  static const _countries = [
    ('US', 0.34),
    ('GB', 0.09),
    ('DE', 0.08),
    ('JP', 0.08),
    ('CA', 0.06),
    ('FR', 0.06),
    ('AU', 0.05),
    ('BR', 0.05),
    ('KR', 0.05),
    ('ES', 0.04),
    ('MX', 0.04),
    ('IN', 0.03),
    ('SE', 0.03),
  ];

  final List<Map<String, dynamic>> transactions = [];
  final List<DateTime> _purchaseTimes = [];
  final Map<int, double> _dayRevenue = {};
  final Map<int, int> _dayCount = {};

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  void _buildTransactions() {
    final now = DateTime.now();
    final today = _midnight(now);
    for (var back = 0; back < _historyDays; back++) {
      final day = DateTime(today.year, today.month, today.day - back);
      final rng = Random(7000 + back);
      final weekdayLift = const [1.0, 1.04, 1.02, 0.98, 1.0, 0.92, 0.88][
          day.weekday - 1];
      final trend = 1 - 0.18 * (back / _historyDays);
      final count = back == 0
          ? 232
          : (176 * weekdayLift * trend + rng.nextInt(12)).round();
      final end = back == 0 ? now : day.add(const Duration(hours: 24));
      final spanMs = max(end.difference(day).inMilliseconds, 3600 * 1000);
      for (var i = 0; i < count; i++) {
        final at = day.add(Duration(milliseconds: rng.nextInt(spanMs)));
        final tx = _transaction(rng, at);
        transactions.add(tx);
        final revenue = (tx['revenue'] as num).toDouble();
        _dayRevenue[back] = (_dayRevenue[back] ?? 0) + revenue;
        _dayCount[back] = (_dayCount[back] ?? 0) + 1;
      }
    }
    transactions.sort(
      (a, b) =>
          (b['_ms'] as int).compareTo(a['_ms'] as int),
    );
    _purchaseTimes.addAll(
      transactions.map(
        (t) => DateTime.fromMillisecondsSinceEpoch(t['_ms'] as int),
      ),
    );
  }

  Map<String, dynamic> _transaction(Random rng, DateTime at) {
    final app = _pick(rng, [for (final p in projects) (p, p.share)]);
    final price = _pick(rng, [for (final p in _prices) (p, p.weight)]);
    final country = _pick(rng, [for (final c in _countries) (c.$1, c.$2)]);
    final storeRoll = rng.nextDouble();
    final store = storeRoll < 0.62
        ? 'App Store'
        : storeRoll < 0.96
        ? 'Play Store'
        : 'Stripe';
    final kind = rng.nextDouble();
    var renewal = false;
    var trial = false;
    var conversion = false;
    var refund = false;
    if (price.id == 'lifetime') {
      // One-time purchase.
    } else if (kind < 0.54) {
      renewal = true;
    } else if (kind < 0.74) {
      // New subscription.
    } else if (kind < 0.87) {
      trial = true;
    } else if (kind < 0.985) {
      conversion = true;
    } else {
      refund = true;
    }
    final revenue = trial
        ? 0.0
        : refund
        ? -price.amount
        : price.amount;
    final platform = store == 'Play Store'
        ? 'Android'
        : rng.nextDouble() < 0.85
        ? 'iOS'
        : 'macOS';
    final subscriber =
        '\$RCAnonymousID:${rng.nextInt(1 << 30).toRadixString(16)}'
        '${rng.nextInt(1 << 30).toRadixString(16)}';
    final iso = at.toUtc().toIso8601String();
    return {
      '_ms': at.millisecondsSinceEpoch,
      'app': {'bundle_id': app.bundleId, 'id': app.id, 'name': app.name},
      'is_auto_renewing': !refund,
      'is_in_introductory_price_period': trial,
      'is_renewal': renewal,
      'is_sandbox': false,
      'is_trial_conversion': conversion,
      'is_trial_period': trial,
      'product_identifier': '${app.bundleId.split('.').last}.${price.id}',
      'purchase_date': iso,
      'expires_date': at
          .add(Duration(days: price.id.contains('annual') ? 365 : 30))
          .toUtc()
          .toIso8601String(),
      'revenue': double.parse(revenue.toStringAsFixed(2)),
      'store': store,
      'store_transaction_identifier': '${rng.nextInt(1 << 31)}',
      'subscriber_country_code': country,
      'subscriber_created_at': at
          .subtract(Duration(days: renewal ? 30 + rng.nextInt(500) : 0))
          .toUtc()
          .toIso8601String(),
      'subscriber_id': subscriber,
      'subscriber_last_seen_platform': platform,
      'was_refunded': refund,
    };
  }

  static T _pick<T>(Random rng, List<(T, double)> weighted) {
    final total = weighted.fold<double>(0, (s, e) => s + e.$2);
    var roll = rng.nextDouble() * total;
    for (final (item, weight) in weighted) {
      roll -= weight;
      if (roll <= 0) return item;
    }
    return weighted.last.$1;
  }

  /// One page of transactions, newest first, strictly older than
  /// [startFromMs] when given.
  Map<String, dynamic> transactionsPage({int limit = 20, int? startFromMs}) {
    final page = <Map<String, dynamic>>[];
    for (final t in transactions) {
      final ms = t['_ms'] as int;
      if (startFromMs != null && ms >= startFromMs) continue;
      page.add(t);
      if (page.length >= limit) break;
    }
    return {
      if (transactions.isNotEmpty)
        'first_purchase_ms': transactions.last['_ms'],
      if (page.isNotEmpty) 'last_purchase_ms': page.last['_ms'],
      'transactions': [
        for (final t in page)
          {
            for (final e in t.entries)
              if (!e.key.startsWith('_')) e.key: e.value,
          },
      ],
    };
  }

  // Charts ------------------------------------------------------------------

  /// Growth multiplier at [back] days ago: the business is up ~42% on the
  /// year, so a year ago it sat near 0.70 of today.
  static double growth(int back) => 1 - 0.30 * (back / 365);

  double revenueOn(int back) {
    final known = _dayRevenue[back];
    if (known != null) return known;
    final lastKnown = _dayRevenue[_historyDays - 1] ?? 6000;
    final rng = Random(900 + back);
    return lastKnown *
        growth(back) /
        growth(_historyDays - 1) *
        (0.94 + rng.nextDouble() * 0.12);
  }

  int countOn(int back) =>
      _dayCount[back] ?? (revenueOn(back) / 35).round();

  /// Daily points for a `charts_v2/<name>` series between [start] and [end].
  Map<String, dynamic> chart(
    String name,
    DateTime start,
    DateTime end, {
    String? revenueType,
    double storeShare = 1,
  }) {
    final today = _midnight(DateTime.now());
    final values = <Map<String, dynamic>>[];
    var revenueTotal = 0.0;
    var countTotal = 0;
    void add(DateTime day, int measure, double value) => values.add({
      'cohort': DateTime.utc(day.year, day.month, day.day)
              .millisecondsSinceEpoch ~/
          1000,
      'measure': measure,
      'value': value,
    });

    for (
      var day = _midnight(start);
      !day.isAfter(_midnight(end));
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final back = max(today.difference(day).inDays, 0);
      final g = growth(back);
      final rng = Random(back * 31 + name.length);
      final wobble = 0.9985 + rng.nextDouble() * 0.003;
      final rev = revenueOn(back) * storeShare;
      switch (name) {
        case 'mrr':
          add(day, 0, mrr * g * wobble);
        case 'arr':
          add(day, 0, mrr * 12 * g * wobble);
        case 'actives':
          add(day, 0, 612400 * g * wobble);
        case 'trials':
          add(day, 0, 1942 * (0.62 + 0.38 * g) * (0.995 + rng.nextDouble() * 0.01));
        case 'customers_new':
          add(day, 0, 9115 / 28 * g * (0.9 + rng.nextDouble() * 0.2));
        case 'churn':
          add(day, 1, 520 * (2 - g) * (0.94 + rng.nextDouble() * 0.12));
          add(day, 2, 2.4 + (1 - g) * 2 + rng.nextDouble() * 0.06);
        case 'revenue':
          final proceeds = revenueType == 'proceeds';
          final amount = rev * (proceeds ? 0.84 : 1);
          add(day, 0, double.parse(amount.toStringAsFixed(2)));
          add(day, 1, (countOn(back) * storeShare).roundToDouble());
          revenueTotal += amount;
          countTotal += (countOn(back) * storeShare).round();
        default:
          add(day, 0, 0);
      }
    }
    return {
      'values': values,
      if (name == 'revenue')
        'summary': {
          'total': {
            'Revenue': revenueTotal,
            'Proceeds': revenueTotal,
            'Transactions': countTotal,
          },
        },
      'last_computed_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> overview() {
    var revenue28 = 0.0;
    for (var back = 0; back < 28; back++) {
      revenue28 += revenueOn(back);
    }
    return {
      'metrics': [
        {'id': 'mrr', 'value': mrr},
        {'id': 'active_subscriptions', 'value': 28640},
        {'id': 'active_trials', 'value': 1942},
        {'id': 'revenue', 'value': revenue28},
        {'id': 'active_users', 'value': 612400},
        {'id': 'new_customers', 'value': 9115},
      ],
    };
  }
}

class DemoApp {
  const DemoApp(this.id, this.name, this.bundleId, this.share);

  final String id;
  final String name;
  final String bundleId;
  final double share;
}

class _Price {
  const _Price(this.amount, this.id, this.weight);

  final double amount;
  final String id;
  final double weight;
}
