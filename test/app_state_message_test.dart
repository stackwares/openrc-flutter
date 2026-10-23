import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/widgets/app_state_message.dart';

void main() {
  testWidgets('error state shows message and retries', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: AppStateMessage.error(
            message: 'No internet connection.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('No internet connection.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('works inside RefreshIndicator', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: RefreshIndicator(
            onRefresh: () async {},
            child: const AppStateMessage(icon: Icons.inbox, title: 'Empty'),
          ),
        ),
      ),
    );
    expect(find.text('Empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
