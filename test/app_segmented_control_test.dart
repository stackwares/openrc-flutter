import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/widgets/app_segmented_control.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String groupValue,
    ValueChanged<String?>? onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppSegmentedControl<String>(
          values: const ['a', 'b'],
          labels: const {'a': 'Alpha', 'b': 'Beta'},
          groupValue: groupValue,
          onValueChanged: onChanged,
        ),
      ),
    ),
  );

  testWidgets('tapping a segment reports its value', (tester) async {
    String? picked;
    await pump(tester, groupValue: 'a', onChanged: (v) => picked = v);
    await tester.tap(find.text('Beta'));
    expect(picked, 'b');
  });

  testWidgets('a null callback ignores taps', (tester) async {
    await pump(tester, groupValue: 'a', onChanged: null);
    await tester.tap(find.text('Beta'));
    expect(tester.takeException(), isNull);
    expect(find.text('Beta'), findsOneWidget);
  });
}
