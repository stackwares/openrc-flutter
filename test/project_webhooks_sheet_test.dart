import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/notifications/widgets/project_webhooks_sheet.dart';
import 'package:openrc/features/settings/widgets/settings_rows.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

/// Waits for work in flight without hanging on a spinner that never stops.
const _settle = Duration(milliseconds: 50);
const _settleTimeout = Duration(seconds: 5);

/// An OpenRC webhook another device made, through an earlier notifier.
void _addOtherDevice(FakeRevenueCat rc) => rc.addForeign(
  'p1',
  name: 'OpenRC · iOS · abcdef',
  url: 'https://old-notifier.example.com/revenuecat/abcdef',
);

/// This device's webhook, written straight in: a request here would wait on
/// the test's fake clock.
void _addOwn(FakeRevenueCat rc, String secret) => rc.webhooks['p1']!.add({
  ...PushWebhooks.inputFor(secret, sandbox: false, kinds: PushKind.all).toJson(),
  'id': 'wh-own',
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// Opens the manager for `p1`, with every project's webhooks as [seed] set
  /// them up.
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
      _addOwn(rc, container.read(pushSettingsProvider).secret!);
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
                  onPressed: () => showProjectWebhooksSheet(context, 'p1'),
                  child: const Text('open manager'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open manager'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    return container;
  }


  testWidgets('shows a project\'s webhooks grouped by who made them', (
    tester,
  ) async {
    final rc = FakeRevenueCat(projects: ['p1']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    _addOtherDevice(rc);
    await pump(tester, rc: rc, ownWebhook: true);

    expect(find.text('Project p1'), findsOneWidget);
    expect(find.text('3 webhooks'), findsOneWidget);
    for (final heading in [
      'This device',
      'Other OpenRC webhooks',
      'Other webhooks',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.text('Slack'), findsOneWidget);
    expect(find.text('OpenRC · iOS · abcdef'), findsOneWidget);
    expect(find.text('hooks.example.com'), findsOneWidget);
    // The device\'s own webhook is named for the platform, and grouped first.
    expect(find.textContaining('OpenRC · Android · '), findsOneWidget);
  });

  testWidgets('deleting one webhook asks first, then removes it', (
    tester,
  ) async {
    final rc = FakeRevenueCat(projects: ['p1']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    await pump(tester, rc: rc);

    await tester.tap(_deleteButtonFor('Slack'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    expect(find.text('Delete “Slack”?'), findsOneWidget);

    // Cancelling keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    expect(rc.webhooks['p1'], hasLength(1));
    expect(find.text('Slack'), findsOneWidget);

    await tester.tap(_deleteButtonFor('Slack'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);

    expect(rc.webhooks['p1'], isEmpty);
    expect(find.text('Slack'), findsNothing);
    expect(find.text('This project has no webhooks.'), findsOneWidget);
  });

  testWidgets('names this device\'s own webhook as the one notifications use', (
    tester,
  ) async {
    final rc = FakeRevenueCat(projects: ['p1']);
    await pump(tester, rc: rc, ownWebhook: true);

    await tester.tap(_deleteButtonFor('OpenRC · Android · '));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    expect(
      find.textContaining('notifications stop for this project'),
      findsOneWidget,
    );
  });

  testWidgets('removes other OpenRC webhooks and keeps everything else', (
    tester,
  ) async {
    final rc = FakeRevenueCat(projects: ['p1']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    _addOtherDevice(rc);
    await pump(tester, rc: rc, ownWebhook: true);

    await tester.tap(find.text('Delete other OpenRC webhooks'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    expect(find.text('Delete 1 webhook'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 1 webhook'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);

    final names = rc.webhooks['p1']!.map((w) => w['name']).toList();
    expect(names, hasLength(2));
    expect(names, isNot(contains('OpenRC · iOS · abcdef')));
    expect(find.text('OpenRC · iOS · abcdef'), findsNothing);
    expect(find.text('Slack'), findsOneWidget);
    // Nothing left for it to sweep.
    expect(find.text('Delete other OpenRC webhooks'), findsNothing);
  });

  testWidgets('says when a deletion fails and keeps the row', (tester) async {
    final rc = FakeRevenueCat(projects: ['p1']);
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    await pump(tester, rc: rc);

    rc.offline = true;
    await tester.tap(_deleteButtonFor('Slack'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle(_settle, EnginePhase.sendSemanticsUpdate, _settleTimeout);

    expect(
      find.text('Couldn’t delete every webhook. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Slack'), findsOneWidget);
  });

  testWidgets('says when a project has no webhooks at all', (tester) async {
    await pump(tester, rc: FakeRevenueCat(projects: ['p1']));
    expect(find.text('0 webhooks'), findsOneWidget);
    expect(find.text('This project has no webhooks.'), findsOneWidget);
    expect(find.text('Delete other OpenRC webhooks'), findsNothing);
  });

  testWidgets('says when the webhooks can\'t be read', (tester) async {
    final rc = FakeRevenueCat(projects: ['p1'])..offline = true;
    await pump(tester, rc: rc);
    expect(
      find.text('Couldn’t load this project’s webhooks.'),
      findsOneWidget,
    );
  });
}

/// The trash button on the webhook row whose name contains [name].
Finder _deleteButtonFor(String name) => find.descendant(
  of: find.ancestor(
    of: find.textContaining(name),
    matching: find.byType(SettingsRow),
  ),
  matching: find.byIcon(Icons.delete_outline_rounded),
);
