import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/payout_detail_provider.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordedRequest {
  const _RecordedRequest({this.startDate, this.endDate, this.startFrom});

  final String? startDate;
  final String? endDate;
  final int? startFrom;
}

class _PagingApi extends RcApiService {
  _PagingApi(this.pages);

  final List<RcTransactionsResponse> pages;
  final requests = <_RecordedRequest>[];

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    requests.add(
      _RecordedRequest(
        startDate: request.startDate,
        endDate: request.endDate,
        startFrom: request.startFrom,
      ),
    );
    if (requests.length > pages.length) {
      return const RcTransactionsResponse(transactions: []);
    }
    return pages[requests.length - 1];
  }
}

class _FailingApi extends RcApiService {
  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/me/transactions'),
      type: DioExceptionType.connectionError,
    );
  }
}

class _CappedApi extends RcApiService {
  int pages = 0;

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    pages++;
    return RcTransactionsResponse(
      lastPurchaseMs: 2_000_000_000 - pages,
      transactions: [
        RcTransaction(
          store: 'App Store',
          revenue: 1,
          purchaseDate: DateTime(2026, 8, 29, 12).toIso8601String(),
          storeTransactionIdentifier: 'p$pages',
        ),
      ],
    );
  }
}

class _SeededTransactions extends TransactionsNotifier {
  _SeededTransactions(super.ref, Map<String, List<RcTransaction>> grouped) {
    state = TransactionsState(selectedDayKey: '2026-10-23', grouped: grouped);
  }
}

RcTransaction _tx({
  required String store,
  required DateTime day,
  double revenue = 10,
  required String id,
}) => RcTransaction(
  store: store,
  revenue: revenue,
  purchaseDate: DateTime(day.year, day.month, day.day, 12).toIso8601String(),
  storeTransactionIdentifier: id,
);

PayoutPeriod get _apple => PayoutPeriod(
  store: PayoutStore.apple,
  earningsStart: DateTime(2026, 8, 2),
  earningsEnd: DateTime(2026, 8, 29),
  paymentDate: DateTime(2026, 10, 1),
);

ProviderContainer _container({
  required RcApiService api,
  Map<String, List<RcTransaction>> grouped = const {},
}) {
  final container = ProviderContainer(
    overrides: [
      rcApiServiceProvider.overrideWithValue(api),
      transactionsProvider.overrideWith(
        (ref) => _SeededTransactions(ref, grouped),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first request uses the earnings window dates', () async {
    final api = _PagingApi(const [RcTransactionsResponse(transactions: [])]);
    final container = _container(api: api);
    await container
        .read(payoutDetailTransactionsProvider(_apple).notifier)
        .loaded;

    expect(api.requests, hasLength(1));
    expect(api.requests.single.startDate, '2026-08-02');
    expect(api.requests.single.endDate, '2026-08-29');
    expect(api.requests.single.startFrom, isNull);
  });

  test('paginates until a page is older than the earnings start', () async {
    final api = _PagingApi([
      RcTransactionsResponse(
        lastPurchaseMs: 100,
        transactions: [
          _tx(store: 'App Store', day: DateTime(2026, 8, 29), id: 'late'),
        ],
      ),
      RcTransactionsResponse(
        lastPurchaseMs: 50,
        transactions: [
          _tx(store: 'App Store', day: DateTime(2026, 8, 1), id: 'early'),
        ],
      ),
    ]);
    final container = _container(api: api);
    final sub = container.listen(
      payoutDetailTransactionsProvider(_apple),
      (_, _) {},
    );
    await container
        .read(payoutDetailTransactionsProvider(_apple).notifier)
        .loaded;

    expect(api.requests, hasLength(2));
    expect(api.requests[1].startFrom, 100);
    expect(sub.read().transactions.map((t) => t.storeTransactionIdentifier), [
      'late',
    ]);
    expect(sub.read().loadComplete, isTrue);
  });

  test(
    'seeds matching loaded transactions and keeps other stores out',
    () async {
      final api = _PagingApi(const [RcTransactionsResponse(transactions: [])]);
      final container = _container(
        api: api,
        grouped: {
          '2026-08-02': [
            _tx(
              store: 'App Store',
              day: DateTime(2026, 8, 2),
              id: 'seed-apple',
            ),
            _tx(
              store: 'Play Store',
              day: DateTime(2026, 8, 2),
              id: 'seed-google',
            ),
          ],
        },
      );
      final sub = container.listen(
        payoutDetailTransactionsProvider(_apple),
        (_, _) {},
      );
      await container
          .read(payoutDetailTransactionsProvider(_apple).notifier)
          .loaded;

      expect(sub.read().transactions.map((t) => t.storeTransactionIdentifier), [
        'seed-apple',
      ]);
      expect(
        container.read(transactionsProvider).grouped['2026-08-02'],
        hasLength(2),
      );
    },
  );

  test('stops after the Revenue backfill page cap', () async {
    final api = _CappedApi();
    final container = _container(api: api);
    final sub = container.listen(
      payoutDetailTransactionsProvider(_apple),
      (_, _) {},
    );
    await container
        .read(payoutDetailTransactionsProvider(_apple).notifier)
        .loaded;

    expect(api.pages, kRealtimeBackfillMaxPages);
    expect(sub.read().transactions, hasLength(kRealtimeBackfillMaxPages));
    expect(sub.read().loadComplete, isTrue);
  });

  test('a failed fetch keeps the seed and reports the error', () async {
    final container = _container(
      api: _FailingApi(),
      grouped: {
        '2026-08-02': [
          _tx(store: 'App Store', day: DateTime(2026, 8, 2), id: 'seed'),
        ],
      },
    );
    final sub = container.listen(
      payoutDetailTransactionsProvider(_apple),
      (_, _) {},
    );
    await container
        .read(payoutDetailTransactionsProvider(_apple).notifier)
        .loaded;

    expect(sub.read().transactions, hasLength(1));
    expect(sub.read().error, isNotNull);
    expect(sub.read().loadComplete, isTrue);
  });
}
