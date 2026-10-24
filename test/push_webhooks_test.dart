import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_config.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/push/push_webhooks.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

void main() {
  final secret = 'A' * 43;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('PushWebhooks', () {
    test('adds a production webhook for the notifying events', () async {
      final rc = FakeRevenueCat();
      final id = await PushWebhooks(
        rc.api(),
      ).add('p1', secret, sandbox: false, kinds: PushKind.all);

      final hook = rc.webhooks['p1']!.single;
      expect(hook['id'], id);
      expect(
        hook['url'],
        '${PushConfig.webhookUrl}/${PushWebhooks.tagFor(secret)}',
      );
      expect(hook['authorization_header'], 'Bearer $secret');
      expect(hook['environment'], 'production');
      expect(hook['event_types'], PushKind.eventTypesFor(PushKind.all));
      expect(hook['event_types'], isNot(contains('PAYWALL_IMPRESSION')));
      expect(hook['name'], startsWith('OpenRC · '));
      expect(hook['name'], endsWith(PushWebhooks.tagFor(secret)));
      expect(
        rc.requests,
        contains('POST /me/projects/p1/integrations/webhooks'),
      );
    });

    test('adding again updates the same webhook', () async {
      final rc = FakeRevenueCat();
      final webhooks = PushWebhooks(rc.api());
      final first = await webhooks.add(
        'p1',
        secret,
        sandbox: false,
        kinds: PushKind.all,
      );
      final second = await webhooks.add(
        'p1',
        secret,
        sandbox: true,
        kinds: PushKind.all,
      );
      expect(second, first);
      expect(rc.webhooks['p1'], hasLength(1));
      expect(rc.webhooks['p1']!.single['environment'], isNull);
    });

    test('finds only this device\'s webhooks', () async {
      final rc = FakeRevenueCat();
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign(
        'p1',
        name: 'OpenRC · iOS · ${PushWebhooks.tagFor('B' * 43)}',
        url: PushConfig.webhookUrl,
      );
      final webhooks = PushWebhooks(rc.api());
      expect(await webhooks.find('p1', secret), isNull);

      final id = await webhooks.add(
        'p2',
        secret,
        sandbox: false,
        kinds: PushKind.all,
      );
      expect(await webhooks.findAll(secret), {'p2': id});
    });

    test('two devices get separate webhooks in one project', () async {
      // RevenueCat refuses a second webhook with the same URL in a project.
      final rc = FakeRevenueCat(projects: ['p1']);
      final webhooks = PushWebhooks(rc.api());
      await webhooks.add('p1', secret, sandbox: false, kinds: PushKind.all);
      await webhooks.add('p1', 'B' * 43, sandbox: false, kinds: PushKind.all);
      final urls = rc.webhooks['p1']!.map((w) => w['url']).toSet();
      expect(urls, hasLength(2));
    });

    test('finds and updates a webhook from before URLs had tags', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      rc.addForeign(
        'p1',
        name: 'OpenRC · Android · ${PushWebhooks.tagFor(secret)}',
        url: PushConfig.webhookUrl,
      );
      final webhooks = PushWebhooks(rc.api());
      final id = await webhooks.find('p1', secret);
      expect(id, isNotNull);
      expect(
        await webhooks.add('p1', secret, sandbox: false, kinds: PushKind.all),
        id,
      );
      expect(rc.webhooks['p1']!.single['url'], PushWebhooks.urlFor(secret));
    });

    test('a webhook for some kinds names them and finds itself', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      final webhooks = PushWebhooks(rc.api());
      final id = await webhooks.add(
        'p1',
        secret,
        sandbox: false,
        kinds: {PushKind.trial, PushKind.newSubscription},
      );
      final hook = rc.webhooks['p1']!.single;
      expect(hook['url'], '${PushWebhooks.urlFor(secret)}?notify=new,trial');
      expect(hook['event_types'], ['INITIAL_PURCHASE']);
      expect(await webhooks.find('p1', secret), id);
    });

    test('the tag names a secret without giving it away', () {
      final tag = PushWebhooks.tagFor(secret);
      expect(tag, hasLength(6));
      expect(secret, isNot(contains(tag)));
      expect(PushWebhooks.tagFor('B' * 43), isNot(tag));
    });

    test('passes on RevenueCat\'s test result', () async {
      final rc = FakeRevenueCat()..testResponseCode = 401;
      final webhooks = PushWebhooks(rc.api());
      final id = await webhooks.add(
        'p1',
        secret,
        sandbox: false,
        kinds: PushKind.all,
      );
      final result = await webhooks.test('p1', id);
      expect(result.successful, isFalse);
      expect(result.responseCode, 401);
    });
  });

  group('projects sheet state', () {
    late FakeRevenueCat rc;
    late ProviderContainer container;

    setUp(() async {
      rc = FakeRevenueCat(projects: ['p1', 'p2', 'p3']);
      container = ProviderContainer(
        overrides: [
          pushMessagingProvider.overrideWithValue(FakePushMessaging()),
          rcApiServiceProvider.overrideWithValue(rc.api()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(pushSettingsProvider.notifier).enable();
    });

    Future<PushProjectsNotifier> loaded() async {
      container.listen(pushProjectsProvider, (_, _) {});
      final notifier = container.read(pushProjectsProvider.notifier);
      await pumpEventQueue();
      expect(container.read(pushProjectsProvider).loading, isFalse);
      return notifier;
    }

    test('connects and disconnects projects', () async {
      final notifier = await loaded();
      expect(container.read(pushProjectsProvider).connectedCount, 0);

      expect(await notifier.apply({'p1', 'p3'}), 0);
      expect(rc.webhooks['p1'], hasLength(1));
      expect(rc.webhooks['p2'], isEmpty);
      expect(rc.webhooks['p3'], hasLength(1));
      expect(container.read(pushProjectsProvider).connectedCount, 2);
      expect(container.read(pushSettingsProvider).knownProjects, {
        'p1',
        'p2',
        'p3',
      });

      expect(await notifier.apply({'p3'}), 0);
      expect(rc.webhooks['p1'], isEmpty);
      expect(rc.webhooks['p3'], hasLength(1));
    });

    test('shows RevenueCat\'s reason when a project fails', () async {
      final notifier = await loaded();
      rc.refuseCreate = 'Webhooks are available on the Pro plan.';
      expect(await notifier.apply({'p1'}), 1);
      final p1 = container
          .read(pushProjectsProvider)
          .projects
          .firstWhere((p) => p.id == 'p1');
      expect(p1.connected, isFalse);
      expect(p1.error, 'Webhooks are available on the Pro plan.');
    });

    test('sends the test event through a connected project', () async {
      final notifier = await loaded();
      expect(await notifier.sendTest(), isNull);
      await notifier.apply({'p2'});
      final result = await notifier.sendTest();
      expect(result?.successful, isTrue);
      expect(
        rc.requests.last,
        startsWith('POST /me/projects/p2/integrations/webhooks/'),
      );
    });

    test('says when the project list can\'t load', () async {
      rc.offline = true;
      await loaded();
      expect(container.read(pushProjectsProvider).failed, isTrue);
    });

    test('reads existing webhooks as connected', () async {
      final secret = container.read(pushSettingsProvider).secret!;
      await PushWebhooks(
        rc.api(),
      ).add('p2', secret, sandbox: false, kinds: PushKind.all);
      await loaded();
      final connected = container
          .read(pushProjectsProvider)
          .projects
          .where((p) => p.connected)
          .map((p) => p.id);
      expect(connected, ['p2']);
      expect(PushChannel.parse(secret), secret);
    });
  });
}
