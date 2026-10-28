import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/currency_format.dart';
import 'package:openrc/features/revenue/payout_detail_provider.dart';
import 'package:openrc/features/revenue/payout_detail_screen.dart';
import 'package:openrc/features/revenue/payout_history.dart';
import 'package:openrc/features/revenue/payout_history_provider.dart';
import 'package:openrc/features/revenue/payout_history_screen.dart';
import 'package:openrc/features/revenue/widgets/revenue_next_payday_proceeds_card.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedHistory extends PayoutHistoryNotifier {
  _FixedHistory(super.ref, PayoutHistoryState initial) {
    state = initial;
  }

  int loads = 0;

  @override
  Future<void> load() async => loads++;
}

/// Saved totals for every paid payout of [stores] as of today.
Map<String, double> _amounts({double apple = 100, double google = 50}) {
  final today = DateTime.now();
  return {
    for (final p in paidPayouts(PayoutStore.apple, today)) p.id: apple,
    for (final p in paidPayouts(PayoutStore.google, today)) p.id: google,
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Created when something first reads the history.
  late _FixedHistory notifier;

  Future<void> pump(
    WidgetTester tester,
    PayoutHistoryState state, {
    Widget home = const PayoutHistoryScreen(),
    // Tall enough to build every month without scrolling.
    Size size = const Size(800, 4000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payoutHistoryProvider.overrideWith((ref) {
            notifier = _FixedHistory(ref, state);
            return notifier;
          }),
          payoutDetailTransactionsProvider.overrideWith((ref, period) {
            return PayoutDetailNotifier.ready(
              ref,
              period,
              const PayoutDetailState(loadComplete: true),
            );
          }),
          usdExchangeRatesProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the year total, the stores and every payout', (
    tester,
  ) async {
    final amounts = _amounts();
    await pump(tester, PayoutHistoryState(amounts: amounts, hasLoaded: true));
    expect(notifier.loads, 1);

    expect(find.text('Payout history'), findsOneWidget);
    expect(find.text('Paid in the last 12 months'), findsOneWidget);
    final total = amounts.values.fold(0.0, (a, b) => a + b);
    expect(find.text(formatExactUsd(total)), findsOneWidget);
    expect(find.textContaining('payouts since'), findsOneWidget);
    expect(find.byIcon(Icons.apple), findsWidgets);
    expect(find.byIcon(Icons.android), findsWidgets);
    expect(find.text('Tap a month to see what it paid'), findsOneWidget);
  });

  testWidgets('the store filter narrows totals and rows', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(amounts: _amounts(), hasLoaded: true),
    );
    await tester.tap(find.text('Google').first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.apple), findsNothing);
    final googleTotal =
        paidPayouts(PayoutStore.google, DateTime.now()).length * 50.0;
    expect(find.text(formatExactUsd(googleTotal)), findsOneWidget);
  });

  testWidgets('one store means no filter and no split', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(amounts: _amounts(apple: 0), hasLoaded: true),
    );
    expect(find.text('All'), findsNothing);
    expect(find.byIcon(Icons.apple), findsNothing);
    expect(find.byIcon(Icons.android), findsWidgets);
  });

  testWidgets('nothing paid shows an empty state', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(
        amounts: _amounts(apple: 0, google: 0),
        hasLoaded: true,
      ),
    );
    expect(find.text('No payouts yet'), findsOneWidget);
  });

  testWidgets('an ignored store filter explains itself', (tester) async {
    await pump(
      tester,
      const PayoutHistoryState(storeSplitUnavailable: true, hasLoaded: true),
    );
    expect(find.text('Payouts by store aren’t available'), findsOneWidget);
  });

  testWidgets('an error with nothing saved offers a retry', (tester) async {
    await pump(
      tester,
      const PayoutHistoryState(
        error: 'No internet connection.',
        hasLoaded: true,
      ),
    );
    expect(find.text('Couldn’t load payouts'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(notifier.loads, 2);
  });

  testWidgets('a failed refresh keeps saved payouts on screen', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(
        amounts: _amounts(),
        hasLoaded: true,
        error: 'No internet connection.',
      ),
    );
    expect(find.text('Couldn’t load the latest payouts.'), findsOneWidget);
    expect(find.text('Paid in the last 12 months'), findsOneWidget);
  });

  testWidgets('the Next payouts card opens the history', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(amounts: _amounts(), hasLoaded: true),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: RealtimeNextPaydayProceedsCard(
            allLoadedTransactions: [],
            loadedTransactionCount: 0,
          ),
        ),
      ),
    );
    expect(find.textContaining('Last paid: Apple'), findsOneWidget);
    await tester.tap(find.text('Payout history'));
    await tester.pumpAndSettle();
    expect(find.text('Paid in the last 12 months'), findsOneWidget);
  });

  testWidgets('a wide window shows the history in a side panel', (
    tester,
  ) async {
    await pump(
      tester,
      PayoutHistoryState(amounts: _amounts(), hasLoaded: true),
      size: const Size(1400, 1000),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: RealtimeNextPaydayProceedsCard(
            allLoadedTransactions: [],
            loadedTransactionCount: 0,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Payout history'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The panel is 480 wide on the right; the content fills it, not the window.
    final total = tester.getRect(find.text('Paid in the last 12 months'));
    expect(total.left, greaterThan(1400 - 480));
    expect(total.width, greaterThan(100));
    expect(find.text('Tap a month to see what it paid'), findsOneWidget);
  });

  testWidgets('a phone opens the payout details full screen', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(amounts: _amounts(), hasLoaded: true),
      size: const Size(400, 4000),
    );
    final period = paidPayouts(PayoutStore.apple, DateTime.now()).last;
    final row = find.byKey(ValueKey('payout-row-${period.id}'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    // A route, not the wide window's side panel: the list is gone behind it.
    expect(find.byType(PayoutDetailScreen), findsOneWidget);
    expect(find.byType(PayoutHistoryScreen), findsNothing);
    expect(find.text('Apple'), findsWidgets);
  });

  testWidgets('tapping a payout row opens its detail screen', (tester) async {
    await pump(
      tester,
      PayoutHistoryState(amounts: _amounts(), hasLoaded: true),
    );
    final period = paidPayouts(PayoutStore.apple, DateTime.now()).last;
    final row = find.byKey(ValueKey('payout-row-${period.id}'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(PayoutDetailScreen), findsOneWidget);
    expect(find.text('Apple'), findsWidgets);
    expect(
      find.textContaining('differ from the saved payout figure'),
      findsOneWidget,
    );
  });
}
