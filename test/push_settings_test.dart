import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

void main() {
  final secret = 'A' * 43;
  final otherSecret = 'B' * 43;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('turning on makes a secret and subscribes to its topic', () async {
    final messaging = FakePushMessaging();
    final notifier = PushSettingsNotifier(messaging);

    expect(await notifier.enable(), PushEnableResult.enabled);
    final saved = notifier.state.secret!;
    expect(notifier.state.enabled, isTrue);
    expect(PushChannel.parse(saved), saved);
    expect(messaging.topics, {PushChannel.topicFor(saved)});

    // Next launch: still on, with the same secret, and subscribed again.
    final next = FakePushMessaging();
    final restored = PushSettingsNotifier(next);
    await pumpEventQueue();
    expect(restored.state.enabled, isTrue);
    expect(restored.state.secret, saved);
    expect(next.topics, {PushChannel.topicFor(saved)});
  });

  test('a refused permission stays off and says so', () async {
    final notifier = PushSettingsNotifier(FakePushMessaging(allowed: false));
    expect(await notifier.enable(), PushEnableResult.blocked);
    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.blocked, isTrue);
  });

  test('a failed subscription reports failure and stays off', () async {
    final messaging = FakePushMessaging()..failSubscribe = true;
    final notifier = PushSettingsNotifier(messaging);
    expect(await notifier.enable(), PushEnableResult.failed);
    expect(notifier.state.enabled, isFalse);
  });

  test('turning off keeps the secret for RevenueCat\'s webhook', () async {
    FlutterSecureStorage.setMockInitialValues({'push_secret_v1': secret});
    SharedPreferences.setMockInitialValues({'push_enabled_v1': true});
    final messaging = FakePushMessaging();
    final notifier = PushSettingsNotifier(messaging);
    await pumpEventQueue();
    expect(messaging.topics, {PushChannel.topicFor(secret)});

    await notifier.disable();
    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.secret, secret);
    expect(messaging.topics, isEmpty);

    expect(await notifier.enable(), PushEnableResult.enabled);
    expect(notifier.state.secret, secret);
    expect(messaging.topics, {PushChannel.topicFor(secret)});
  });

  test('turning off removes this device\'s webhooks, not others\'', () async {
    final rc = FakeRevenueCat();
    final webhooks = PushWebhooks(rc.api());
    final notifier = PushSettingsNotifier(FakePushMessaging(), webhooks);
    await notifier.enable();
    final mine = notifier.state.secret!;
    await webhooks.add('p1', mine, sandbox: false, kinds: PushKind.all);
    await webhooks.add('p2', mine, sandbox: false, kinds: PushKind.all);
    await webhooks.add('p2', otherSecret, sandbox: false, kinds: PushKind.all);

    await notifier.disable();
    expect(rc.webhooks['p1'], isEmpty);
    expect(rc.webhooks['p2'], hasLength(1));
    expect(await webhooks.find('p2', otherSecret), isNotNull);
  });

  test('webhooks left behind offline are removed on a later launch', () async {
    final rc = FakeRevenueCat();
    final webhooks = PushWebhooks(rc.api());
    final notifier = PushSettingsNotifier(FakePushMessaging(), webhooks);
    await notifier.enable();
    await webhooks.add(
      'p1',
      notifier.state.secret!,
      sandbox: false,
      kinds: PushKind.all,
    );

    rc.offline = true;
    await notifier.clear();
    expect(notifier.state.secret, isNull);
    expect(rc.webhooks['p1'], hasLength(1));

    rc.offline = false;
    final next = PushSettingsNotifier(FakePushMessaging(), webhooks);
    await next.retryPendingRemovals();
    expect(rc.webhooks['p1'], isEmpty);
    // Nothing is left to retry.
    rc.requests.clear();
    await next.retryPendingRemovals();
    expect(rc.requests, isEmpty);
  });

  test('the sandbox switch updates this device\'s webhooks', () async {
    final rc = FakeRevenueCat();
    final webhooks = PushWebhooks(rc.api());
    final notifier = PushSettingsNotifier(FakePushMessaging(), webhooks);
    await notifier.enable();
    await webhooks.add(
      'p1',
      notifier.state.secret!,
      sandbox: false,
      kinds: PushKind.all,
    );

    expect(await notifier.setSandbox(true), isTrue);
    expect(notifier.state.sandbox, isTrue);
    expect(rc.webhooks['p1']!.single['environment'], isNull);

    rc.offline = true;
    expect(await notifier.setSandbox(false), isFalse);
  });

  test('choosing kinds updates the projects that follow the choice', () async {
    final rc = FakeRevenueCat();
    final webhooks = PushWebhooks(rc.api());
    final notifier = PushSettingsNotifier(FakePushMessaging(), webhooks);
    await notifier.enable();
    final secret = notifier.state.secret!;
    await webhooks.add('p1', secret, sandbox: false, kinds: PushKind.all);
    await webhooks.add('p2', secret, sandbox: false, kinds: PushKind.all);

    expect(await notifier.setProjectKinds('p2', {PushKind.refund}), isTrue);
    expect(rc.webhooks['p2']!.single['url'], endsWith('?notify=refund'));

    expect(await notifier.setKinds({PushKind.trial}), isTrue);
    expect(rc.webhooks['p1']!.single['url'], endsWith('?notify=trial'));
    expect(rc.webhooks['p1']!.single['event_types'], ['INITIAL_PURCHASE']);
    // p2 keeps its own choice.
    expect(rc.webhooks['p2']!.single['url'], endsWith('?notify=refund'));

    // Back to the shared choice.
    await notifier.setProjectKinds('p2', null);
    expect(rc.webhooks['p2']!.single['url'], endsWith('?notify=trial'));

    // Choices outlive a restart.
    final next = PushSettingsNotifier(FakePushMessaging(), webhooks);
    await pumpEventQueue();
    expect(next.state.kinds, {PushKind.trial});
    expect(next.state.projectKinds, isEmpty);
    expect(await notifier.setKinds({}), isFalse);
  });

  test('signing out removes webhooks and forgets the secret', () async {
    final rc = FakeRevenueCat();
    final webhooks = PushWebhooks(rc.api());
    final messaging = FakePushMessaging();
    final notifier = PushSettingsNotifier(messaging, webhooks);
    await notifier.enable();
    await webhooks.add(
      'p1',
      notifier.state.secret!,
      sandbox: false,
      kinds: PushKind.all,
    );
    await notifier.rememberProjects({'p1', 'p2'});
    await notifier.clear();
    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.secret, isNull);
    expect(notifier.state.knownProjects, isEmpty);
    expect(messaging.topics, isEmpty);
    expect(rc.webhooks['p1'], isEmpty);

    final next = PushSettingsNotifier(FakePushMessaging());
    await pumpEventQueue();
    expect(next.state.secret, isNull);
  });

  test('builds without Firebase do nothing', () async {
    final notifier = PushSettingsNotifier(null);
    expect(await notifier.enable(), PushEnableResult.failed);
    await notifier.clear();
    expect(notifier.state.enabled, isFalse);
  });
}
