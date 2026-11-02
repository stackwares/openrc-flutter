import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/upcoming/upcoming_projection.dart';
import 'package:openrc/features/upcoming/upcoming_provider.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers each window's first request with [byStartDate] rows, and every
/// follow-up page with nothing.
class _WindowApi extends RcApiService {
  _WindowApi([this.byStartDate = const {}]);

  final Map<String, List<RcTransaction>> byStartDate;
  final requests = <RcTransactionsRequest>[];

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    requests.add(request);
    if (request.startFrom != null) {
      return const RcTransactionsResponse(transactions: []);
    }
    return RcTransactionsResponse(
      transactions: byStartDate[request.startDate] ?? const [],
    );
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

/// Never ends: every page is a day newer than the window start.
class _EndlessApi extends RcApiService {
  int pages = 0;

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    pages++;
    final day = DateTime.now().subtract(const Duration(days: 1));
    return RcTransactionsResponse(
      lastPurchaseMs: 2_000_000_000_000 - pages,
      transactions: [
        RcTransaction(
          purchaseDate: day.toIso8601String(),
          storeTransactionIdentifier: 'p$pages',
        ),
      ],
    );
  }
}

class _EmptyTransactions extends TransactionsNotifier {
  _EmptyTransactions(super.ref) {
    state = const TransactionsState(selectedDayKey: '2026-11-02');
  }
}

ProviderContainer _container(RcApiService api) {
  final container = ProviderContainer(
    overrides: [
      rcApiServiceProvider.overrideWithValue(api),
      transactionsProvider.overrideWith((ref) => _EmptyTransactions(ref)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sweeps every look-back window, newest first', () async {
    final api = _WindowApi();
    final container = _container(api);
    await container.read(upcomingTransactionsProvider.notifier).loaded;

    final windows = upcomingFetchWindows(
      now: DateTime.now(),
      horizon: kUpcomingMaxHorizon,
    );
    final firstRequests = api.requests.where((r) => r.startFrom == null);
    expect(firstRequests.map((r) => r.startDate), [
      for (final w in windows) _key(w.start),
    ]);
    expect(firstRequests.map((r) => r.endDate), [
      for (final w in windows) _key(w.end),
    ]);
    final state = container.read(upcomingTransactionsProvider);
    expect(state.loadComplete, isTrue);
    expect(state.isLoading, isFalse);
  });

  test('a year-old annual plan shows as an upcoming renewal', () async {
    final now = DateTime.now();
    final windows = upcomingFetchWindows(
      now: now,
      horizon: kUpcomingMaxHorizon,
    );
    final annual = windows.last;
    final purchased = DateTime(now.year - 1, now.month, now.day + 3, 9);
    final api = _WindowApi({
      _key(annual.start): [
        RcTransaction(
          subscriberId: 's1',
          productIdentifier: 'pro.annual',
          store: 'App Store',
          storeTransactionIdentifier: 'a1',
          purchaseDate: purchased.toIso8601String(),
          expiresDate: DateTime(
            purchased.year + 1,
            purchased.month,
            purchased.day,
            9,
          ).toIso8601String(),
          revenue: 59.99,
          isAutoRenewing: true,
        ),
      ],
    });
    final container = _container(api);
    await container.read(upcomingTransactionsProvider.notifier).loaded;

    final events = container.read(upcomingEventsProvider(7));
    expect(events, hasLength(1));
    expect(events.single.kind, UpcomingKind.renewal);
    expect(events.single.amountUsd, 59.99);
  });

  test('a failed load keeps an error and finishes', () async {
    final container = _container(_FailingApi());
    await container.read(upcomingTransactionsProvider.notifier).loaded;

    final state = container.read(upcomingTransactionsProvider);
    expect(state.error, isNotNull);
    expect(state.loadComplete, isTrue);
    expect(state.isLoading, isFalse);
  });

  test('stops each window at the page cap and flags it', () async {
    final api = _EndlessApi();
    final container = _container(api);
    await container.read(upcomingTransactionsProvider.notifier).loaded;

    final state = container.read(upcomingTransactionsProvider);
    expect(state.truncated, isTrue);
    expect(state.loadComplete, isTrue);
  });
}
