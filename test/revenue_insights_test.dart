import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/revenue/widgets/revenue_insights_list.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revenuecat/features/revenue/revenue_insights_compute.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/commission_settings_store.dart';

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

  test('without web sales the other-stores share is zero', () {
    final data = computeRevenueInsights(const [
      RcTransaction(store: 'App Store', revenue: 5),
    ], const CommissionSettings());
    expect(data.otherStoresPct, 0);
    expect(data.applePct, closeTo(100, 1e-9));
  });
}
