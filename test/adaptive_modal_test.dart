import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/widgets/adaptive_modal.dart';

void main() {
  Future<BuildContext> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold();
          },
        ),
      ),
    );
    return captured;
  }

  group('showAdaptiveSheet', () {
    testWidgets('is a bottom sheet on phones', (tester) async {
      final context = await pumpAt(tester, const Size(390, 844));
      showAdaptiveSheet<void>(
        context: context,
        builder: (_) => const Text('Pick a currency'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Pick a currency'), findsOneWidget);
    });

    testWidgets('takes its share of a phone, drag handle included', (
      tester,
    ) async {
      final context = await pumpAt(tester, const Size(390, 1000));
      showAdaptiveSheet<void>(
        context: context,
        heightFactor: 0.7,
        builder: (_) => const Text('Filters'),
      );
      await tester.pumpAndSettle();
      // The top 30% stays free to tap out of the sheet.
      expect(tester.getTopLeft(find.byType(BottomSheet)).dy, 300);
    });

    testWidgets('is a capped dialog on large screens', (tester) async {
      final context = await pumpAt(tester, const Size(1280, 1400));
      showAdaptiveSheet<void>(
        context: context,
        heightFactor: 0.8,
        builder: (_) => const Text('Pick a currency'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final card = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Material),
      );
      final size = tester.getSize(card.first);
      expect(size.width, lessThanOrEqualTo(560));
      expect(size.height, lessThanOrEqualTo(680));
    });

    testWidgets('can be wider for side-by-side content', (tester) async {
      final context = await pumpAt(tester, const Size(1280, 1400));
      showAdaptiveSheet<void>(
        context: context,
        heightFactor: 0.8,
        dialogMaxWidth: 880,
        builder: (_) => const Text('Filters'),
      );
      await tester.pumpAndSettle();
      final card = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Material),
      );
      expect(tester.getSize(card.first).width, 880);
    });
  });

  group('showAdaptiveForm', () {
    List<Widget> actions(BuildContext context) => [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Log out'),
      ),
    ];

    testWidgets('is a sheet with the main action first on phones', (
      tester,
    ) async {
      final context = await pumpAt(tester, const Size(390, 844));
      final result = showAdaptiveForm<bool>(
        context: context,
        title: 'Log out?',
        content: (_) => const Text('You’ll need to sign in again.'),
        actions: actions,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      final logOut = tester.getTopLeft(find.text('Log out'));
      final cancel = tester.getTopLeft(find.text('Cancel'));
      expect(logOut.dy, lessThan(cancel.dy));

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('is an alert dialog on large screens', (tester) async {
      final context = await pumpAt(tester, const Size(1024, 768));
      showAdaptiveForm<bool>(
        context: context,
        title: 'Log out?',
        content: (_) => const Text('You’ll need to sign in again.'),
        actions: actions,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
