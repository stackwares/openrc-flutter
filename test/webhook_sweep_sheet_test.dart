import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/notifications/widgets/webhook_sweep_sheet.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

/// A spinner that never stops would hang `pumpAndSettle` forever.
const _settle = Duration(milliseconds: 50);
const _settleTimeout = Duration(seconds: 5);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required FakeRevenueCat rc,
    bool ownWebhook = false,
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        pushMessagingProvider.overrideWithValue(FakePushMessaging()),
        rcApiServiceProvider.overrideWithValue(rc.api()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(pushSettingsProvider.notifier).enable();
    if (ownWebhook) {
      // Written in directly: a request here would wait on the fake clock.
      rc.webhooks['p1']!.add({
        ...PushWebhooks.inputFor(
          container.read(pushSettingsProvider).secret!,
          sandbox: false,
          kinds: PushKind.all,
        ).toJson(),
        'id': 'wh-own',
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showWebhookSweepSheet(context),
                  child: const Text('open sweep'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sweep'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    return container;
  }

  testWidgets('counts what is this device\'s and what would go', (
    tester,
  ) async {
    final rc = FakeRevenueCat(projects: ['p1', 'p2']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    rc.addForeign('p2', name: 'Zapier', url: 'https://zapier.com/y');
    await pump(tester, rc: rc, ownWebhook: true);

    expect(find.text('All webhooks'), findsOneWidget);
    expect(find.text('Slack'), findsNothing);
    expect(find.text('1 for this device stay · 2 other'), findsOneWidget);
    expect(find.text('1 for this device · 1 other'), findsOneWidget);
    expect(find.text('0 for this device · 1 other'), findsOneWidget);
    expect(find.text('Delete 2 other webhooks'), findsOneWidget);
  });

  testWidgets('asks first, then deletes everything but this device\'s', (
    tester,
  ) async {
    final rc = FakeRevenueCat(projects: ['p1', 'p2']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    rc.addForeign('p2', name: 'Zapier', url: 'https://zapier.com/y');
    await pump(tester, rc: rc, ownWebhook: true);

    await tester.tap(find.text('Delete 2 other webhooks'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    expect(find.text('Delete every other webhook?'), findsOneWidget);

    // Cancelling keeps them.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    expect(rc.webhooks['p1'], hasLength(2));

    await tester.tap(find.text('Delete 2 other webhooks'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete 2 other webhooks').last,
    );
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);

    expect(rc.webhooks['p1']!.single['id'], 'wh-own');
    expect(rc.webhooks['p2'], isEmpty);
    expect(find.text('Deleted 2 webhooks.'), findsOneWidget);
    // Nothing left to delete, so the action says so.
    expect(find.text('Nothing left to delete'), findsOneWidget);
  });

  testWidgets('says when nothing needs deleting', (tester) async {
    await pump(
      tester,
      rc: FakeRevenueCat(projects: ['p1']),
      ownWebhook: true,
    );
    expect(find.text('1 for this device stay · 0 other'), findsOneWidget);
    expect(find.text('Nothing left to delete'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('says when a sweep could not finish', (tester) async {
    final rc = FakeRevenueCat(projects: ['p1']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    await pump(tester, rc: rc);

    rc.offline = true;
    await tester.tap(find.text('Delete 1 other webhook'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete 1 other webhook').last,
    );
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);

    expect(
      find.text(
        'Some webhooks couldn’t be deleted. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });
}
