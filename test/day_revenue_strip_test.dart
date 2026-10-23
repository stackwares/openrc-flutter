import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/transactions/widgets/day_revenue_strip.dart';
import 'package:revenuecat/theme/app_colors.dart';

void main() {
  final days = [
    for (var i = 0; i < 7; i++)
      DayRevenueStripDay(
        dayKey: '2026-10-${(17 + i).toString().padLeft(2, '0')}',
        date: DateTime(2026, 10, 17 + i),
        // The oldest day isn't loaded yet.
        total: i == 0 ? null : 100.0 * i,
      ),
  ];

  Future<List<String>> pump(WidgetTester tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          splashFactory: InkRipple.splashFactory,
          extensions: const [AppColors.dark],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DayRevenueStrip(
              days: days,
              selectedDayKey: '2026-10-23',
              formatAmount: (v) => '\$${v.toStringAsFixed(2)}',
              onDaySelected: selected.add,
            ),
          ),
        ),
      ),
    );
    return selected;
  }

  testWidgets('tapping a bar selects that day', (tester) async {
    final selected = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('day_strip_2026-10-20')));
    expect(selected, ['2026-10-20']);
  });

  testWidgets('the selected day is not tappable again', (tester) async {
    final selected = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('day_strip_2026-10-23')));
    expect(selected, isEmpty);
  });

  testWidgets('days that are not loaded yet say so', (tester) async {
    await pump(tester);
    expect(
      find.bySemanticsLabel('Sat, Oct 17: not loaded yet'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Fri, Oct 23: \$600.00'), findsOneWidget);
  });
}
