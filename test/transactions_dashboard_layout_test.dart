import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/revenue_screen.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:openrc/features/transactions/widgets/transactions_filter_bar.dart';
import 'package:openrc/features/transactions/widgets/transactions_table.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/transaction_list_sort_mode.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/transaction_list_sort_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fixed extends TransactionsNotifier {
  _Fixed(super.ref, TransactionsState initial) {
    state = initial;
  }

  @override
  Future<void> fetchInitial() async {}
}

const _projects = [
  RcProject(id: 'app_a', name: 'Alpha'),
  RcProject(id: 'app_b', name: 'Beta'),
  RcProject(id: 'app_c', name: 'Gamma'),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final n = DateTime.now();
  // Early today: in the past, today and this month whenever the test runs.
  final at = DateTime(n.year, n.month, n.day).add(const Duration(seconds: 1));
  final todayKey = localTodayDayKey();

  RcTransaction tx(
    String subscriber,
    String appId,
    String appName, {
    bool trial = false,
    bool renewal = false,
    String store = 'App Store',
  }) => RcTransaction(
    storeTransactionIdentifier: 'tx-$subscriber',
    subscriberId: subscriber,
    subscriberCountryCode: 'US',
    app: RcTransactionApp(id: appId, name: appName),
    productIdentifier: 'pro_monthly',
    purchaseDate: at.toUtc().toIso8601String(),
    revenue: trial ? 0 : 4.99,
    isTrialPeriod: trial,
    isRenewal: renewal,
    store: store,
  );

  final transactions = [
    tx('trialuser', 'app_a', 'Alpha', trial: true),
    tx('renewuser', 'app_b', 'Beta', renewal: true, store: 'Play Store'),
  ];

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsProvider.overrideWith(
            (ref) => _Fixed(
              ref,
              TransactionsState(
                selectedDayKey: todayKey,
                grouped: {todayKey: transactions},
                hasMore: false,
                realtimeLoadComplete: true,
              ),
            ),
          ),
          rcAccountProjectsProvider.overrideWith((ref) async => _projects),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byWidget(screen)));
  }

  Finder inBar(String text) => find.descendant(
    of: find.byType(TransactionsFilterBar),
    matching: find.text(text),
  );

  testWidgets('wide Transactions shows filters, cards and a table', (
    tester,
  ) async {
    await pump(tester, const TransactionsScreen());
    expect(find.byType(TransactionsFilterBar), findsOneWidget);
    expect(find.byType(TransactionsTable), findsOneWidget);
    expect(inBar('All projects'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('trialuser'), findsOneWidget);
    expect(find.text('renewuser'), findsOneWidget);
  });

  testWidgets('narrow windows keep the single column', (tester) async {
    await pump(tester, const TransactionsScreen(), size: const Size(430, 900));
    expect(find.byType(TransactionsFilterBar), findsNothing);
    expect(find.byType(TransactionsTable), findsNothing);
  });

  testWidgets('a project click shows only it; Ctrl-click adds another', (
    tester,
  ) async {
    final container = await pump(tester, const TransactionsScreen());
    Set<String>? apps() => container.read(transactionsAppIncludeFilterProvider);

    await tester.tap(inBar('Alpha'));
    await tester.pumpAndSettle();
    expect(apps(), {'app_a'});
    expect(find.text('renewuser'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(inBar('Beta'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(apps(), {'app_a', 'app_b'});

    await tester.tap(inBar('All projects'));
    await tester.pumpAndSettle();
    expect(apps(), isNull);
  });

  testWidgets('the store menu sets the store filter', (tester) async {
    final container = await pump(tester, const TransactionsScreen());
    await tester.tap(inBar('All stores'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CheckboxMenuButton),
        matching: find.text('Google Play'),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(transactionsPlatformFilterProvider), {
      TransactionPlatformFilter.google,
    });
  });

  testWidgets('the Purchased header flips the sort', (tester) async {
    final container = await pump(tester, const TransactionsScreen());
    await tester.tap(find.text('Purchased'));
    await tester.pumpAndSettle();
    expect(
      container.read(transactionListSortProvider),
      TransactionListSortMode.purchaseOldestFirst,
    );
  });

  testWidgets('wide Revenue lists the month and filters it by tile', (
    tester,
  ) async {
    // Tall enough that the table under the cards is built.
    await pump(
      tester,
      const RealtimeTransactionsScreen(),
      size: const Size(1400, 2400),
    );
    expect(find.byType(TransactionsFilterBar), findsOneWidget);
    expect(
      find.textContaining('This month’s transactions', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('trialuser'), findsOneWidget);
    expect(find.text('renewuser'), findsOneWidget);

    await tester.tap(find.text('Trials').first);
    await tester.pumpAndSettle();
    expect(find.text('trialuser'), findsOneWidget);
    expect(find.text('renewuser'), findsNothing);
  });
}
