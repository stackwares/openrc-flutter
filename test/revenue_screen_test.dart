import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/revenue/revenue_screen.dart';
import 'package:openrc/features/transactions/transactions_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedTransactions extends TransactionsNotifier {
  _FixedTransactions(super.ref, TransactionsState initial) {
    state = initial;
  }

  int fetches = 0;

  @override
  Future<void> fetchInitial() async {
    fetches++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FixedTransactions> pump(
    WidgetTester tester,
    TransactionsState state,
  ) async {
    late _FixedTransactions notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsProvider.overrideWith((ref) {
            notifier = _FixedTransactions(ref, state);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const RealtimeTransactionsScreen(),
        ),
      ),
    );
    await tester.pump();
    return notifier;
  }

  testWidgets('shows the month total when nothing has loaded', (tester) async {
    await pump(
      tester,
      const TransactionsState(
        selectedDayKey: '2026-10-23',
        realtimeLoadComplete: true,
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('This month so far'), findsOneWidget);
    expect(find.textContaining('\$0.00'), findsWidgets);
  });

  testWidgets('error state retries the transaction load', (tester) async {
    final notifier = await pump(
      tester,
      const TransactionsState(
        selectedDayKey: '2026-10-23',
        error: 'No internet connection.',
      ),
    );
    expect(find.text('Couldn\u2019t load revenue'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(notifier.fetches, 1);
  });
}
