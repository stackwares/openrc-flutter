import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/app/app_navigator.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/features/ask/ask_providers.dart';

void main() {
  testWidgets('asking from a pushed detail closes it and opens Ask', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: appNavigatorKey, home: const _Root()),
      ),
    );

    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.text('ask about this'));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsNothing);
    expect(container.read(mainShellTabIndexProvider), 3);
    expect(container.read(askPrefillProvider), 'About this detail');
  });
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute<void>(builder: (_) => const _Detail())),
        child: const Text('open detail'),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('detail')),
      body: TextButton(
        onPressed: () => openAskTab(ref, prefill: 'About this detail'),
        child: const Text('ask about this'),
      ),
    );
  }
}
