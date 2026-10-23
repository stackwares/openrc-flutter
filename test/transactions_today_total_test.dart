import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/transactions_screen.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fixed extends TransactionsNotifier {
  _Fixed(super.ref, TransactionsState initial) {
    state = initial;
  }

  @override
  Future<void> fetchInitial() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final now = DateTime.now();
  final nearMidnight = now.hour == 23 && now.minute >= 50 || now.hour == 0;

  testWidgets('today’s total leaves out transactions scheduled for later', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 2000);
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
            storeTransactionIdentifier: 'happened',
            purchaseDate: now
                .subtract(const Duration(minutes: 5))
                .toUtc()
                .toIso8601String(),
            revenue: 10,
            store: 'App Store',
          ),
          RcTransaction(
            storeTransactionIdentifier: 'scheduled',
            purchaseDate: now
                .add(const Duration(minutes: 5))
                .toUtc()
                .toIso8601String(),
            revenue: 5,
            store: 'App Store',
          ),
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
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\$10.00'), findsWidgets);
    expect(find.text('\$15.00'), findsNothing);
    expect(find.textContaining('1 later today'), findsOneWidget);
  }, skip: nearMidnight);
}
