import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/models/rc_transaction.dart';

RcTransaction _tx({
  required String store,
  required DateTime day,
  double revenue = 10,
  String? id,
}) => RcTransaction(
  store: store,
  revenue: revenue,
  purchaseDate: DateTime(day.year, day.month, day.day, 12).toIso8601String(),
  storeTransactionIdentifier: id,
);

void main() {
  final start = DateTime(2026, 8, 2);
  final end = DateTime(2026, 8, 29);

  test('local purchase day is inclusive at both ends', () {
    expect(
      localPurchaseDayInInclusiveRange(
        _tx(store: 'App Store', day: start),
        start,
        end,
      ),
      isTrue,
    );
    expect(
      localPurchaseDayInInclusiveRange(
        _tx(store: 'App Store', day: end),
        start,
        end,
      ),
      isTrue,
    );
    expect(
      localPurchaseDayInInclusiveRange(
        _tx(store: 'App Store', day: DateTime(2026, 8, 1)),
        start,
        end,
      ),
      isFalse,
    );
    expect(
      localPurchaseDayInInclusiveRange(
        _tx(store: 'App Store', day: DateTime(2026, 8, 30)),
        start,
        end,
      ),
      isFalse,
    );
  });

  test(
    'collectTransactionsInLocalInclusiveRange dedupes and skips bad dates',
    () {
      final inRange = _tx(store: 'App Store', day: start, id: 'a');
      final collected = collectTransactionsInLocalInclusiveRange(
        [
          inRange,
          _tx(store: 'App Store', day: start, id: 'a'),
          _tx(store: 'App Store', day: DateTime(2026, 7, 1), id: 'b'),
          const RcTransaction(store: 'App Store', revenue: 1),
        ],
        start: start,
        end: end,
      );
      expect(collected, hasLength(1));
      expect(collected.single.storeTransactionIdentifier, 'a');
    },
  );

  test('transactionsForPayout keeps that store in the earnings window', () {
    final period = PayoutPeriod(
      store: PayoutStore.apple,
      earningsStart: start,
      earningsEnd: end,
      paymentDate: DateTime(2026, 10, 1),
    );
    final kept = transactionsForPayout([
      _tx(store: 'App Store', day: start, id: 'apple'),
      _tx(store: 'mac_app_store', day: end, id: 'mac'),
      _tx(store: 'Play Store', day: start, id: 'google'),
      _tx(store: 'App Store', day: DateTime(2026, 9, 1), id: 'late'),
    ], period);
    expect(kept.map((t) => t.storeTransactionIdentifier), ['apple', 'mac']);
  });

  test('PayoutPeriod equality follows its id', () {
    final a = PayoutPeriod(
      store: PayoutStore.apple,
      earningsStart: start,
      earningsEnd: end,
      paymentDate: DateTime(2026, 10, 1),
    );
    final b = PayoutPeriod(
      store: PayoutStore.apple,
      earningsStart: start,
      earningsEnd: DateTime(2026, 8, 28),
      paymentDate: DateTime(2026, 10, 2),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
