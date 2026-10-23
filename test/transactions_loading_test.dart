import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _ms(RcTransaction t) =>
    DateTime.parse(t.purchaseDate!).millisecondsSinceEpoch;

RcTransaction _tx(String id, DateTime at) => RcTransaction(
  storeTransactionIdentifier: id,
  purchaseDate: at.toUtc().toIso8601String(),
  revenue: 1,
  store: 'App Store',
);

/// `/me/transactions` over a fixed history (newest first). The first page
/// returns the last 12 hours; later pages page back by `start_from`. One
/// later page can be held open to simulate a slow request.
class _FakeApi extends RcApiService {
  _FakeApi(this.history);

  final List<RcTransaction> history;
  bool holdNextPage = false;
  Completer<void>? held;

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    if (request.startFrom == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 12))
          .millisecondsSinceEpoch;
      return RcTransactionsResponse(
        transactions: history.where((t) => _ms(t) > cutoff).toList(),
      );
    }
    if (holdNextPage) {
      holdNextPage = false;
      held = Completer<void>();
      await held!.future;
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return RcTransactionsResponse(
      transactions: history
          .where((t) => _ms(t) <= request.startFrom!)
          .take(request.limit)
          .toList(),
    );
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime.now();
  final history = [
    for (var h = 1; h <= 3; h++)
      _tx('recent-$h', now.subtract(Duration(hours: h))),
    for (var d = 1; d <= 120; d += 7)
      _tx('day-$d', now.subtract(Duration(days: d, hours: 1))),
  ];

  ProviderContainer containerFor(_FakeApi api) {
    final c = ProviderContainer(
      overrides: [
        rcApiServiceProvider.overrideWithValue(api),
        usdExchangeRatesProvider.overrideWith((ref) async => const {}),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('a refresh during the month backfill still finishes loading', () async {
    final api = _FakeApi(history)..holdNextPage = true;
    final container = containerFor(api);
    final notifier = container.read(transactionsProvider.notifier);

    unawaited(notifier.fetchInitial());
    await _settle();
    expect(api.held, isNotNull, reason: 'first backfill page is in flight');

    // Pull to refresh while that page is still loading; the new first page
    // lands before the stale one.
    unawaited(notifier.fetchInitial());
    await _settle();
    api.held!.complete();
    await _settle();

    final state = container.read(transactionsProvider);
    expect(state.realtimeLoadComplete, isTrue);
    expect(state.isLoadingMore, isFalse);
  });

  test('stepping back to an unloaded day loads it', () async {
    final api = _FakeApi(history);
    final container = containerFor(api);
    final notifier = container.read(transactionsProvider.notifier);

    await notifier.fetchInitial();
    final target = now.subtract(const Duration(days: 64));
    final key = DateFormat('yyyy-MM-dd').format(target);
    notifier.setSelectedDayKey(key);
    await _settle();

    final state = container.read(transactionsProvider);
    expect(state.isDayFullyLoaded(key), isTrue);
  });

  test('a day is complete only once an older day has loaded', () {
    const state = TransactionsState(
      selectedDayKey: '2026-10-23',
      grouped: {'2026-10-23': [], '2026-10-20': []},
    );
    expect(state.isDayFullyLoaded('2026-10-23'), isTrue);
    expect(state.isDayFullyLoaded('2026-10-20'), isFalse);
    expect(state.isDayFullyLoaded('2026-10-01'), isFalse);
    expect(
      state.copyWith(hasMore: false).isDayFullyLoaded('2026-10-01'),
      isTrue,
    );
  });
}
