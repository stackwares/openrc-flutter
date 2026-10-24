import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/notifications/notifications_screen.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required PushMessaging push,
    required RcApiService api,
  }) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushMessagingProvider.overrideWithValue(push),
          rcApiServiceProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: const NotificationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen)),
    );
  }

  testWidgets('turning on picks projects, sets them up and tests', (
    tester,
  ) async {
    final push = FakePushMessaging();
    final rc = FakeRevenueCat();
    final container = await pump(tester, push: push, api: rc.api());

    // What notifications look like, before anything is asked.
    expect(find.text('🔵 New subscription · \$9.99'), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();

    // Every project starts ticked.
    expect(find.text('Which projects?'), findsOneWidget);
    expect(find.text('2 of 2 selected'), findsOneWidget);
    await tester.tap(find.text('Project p2'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 selected'), findsOneWidget);
    await tester.tap(find.text('Turn on for 1 project'));
    await tester.pumpAndSettle();

    final secret = container.read(pushSettingsProvider).secret!;
    expect(push.topics, {PushChannel.topicFor(secret)});
    expect(rc.webhooks['p1'], hasLength(1));
    expect(rc.webhooks['p2'], isEmpty);
    expect(find.text('You’re all set'), findsOneWidget);
    expect(
      find.text('Test sent. It should arrive in a moment.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications are on'), findsOneWidget);
    expect(
      find.text('Notifying this device for 1 of 2 projects'),
      findsOneWidget,
    );

    // A project's switch applies straight away.
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Project p2'),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(rc.webhooks['p2'], hasLength(1));
    expect(
      find.text('Notifying this device for 2 of 2 projects'),
      findsOneWidget,
    );
  });

  testWidgets('choosing what to hear about updates every project', (
    tester,
  ) async {
    final rc = FakeRevenueCat();
    await pump(tester, push: FakePushMessaging(), api: rc.api());
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 2 projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('New customers'), 200);
    await tester.tap(find.text('New customers'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    for (final id in ['p1', 'p2']) {
      expect(
        rc.webhooks[id]!.single['url'],
        endsWith('?notify=new,trial,conversion,purchase&project=Project+$id'),
      );
    }
    expect(find.text('Saved for your projects'), findsOneWidget);

    // One project gets its own choice: trials only.
    await tester.scrollUntilVisible(find.text('Project p1'), -200);
    await tester.tap(find.text('Project p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    for (final kind in [
      'New subscriptions',
      'Trial conversions',
      'One-time purchases',
    ]) {
      await tester.tap(find.text(kind).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      rc.webhooks['p1']!.single['url'],
      endsWith('?notify=trial&project=Project+p1'),
    );
    expect(
      rc.webhooks['p2']!.single['url'],
      endsWith('?notify=new,trial,conversion,purchase&project=Project+p2'),
    );
    expect(find.text('Own choice · 1 kind'), findsOneWidget);
  });

  testWidgets('the app bar opens the sweep for every project', (
    tester,
  ) async {
    final rc = FakeRevenueCat();
    rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
    await pump(tester, push: FakePushMessaging(), api: rc.api());
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    // Still choosing projects, which is where a full project leaves you: the
    // sweep is reachable from here, before any webhook of this device's
    // exists.
    expect(find.text('Which projects?'), findsOneWidget);

    await tester.tap(find.byTooltip('All webhooks'));
    await tester.pumpAndSettle();
    expect(find.text('All webhooks'), findsWidgets);
    expect(find.text('0 for this device stay · 1 other'), findsOneWidget);
    expect(find.text('Delete 1 other webhook'), findsOneWidget);
  });

  testWidgets('a project opens its webhook manager', (tester) async {
    final rc = FakeRevenueCat();
    await pump(tester, push: FakePushMessaging(), api: rc.api());
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 2 projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Project p1'), -200);
    await tester.tap(find.text('Project p1'));
    await tester.pumpAndSettle();
    expect(find.text('See and delete the webhooks in this project'), findsOneWidget);

    await tester.tap(find.text('Webhooks'));
    await tester.pumpAndSettle();
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('1 webhook'), findsOneWidget);
  });

  testWidgets('turning off asks first, then removes the webhooks', (
    tester,
  ) async {
    final push = FakePushMessaging();
    final rc = FakeRevenueCat();
    await pump(tester, push: push, api: rc.api());
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 2 projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Turn off notifications'), 200);
    await tester.tap(find.text('Turn off notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off notifications?'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Turn off notifications'),
    );
    await tester.pumpAndSettle();

    expect(rc.webhooks['p1'], isEmpty);
    expect(rc.webhooks['p2'], isEmpty);
    expect(push.topics, isEmpty);
    expect(find.text('Turn on notifications'), findsOneWidget);
  });

  testWidgets('a project RevenueCat refuses says why', (tester) async {
    final rc = FakeRevenueCat(projects: ['p1'])
      ..refuseCreate = 'Webhooks are available on the Pro plan.';
    await pump(tester, push: FakePushMessaging(), api: rc.api());
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 1 project'));
    await tester.pumpAndSettle();
    expect(
      find.text('Webhooks are available on the Pro plan.'),
      findsOneWidget,
    );
    expect(
      find.text('1 project couldn’t be set up. Try again.'),
      findsOneWidget,
    );
    expect(find.text('You’re all set'), findsNothing);
  });

  testWidgets('says when the system blocks notifications', (tester) async {
    await pump(
      tester,
      push: FakePushMessaging(allowed: false),
      api: FakeRevenueCat().api(),
    );
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Notifications are turned off for OpenRC'),
      findsOneWidget,
    );
    expect(find.text('Which projects?'), findsNothing);
  });

  testWidgets('manual setup shows the URL and this device\'s header', (
    tester,
  ) async {
    final container = await pump(
      tester,
      push: FakePushMessaging(),
      api: FakeRevenueCat().api(),
    );
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on for 2 projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Set up manually'), 200);
    await tester.tap(find.text('Set up manually'));
    await tester.pumpAndSettle();
    final secret = container.read(pushSettingsProvider).secret!;
    expect(find.text(PushWebhooks.urlFor(secret)), findsOneWidget);
    expect(find.text('Bearer $secret'), findsOneWidget);
  });
}
