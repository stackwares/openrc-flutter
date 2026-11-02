import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/upcoming/upcoming_projection.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';

final _now = DateTime(2026, 11, 2, 12);

RcTransaction _tx({
  required String id,
  String subscriber = 's1',
  String product = 'pro.monthly',
  String store = 'App Store',
  required DateTime purchased,
  required DateTime expires,
  double revenue = 9.99,
  bool trial = false,
  bool intro = false,
  bool renewal = false,
  bool autoRenew = true,
  bool refunded = false,
  String? unsubscribed,
}) => RcTransaction(
  app: const RcTransactionApp(id: 'app1', name: 'App'),
  subscriberId: subscriber,
  productIdentifier: product,
  store: store,
  storeTransactionIdentifier: id,
  purchaseDate: purchased.toIso8601String(),
  expiresDate: expires.toIso8601String(),
  revenue: trial ? 0 : revenue,
  isTrialPeriod: trial,
  isInIntroductoryPricePeriod: intro,
  isRenewal: renewal,
  isAutoRenewing: autoRenew,
  wasRefunded: refunded,
  unsubscribeDetectedAt: unsubscribed,
);

List<UpcomingEvent> _project(List<RcTransaction> txs, {int days = 7}) =>
    projectUpcoming(
      txs,
      now: _now,
      horizon: Duration(days: days),
    );

