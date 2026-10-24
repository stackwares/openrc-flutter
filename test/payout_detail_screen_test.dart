import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/core/utils/store_payday_schedule.dart';
import 'package:openrc/features/revenue/payout_detail_provider.dart';
import 'package:openrc/features/revenue/payout_detail_screen.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/revenue_section_screen.dart';
import 'package:openrc/features/revenue/widgets/revenue_period_hero_card.dart';
import 'package:openrc/features/transactions/widgets/day_summary_card.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

PayoutPeriod get _period => PayoutPeriod(
  store: PayoutStore.apple,
  earningsStart: DateTime(2026, 8, 2),
  earningsEnd: DateTime(2026, 8, 29),
  paymentDate: DateTime(2026, 10, 1),
);

final _txs = [
  RcTransaction(
    app: const RcTransactionApp(id: 'app1', name: 'Stein'),
    store: 'App Store',
    revenue: 12.34,
    purchaseDate: DateTime(2026, 8, 2, 12).toIso8601String(),
    subscriberCountryCode: 'US',
    isRenewal: true,
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rcAccountProjectsProvider.overrideWith((ref) async => const []),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
          payoutDetailTransactionsProvider.overrideWith((ref, period) {
            return PayoutDetailNotifier.ready(
              ref,
              period,
              PayoutDetailState(transactions: _txs, loadComplete: true),
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          home: PayoutDetailScreen(payout: Payout(_period, 99)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the earnings hero, type tiles and breakdown', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(find.text('App Store'), findsWidgets);
    expect(
      find.text(
        'Earnings ${formatPaydayRange(_period.earningsStart, _period.earningsEnd)}',
      ),
      findsWidgets,
    );
    expect(find.text(formatExactUsd(12.34)), findsWidgets);
    expect(find.byType(RevenuePeriodHeroCard), findsOneWidget);
    expect(find.byType(DayTypeCountSummary), findsOneWidget);
    expect(find.text('Top apps'), findsOneWidget);
    expect(find.text('Stein'), findsOneWidget);
    expect(find.text('Top countries'), findsOneWidget);
    expect(
      find.textContaining('differ from the saved payout figure'),
      findsOneWidget,
    );
  });

  testWidgets('a type tile opens the section list for this payout window', (
    tester,
  ) async {
    await pumpDetail(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(DayTypeCountSummary),
        matching: find.text('Renewals'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RealtimeSectionTransactionsScreen), findsOneWidget);
    expect(
      find.text(
        'Earnings ${formatPaydayRange(_period.earningsStart, _period.earningsEnd)}',
      ),
      findsWidgets,
    );
    expect(find.text('This month so far'), findsNothing);
  });
}
