import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/revenue_section_screen.dart';
import 'package:openrc/features/revenue/widgets/revenue_insights_list.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openrc/features/revenue/revenue_insights_compute.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/commission_settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the Breakdown card fits three stores on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: RealtimeRevenueInsightsList(
              asModalEntry: true,
              transactions: [
                RcTransaction(store: 'App Store', revenue: 12.34),
                RcTransaction(store: 'Play Store', revenue: 56.78),
                RcTransaction(store: 'Stripe', revenue: 9.99),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('12.6%'), findsOneWidget);
  });

  testWidgets('sales without a country show as Unknown, not a code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: RealtimeRevenueInsightsList(
              asModalEntry: true,
              transactions: [
                RcTransaction(store: 'App Store', revenue: 10),
                RcTransaction(
                  store: 'App Store',
                  revenue: 10,
                  subscriberCountryCode: 'DE',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('__'), findsNothing);
    expect(find.text('DE'), findsOneWidget);
  });

  test('store shares include web revenue and add up to 100%', () {
    final data = computeRevenueInsights(const [
      RcTransaction(store: 'App Store', revenue: 10),
      RcTransaction(store: 'Play Store', revenue: 10),
      RcTransaction(store: 'Stripe', revenue: 20),
    ], const CommissionSettings());

    expect(data.applePct, closeTo(25, 1e-9));
    expect(data.googlePct, closeTo(25, 1e-9));
    expect(data.otherStoresPct, closeTo(50, 1e-9));
    expect(data.otherStoresRevenue, closeTo(20, 1e-9));
    expect(
      data.applePct + data.googlePct + data.otherStoresPct,
      closeTo(100, 1e-9),
    );
  });

  const stein = RcTransactionApp(id: 'app1', name: 'Stein');
  const orly = RcTransactionApp(id: 'app2', name: 'Orly');
  const trials = [
    RcTransaction(
      app: stein,
      store: 'App Store',
      isTrialPeriod: true,
      subscriberCountryCode: 'US',
      productIdentifier: 'stein.pro.sub.annual.false',
    ),
    RcTransaction(
      app: stein,
      store: 'App Store',
      isTrialPeriod: true,
      subscriberCountryCode: 'US',
      productIdentifier: 'stein.pro.sub.monthly.false',
      isAutoRenewing: false,
    ),
    RcTransaction(
      app: orly,
      store: 'Play Store',
      isTrialPeriod: true,
      subscriberCountryCode: 'DE',
      productIdentifier: 'orly.pro.sub.annual.false',
    ),
  ];

  test('trials are counted by status, store, app, country and plan', () {
    final data = computeTrialInsights(trials);

    expect(data.total, 3);
    expect(data.autoRenewing, 2);
    expect(data.cancelled, 1);
    expect([data.apple, data.google, data.otherStores], [2, 1, 0]);
    expect(data.topApps.map((e) => (e.label, e.count, e.appId)), [
      ('Stein', 2, 'app1'),
      ('Orly', 1, 'app2'),
    ]);
    expect(data.topCountries.map((e) => (e.key, e.count)), [
      ('US', 2),
      ('DE', 1),
    ]);
    expect(data.topPlans.map((e) => (e.label, e.count)), [
      ('Annual', 2),
      ('Monthly', 1),
    ]);
    expect(data.pctOf(data.autoRenewing), closeTo(66.67, 0.01));
  });

  testWidgets('only trials: the Breakdown card counts them', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pump(List<RcTransaction> transactions) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(FlexScheme.indigoM3),
            home: Scaffold(
              body: RealtimeRevenueInsightsList(
                asModalEntry: true,
                transactions: transactions,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(trials);
    expect(tester.takeException(), isNull);
    expect(find.text('Trials breakdown'), findsOneWidget);
    expect(find.text('3 trials'), findsOneWidget);
    expect(find.text('Auto-renew on'), findsOneWidget);
    expect(find.text('Top plans'), findsOneWidget);
    expect(find.text('Annual'), findsOneWidget);
    expect(find.text('0.0%'), findsNothing);

    // A sale among them brings back the revenue breakdown.
    await pump([
      ...trials,
      const RcTransaction(store: 'App Store', revenue: 9.99),
    ]);
    expect(find.text('Breakdown'), findsOneWidget);
    expect(find.text('Trials breakdown'), findsNothing);
  });

  testWidgets('the Revenue tab’s Trials list leads with their breakdown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final at = DateTime.now().toUtc().toIso8601String();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rcAccountProjectsProvider.overrideWith((ref) async => const []),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: RealtimeSectionTransactionsScreen(
            windowTransactions: [
              for (final t in trials)
                RcTransaction(
                  app: t.app,
                  store: t.store,
                  isTrialPeriod: true,
                  purchaseDate: at,
                  productIdentifier: t.productIdentifier,
                ),
              RcTransaction(
                store: 'App Store',
                revenue: 9.99,
                purchaseDate: at,
              ),
            ],
            filter: TransactionDaySectionFilter.trial,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Trials breakdown'), findsOneWidget);
    expect(find.text('3 trials'), findsOneWidget);
  });

  test('without web sales the other-stores share is zero', () {
    final data = computeRevenueInsights(const [
      RcTransaction(store: 'App Store', revenue: 5),
    ], const CommissionSettings());
    expect(data.otherStoresPct, 0);
    expect(data.applePct, closeTo(100, 1e-9));
  });
}
