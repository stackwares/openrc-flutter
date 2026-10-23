import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/widgets/animated_number.dart';
import 'package:revenuecat/widgets/pressable_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child, {bool reduceMotion = false}) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  testWidgets('a total counts up from zero and lands on the value', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const AnimatedExactAmount(amount: 212.87, countFromZero: true)),
    );
    expect(find.text('\$0.00'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('\$212.87'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('\$212.87'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final value at once', (tester) async {
    await tester.pumpWidget(
      host(
        const AnimatedExactAmount(amount: 212.87, countFromZero: true),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(find.text('\$212.87'), findsOneWidget);
  });

  testWidgets('counts glide from the old value to the new one', (tester) async {
    await tester.pumpWidget(host(const AnimatedCount(count: 10)));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    await tester.pumpWidget(host(const AnimatedCount(count: 20)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('20'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('press shrinks the child and a drag releases it', (tester) async {
    await tester.pumpWidget(
      host(
        const PressableScale(
          child: ColoredBox(
            color: Colors.blue,
            child: SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressableScale)),
    );
    await tester.pump();
    expect(scale(), lessThan(1));

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(scale(), 1);
    await gesture.up();
  });
}
