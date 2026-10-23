import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/app/floating_tab_chrome.dart';

void main() {
  testWidgets('tapping a tab reports its index; selected tab is inert', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: FloatingTabChrome(
            currentIndex: 0,
            onDestinationSelected: taps.add,
            destinations: const [
              FloatingTabDestination(
                label: 'A',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
              ),
              FloatingTabDestination(
                label: 'B',
                icon: Icons.star_outline,
                selectedIcon: Icons.star,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_outline));
    await tester.tap(find.byIcon(Icons.home));
    expect(taps, [1]);
    expect(find.byTooltip('B'), findsOneWidget);
  });
}
