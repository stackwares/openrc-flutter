import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:openrc/features/transactions/widgets/jump_to_day_sheet.dart';
import 'package:openrc/widgets/shell_header.dart';

void main() {
  final today = DateUtils.dateOnly(DateTime.now());

  /// Opens the picker on [selectedDay]; the future completes with its pick.
  Future<Future<DateTime?>> open(
    WidgetTester tester, {
    DateTime? selectedDay,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = showJumpToDaySheet(
      context,
      selectedDay: selectedDay ?? today,
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a quick pick opens that day', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();

    expect(await result, DateUtils.addDaysToDate(today, -1));
  });

  testWidgets('tapping a day in the calendar opens it', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(await result, DateTime(today.year, today.month, 1));
  });

  testWidgets('picking a year moves the calendar without closing it', (
    tester,
  ) async {
    final result = await open(tester);
    final lastYear = today.year - 1;

    await tester.tap(find.text(DateFormat.yMMMM().format(today)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$lastYear'));
    await tester.pumpAndSettle();

    expect(find.text('Go to a day'), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    expect(await result, DateTime(lastYear, today.month, 15));
  });

  testWidgets('a tappable header title shows a chevron and its tooltip', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ShellHeader(
            title: 'Today',
            subtitle: 'Friday, October 23, 2026',
            onTitleTap: () => taps++,
            titleTapTooltip: 'Go to a day',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.byTooltip('Go to a day'), findsOneWidget);
    await tester.tap(find.text('Today'));
    expect(taps, 1);
  });
}
