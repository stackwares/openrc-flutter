import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/extensions/context_extensions.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => context.showSnackBar(
                'Saved',
                actionLabel: actionLabel,
                onAction: onAction,
                duration: duration,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a toast goes away by itself', (tester) async {
    await show(tester);
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('a toast with an action goes away too', (tester) async {
    // Material would keep this one up until it was tapped, since
    // SnackBar.persist defaults to `action != null`.
    await show(tester, actionLabel: 'Undo', onAction: () {});
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('the caller can ask for a longer read', (tester) async {
    await show(tester, duration: const Duration(seconds: 10));

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });
}
