import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

RcTransaction _tx(String id, DateTime at, {double revenue = 1}) =>
    RcTransaction(
      storeTransactionIdentifier: id,
      purchaseDate: at.toUtc().toIso8601String(),
      revenue: revenue,
      store: 'App Store',
    );

int _ms(RcTransaction t) =>
    DateTime.parse(t.purchaseDate!).millisecondsSinceEpoch;

/// `/me/transactions` over a fixed history (newest first), paged by
/// `start_from` exactly like the real endpoint.
class _FakeApi extends RcApiService {
  _FakeApi(this.history);

  final List<RcTransaction> history;

  @override
  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (request.startFrom == null) {
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 12))
          .millisecondsSinceEpoch;
      return RcTransactionsResponse(
        transactions: history.where((t) => _ms(t) > cutoff).toList(),
      );
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
      _tx('recent-$h', now.subtract(Duration(hours: h)), revenue: h * 2.0),
    for (var d = 1; d <= 120; d += 7)
      _tx('day-$d', now.subtract(Duration(days: d, hours: 1)), revenue: 3.0),
  ];

  test('every page leaves the day totals matching the loaded rows', () async {
    final container = ProviderContainer(
      overrides: [
        rcApiServiceProvider.overrideWithValue(_FakeApi(history)),
        usdExchangeRatesProvider.overrideWith((ref) async => const {}),
      ],
    );
    addTearDown(container.dispose);

    await container.read(transactionsProvider.notifier).fetchInitial();
    await _settle();

    final state = container.read(transactionsProvider);
    // Several pages landed, so the totals were built page by page.
    expect(state.grouped.length, greaterThan(1));
    expect(state.realtimeLoadComplete, isTrue);
    expect(
      state.dailyTotals,
      dailyTotalsForGrouped(
        state.grouped,
        container.read(commissionSettingsProvider),
      ),
      reason: 'each page adds only its own days, so they must still add up',
    );
  });

  testWidgets('scheduled rows from a future day are still listed today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = DateTime(now.year, now.month, now.day);
    final todayKey = localTodayDayKey();
    final tomorrowKey = isoLocalDayKey(today.add(const Duration(days: 1)));
    // One row scheduled later today, one scheduled tomorrow: the day view
    // fills its Scheduled section without walking the loaded history.
    final laterToday = _tx('later-today', today.add(const Duration(hours: 23)));
    final tomorrow = _tx(
      'tomorrow',
      today.add(const Duration(days: 1, hours: 9)),
    );
    final state = TransactionsState(
      selectedDayKey: todayKey,
      hasMore: false,
      grouped: {
        todayKey: [
          _tx('sold', today.subtract(const Duration(hours: 2))),
          laterToday,
        ],
        tomorrowKey: [tomorrow],
        for (var d = 1; d <= 30; d++)
          isoLocalDayKey(today.subtract(Duration(days: d))): [
            _tx('past-$d', today.subtract(Duration(days: d + 1))),
          ],
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

    expect(find.textContaining('Scheduled'), findsOneWidget);
    expect(find.textContaining('2 later today'), findsOneWidget);
  });
}

class _Fixed extends TransactionsNotifier {
  _Fixed(super.ref, TransactionsState initial) {
    state = initial;
  }

  @override
  Future<void> fetchInitial() async {}
}
