import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/upcoming/upcoming_provider.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fixed extends TransactionsNotifier {
  _Fixed(super.ref, TransactionsState initial) {
    state = initial;
  }

  @override
  Future<void> fetchInitial({String source = 'manual'}) async {}
}

RcTransaction _monthly({
  required String id,
  required DateTime expires,
  double revenue = 9.99,
}) => RcTransaction(
  app: const RcTransactionApp(id: 'app1', name: 'Demo App'),
  subscriberId: 'sub-$id',
  productIdentifier: 'pro.monthly',
  store: 'App Store',
  storeTransactionIdentifier: id,
  purchaseDate: DateTime(
    expires.year,
    expires.month - 1,
    expires.day,
    expires.hour,
    expires.minute,
  ).toUtc().toIso8601String(),
  expiresDate: expires.toUtc().toIso8601String(),
  revenue: revenue,
  isAutoRenewing: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime.now();
  final nearMidnight = now.hour == 23 || now.hour == 0;

  Future<void> pump(
    WidgetTester tester,
    List<RcTransaction> upcomingRows,
  ) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = localTodayDayKey();
    final state = TransactionsState(
      selectedDayKey: today,
      hasMore: false,
      realtimeLoadComplete: true,
      grouped: {
        today: [
          RcTransaction(
            storeTransactionIdentifier: 'sold',
            purchaseDate: now
                .subtract(const Duration(minutes: 5))
                .toUtc()
                .toIso8601String(),
            revenue: 10,
            store: 'App Store',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsProvider.overrideWith((ref) => _Fixed(ref, state)),
          upcomingTransactionsProvider.overrideWith(
            (ref) => UpcomingNotifier.ready(
              ref,
              UpcomingLoadState(transactions: upcomingRows, loadComplete: true),
            ),
          ),
          rcAccountProjectsProvider.overrideWith((ref) async => const []),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('today shows renewals still due and where the day ends up', (
    tester,
  ) async {
    await pump(tester, [
      _monthly(id: 'later', expires: now.add(const Duration(minutes: 30))),
    ]);

    expect(
      find.textContaining('Due later today', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('On track for'), findsOneWidget);
    expect(find.text('\$19.99'), findsOneWidget);
  }, skip: nearMidnight);

  testWidgets('next day opens a projected day with its renewals', (
    tester,
  ) async {
    final tomorrowNoon = DateTime(now.year, now.month, now.day + 1, 12);
    await pump(tester, [_monthly(id: 'tomorrow', expires: tomorrowNoon)]);

    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();

    expect(find.text('Tomorrow'), findsWidgets);
    expect(find.text('Expected'), findsOneWidget);
    expect(
      find.textContaining('Due this day', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Demo App'), findsOneWidget);
    expect(find.text('1 renewal'), findsOneWidget);
  }, skip: nearMidnight);
}
