import 'dart:async';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/transactions_loading_skeleton.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/theme/app_theme.dart';
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
  final requests = <RcTransactionsRequest>[];
  bool holdNextPage = false;
  Completer<void>? held;

  /// Pages starting after this instant wait for [release]: today's pages
  /// stall while older ones (day runs) go through.
  int? holdFrom;
  final release = Completer<void>();

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    requests.add(request);
    if (request.startFrom == null) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 12))
          .millisecondsSinceEpoch;
      return RcTransactionsResponse(
        transactions: history.where((t) => _ms(t) > cutoff).toList(),
      );
    }
    if (holdFrom != null && request.startFrom! > holdFrom!) {
      await release.future;
    } else if (holdNextPage) {
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

class _Fixed extends TransactionsNotifier {
  _Fixed(super.ref, TransactionsState initial) {
    state = initial;
  }

  @override
  Future<void> fetchInitial() async {}
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

  test('reaching the end of a complete day pages in nothing', () async {
    final api = _FakeApi(history);
    final container = containerFor(api);
    final notifier = container.read(transactionsProvider.notifier);

    await notifier.fetchInitial();
    await _settle();
    final state = container.read(transactionsProvider);
    expect(state.hasMore, isTrue, reason: 'older history is still unloaded');
    expect(state.isDayFullyLoaded(state.selectedDayKey), isTrue);

    final sent = api.requests.length;
    await notifier.fetchMore();
    await _settle();
    expect(api.requests, hasLength(sent));
  });

  test('changing days while a page loads doesn’t fetch it twice', () async {
    final api = _FakeApi(history)..holdNextPage = true;
    final container = containerFor(api);
    final notifier = container.read(transactionsProvider.notifier);

    unawaited(notifier.fetchInitial());
    await _settle();
    expect(api.held, isNotNull, reason: 'first backfill page is in flight');

    // The day just past what's loaded pages back from today too.
    final oldest = DateFormat(
      'yyyy-MM-dd',
    ).parse(container.read(transactionsProvider).oldestLoadedDayKey!);
    final edge = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(oldest.year, oldest.month, oldest.day - 1));
    notifier.setSelectedDayKey(edge);
    await _settle();
    api.held!.complete();
    await _settle();

    final cursors = api.requests.map((r) => r.startFrom).nonNulls.toList();
    expect(cursors.toSet(), hasLength(cursors.length));
    expect(container.read(transactionsProvider).isDayFullyLoaded(edge), isTrue);
  });

  testWidgets('a complete day shows no loading rows under its list', (
    tester,
  ) async {
    // Tall enough to build the end of the list.
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = localTodayDayKey();
    final yesterday = DateFormat('yyyy-MM-dd').format(
      DateTime(now.year, now.month, now.day - 1),
    );
    // The Revenue tab's month backfill is still paging older days.
    final state = TransactionsState(
      selectedDayKey: today,
      isLoadingMore: true,
      grouped: {
        today: [_tx('today', now)],
        yesterday: [_tx('yesterday', now.subtract(const Duration(days: 1)))],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsProvider.overrideWith((ref) => _Fixed(ref, state)),
          rcAccountProjectsProvider.overrideWith((ref) async => const []),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(TransactionRowsSkeleton), findsNothing);
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

  test('a day far back loads on its own, apart from today’s pages', () async {
    final api = _FakeApi(
      history,
    )..holdFrom = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final container = containerFor(api);
    final notifier = container.read(transactionsProvider.notifier);

    await notifier.fetchInitial();
    await _settle();

    final day = now.subtract(const Duration(days: 99, hours: 1));
    final key = DateFormat('yyyy-MM-dd').format(day);
    notifier.setSelectedDayKey(key);
    await _settle();

    final state = container.read(transactionsProvider);
    expect(state.isDayFullyLoaded(key), isTrue);
    expect(state.dayView[key], isNotEmpty);
    expect(
      state.grouped.containsKey(key),
      isFalse,
      reason: 'month totals only ever see pages back from today',
    );
    final endOfDay =
        DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch - 1;
    expect(api.requests.map((r) => r.startFrom), contains(endOfDay));

    // The day before came with the same page; the day after starts a run.
    String keyFor(int offset) => DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(day.year, day.month, day.day + offset));
    final sent = api.requests.length;
    notifier.setSelectedDayKey(keyFor(-1));
    await _settle();
    expect(
      container.read(transactionsProvider).isDayFullyLoaded(keyFor(-1)),
      isTrue,
    );
    expect(api.requests, hasLength(sent));

    notifier.setSelectedDayKey(keyFor(1));
    await _settle();
    expect(
      container.read(transactionsProvider).isDayFullyLoaded(keyFor(1)),
      isTrue,
    );

    api.release.complete();
    await _settle();
  });

  test('a day run covers its top down to its partial oldest day', () {
    const run = TransactionsDayRun(
      topDayKey: '2026-05-10',
      cursor: 1,
      oldestDayKey: '2026-05-03',
    );
    expect(run.covers('2026-05-10'), isTrue);
    expect(run.covers('2026-05-04'), isTrue);
    expect(run.covers('2026-05-03'), isFalse, reason: 'may be partial');
    expect(run.covers('2026-05-11'), isFalse);
    expect(run.reaches('2026-05-02'), isTrue);
    expect(run.reaches('2026-04-20'), isFalse);
    const finished = TransactionsDayRun(
      topDayKey: '2026-05-10',
      cursor: null,
      oldestDayKey: '2026-05-03',
    );
    expect(finished.covers('2020-01-01'), isTrue);

    const state = TransactionsState(
      selectedDayKey: '2026-05-08',
      grouped: {'2026-10-23': []},
      dayRuns: [run],
    );
    expect(state.isDayFullyLoaded('2026-05-08'), isTrue);
    expect(state.isDayFullyLoaded('2026-06-01'), isFalse);
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
