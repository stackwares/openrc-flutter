import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/transactions/transactions_common.dart';
import 'package:revenuecat/features/transactions/widgets/day_summary_card.dart';
import 'package:revenuecat/theme/app_colors.dart';

void main() {
  testWidgets('tiles fit a phone width at a large text size', (tester) async {
    final tapped = <TransactionDaySectionFilter>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          splashFactory: InkRipple.splashFactory,
          extensions: const [AppColors.dark],
        ),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: SizedBox(
              width: 328,
              child: DayTypeCountSummary(
                transactions: const [],
                previousDayTransactions: const [],
                selectedFilters: const {},
                onFilterCellTap: tapped.add,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Trials'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('same'), findsNWidgets(6));

    await tester.tap(find.text('Renewals'));
    expect(tapped, [TransactionDaySectionFilter.renewal]);
  });
}
