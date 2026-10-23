import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/theme/app_colors.dart';
import 'package:openrc/widgets/delta_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          splashFactory: InkRipple.splashFactory,
          extensions: const [AppColors.light],
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Color labelColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.color!;

  testWidgets('count shows a signed difference and says what it means', (
    tester,
  ) async {
    await pump(tester, DeltaBadge.count(current: 44, previous: 29));
    expect(find.text('+15'), findsOneWidget);
    expect(find.bySemanticsLabel('15 more than yesterday'), findsOneWidget);
    expect(labelColor(tester, '+15'), AppColors.light.positive);
  });

  testWidgets('fewer of something bad is good news', (tester) async {
    await pump(
      tester,
      DeltaBadge.count(current: 7, previous: 9, higherIsBetter: false),
    );
    expect(find.text('−2'), findsOneWidget);
    expect(labelColor(tester, '−2'), AppColors.light.positive);
  });

  testWidgets('no change reads "same" in a neutral color', (tester) async {
    await pump(tester, DeltaBadge.count(current: 6, previous: 6));
    expect(find.text('same'), findsOneWidget);
    expect(find.bySemanticsLabel('Same as yesterday'), findsOneWidget);
    expect(labelColor(tester, 'same'), AppColors.light.neutralDelta);
  });

  testWidgets('percent drop shows a down arrow in the negative color', (
    tester,
  ) async {
    await pump(tester, DeltaBadge.percent(current: 212.87, previous: 534.54));
    expect(find.text('60%'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Down 60% from yesterday'), findsOneWidget);
    expect(labelColor(tester, '60%'), AppColors.light.negative);
  });
}