void main() {
  test('auto-renewing paid plan due in the window is a renewal', () {
    final events = _project([
      _tx(
        id: 'a',
        purchased: DateTime(2026, 10, 5, 9),
        expires: DateTime(2026, 11, 5, 9),
      ),
    ]);
    expect(events, hasLength(1));
    expect(events.single.kind, UpcomingKind.renewal);
    expect(events.single.amountUsd, 9.99);
    expect(events.single.dueAt, DateTime(2026, 11, 5, 9));
  });

  test('periods ending outside the window or already past are skipped', () {
    final events = _project([
      _tx(
        id: 'late',
        subscriber: 'a',
        purchased: DateTime(2026, 10, 20),
        expires: DateTime(2026, 11, 20),
      ),
      _tx(
        id: 'past',
        subscriber: 'b',
        purchased: DateTime(2026, 10, 1),
        expires: DateTime(2026, 11, 1),
      ),
    ]);
    expect(events, isEmpty);
  });

  test('trial with auto-renew converts at the product list price', () {
    final events = _project([
      _tx(
        id: 'paid',
        subscriber: 'other',
        purchased: DateTime(2026, 10, 1),
        expires: DateTime(2026, 10, 2),
        revenue: 12.99,
      ),
      _tx(
        id: 't',
        trial: true,
        purchased: DateTime(2026, 10, 30),
        expires: DateTime(2026, 11, 6),
      ),
    ]);
    expect(events.single.kind, UpcomingKind.trialConversion);
    expect(events.single.amountUsd, 12.99);
  });

  test('trial with no known paid price has a null amount', () {
    final events = _project([
      _tx(
        id: 't',
        trial: true,
        purchased: DateTime(2026, 10, 30),
        expires: DateTime(2026, 11, 6),
      ),
    ]);
    expect(events.single.kind, UpcomingKind.trialConversion);
    expect(events.single.amountUsd, isNull);
    expect(UpcomingSummary.of(events).unpriced, 1);
  });

  test('cancelled trial ends without a charge', () {
    final events = _project([
      _tx(
        id: 't',
        trial: true,
        autoRenew: false,
        purchased: DateTime(2026, 10, 30),
        expires: DateTime(2026, 11, 6),
      ),
    ]);
    expect(events.single.kind, UpcomingKind.trialEnding);
    expect(events.single.amountUsd, isNull);
  });

  test('paid plan with renewal off is expiring revenue at risk', () {
    final events = _project([
      _tx(
        id: 'a',
        unsubscribed: '2026-10-20T00:00:00Z',
        purchased: DateTime(2026, 10, 5),
        expires: DateTime(2026, 11, 5),
      ),
    ]);
    expect(events.single.kind, UpcomingKind.expiring);
    final summary = UpcomingSummary.of(events);
    expect(summary.atRiskUsd, closeTo(9.99, 1e-9));
    expect(summary.expectedUsd, 0);
  });

  test('intro price renews at the full price', () {
    final events = _project([
      _tx(
        id: 'full',
        subscriber: 'other',
        purchased: DateTime(2026, 9, 1),
        expires: DateTime(2026, 10, 1),
        revenue: 9.99,
      ),
      _tx(
        id: 'intro',
        intro: true,
        revenue: 0.99,
        purchased: DateTime(2026, 10, 5),
        expires: DateTime(2026, 11, 5),
      ),
    ]);
    final renewal = events.singleWhere((e) => e.source.subscriberId == 's1');
    expect(renewal.amountUsd, 9.99);
  });

  test('weekly plan repeats inside a 30-day window', () {
    final events = _project([
      _tx(
        id: 'w',
        product: 'pro.weekly',
        revenue: 2.99,
        purchased: DateTime(2026, 10, 29, 8),
        expires: DateTime(2026, 11, 5, 8),
      ),
    ], days: 30);
    expect(events.map((e) => e.dueAt), [
      DateTime(2026, 11, 5, 8),
      DateTime(2026, 11, 12, 8),
      DateTime(2026, 11, 19, 8),
      DateTime(2026, 11, 26, 8),
    ]);
  });

  test('monthly repeats keep the calendar day', () {
    final events = projectUpcoming(
      [
        _tx(
          id: 'm',
          purchased: DateTime(2026, 10, 3, 8),
          expires: DateTime(2026, 11, 3, 8),
        ),
      ],
      now: _now,
      horizon: const Duration(days: 45),
    );
    expect(events.map((e) => e.dueAt), [
      DateTime(2026, 11, 3, 8),
      DateTime(2026, 12, 3, 8),
    ]);
  });

  test('newest transaction per subscription wins', () {
    final events = _project([
      _tx(
        id: 'old',
        purchased: DateTime(2025, 11, 4),
        expires: DateTime(2026, 11, 4),
        product: 'pro.annual',
        revenue: 59.99,
      ),
      // Switched to monthly last week: the annual row no longer renews.
      _tx(
        id: 'new',
        purchased: DateTime(2026, 10, 25),
        expires: DateTime(2026, 11, 25),
      ),
    ]);
    expect(events, isEmpty);
  });

  test('refunded, sandbox and lifetime rows never project', () {
    final events = _project([
      _tx(
        id: 'r',
        subscriber: 'a',
        refunded: true,
        purchased: DateTime(2026, 10, 5),
        expires: DateTime(2026, 11, 5),
      ),
      RcTransaction(
        subscriberId: 'b',
        productIdentifier: 'lifetime',
        store: 'App Store',
        purchaseDate: DateTime(2026, 10, 5).toIso8601String(),
        revenue: 99,
      ),
    ]);
    expect(events, isEmpty);
  });

  test('summary applies store fees when enabled', () {
    final events = _project([
      _tx(
        id: 'a',
        revenue: 10,
        purchased: DateTime(2026, 10, 5),
        expires: DateTime(2026, 11, 5),
      ),
    ]);
    final summary = UpcomingSummary.of(
      events,
      commission: const CommissionSettings(
        adjustmentEnabled: true,
        appleCommissionPercent: 15,
        googleCommissionPercent: 15,
      ),
    );
    expect(summary.expectedUsd, closeTo(8.5, 1e-9));
    expect(summary.renewals, 1);
  });

  group('upcomingFetchWindows', () {
    test('covers recent plans and each longer plan length', () {
      final windows = upcomingFetchWindows(
        now: _now,
        horizon: const Duration(days: 30),
      );
      bool covers(DateTime day) =>
          windows.any((w) => !day.isBefore(w.start) && !day.isAfter(w.end));
      // Monthly due in 30 days, annual due today and in 30 days.
      expect(covers(DateTime(2026, 10, 2)), isTrue);
      expect(covers(DateTime(2025, 11, 2)), isTrue);
      expect(covers(DateTime(2025, 12, 2)), isTrue);
      // Six-month plan due in 2 weeks.
      expect(covers(DateTime(2026, 5, 16)), isTrue);
      // Nothing due from a 9-month-old purchase.
      expect(covers(DateTime(2026, 2, 1)), isFalse);
    });

    test('windows are newest first and do not overlap', () {
      final windows = upcomingFetchWindows(
        now: _now,
        horizon: const Duration(days: 30),
      );
      for (var i = 1; i < windows.length; i++) {
        expect(windows[i].end.isBefore(windows[i - 1].start), isTrue);
      }
    });
  });
}
