import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/rc_webhook.dart';
import 'package:openrc/services/push/push_channel.dart';
import 'package:openrc/services/push/push_config.dart';
import 'package:openrc/services/push/push_display.dart';
import 'package:openrc/services/push/push_kinds.dart';
import 'package:openrc/services/push/push_names.dart';
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
      final found = await webhooks.findAll(secret);
      expect(found.keys, ['p2']);
      expect(found['p2']!.id, id);
      expect(found['p2']!.projectName, 'Project p2');
    });

    test('tells this device\'s webhooks from OpenRC\'s and other services',
        () {
      final own = RcWebhook(
        id: 'wh1',
        name: PushWebhooks.nameFor(secret),
        url: PushWebhooks.urlFor(secret),
      );
      final legacy = RcWebhook(
        id: 'wh2',
        name: 'OpenRC · Android · ${PushWebhooks.tagFor(secret)}',
        url: PushConfig.webhookUrl,
      );
      final otherDevice = RcWebhook(
        id: 'wh3',
        name: 'OpenRC · iOS · ${PushWebhooks.tagFor('B' * 43)}',
        url: '${PushConfig.webhookUrl}/${PushWebhooks.tagFor('B' * 43)}',
      );
      // An earlier notifier deployment: same path shape, another host.
      final olderDeployment = RcWebhook(
        id: 'wh4',
        name: 'OpenRC · Android · abcdef',
        url: 'https://old-notifier.example.workers.dev/revenuecat/abcdef',
      );
      final foreign = RcWebhook(
        id: 'wh5',
        name: 'Slack',
        url: 'https://hooks.example.com/x',
      );
      final nameless = RcWebhook(id: 'wh6');

      expect(PushWebhooks.ownerOf(own, secret), WebhookOwner.thisDevice);
      expect(PushWebhooks.ownerOf(legacy, secret), WebhookOwner.thisDevice);
      expect(PushWebhooks.ownerOf(otherDevice, secret), WebhookOwner.openRcOther);
      expect(
        PushWebhooks.ownerOf(olderDeployment, secret),
        WebhookOwner.openRcOther,
      );
      expect(PushWebhooks.ownerOf(foreign, secret), WebhookOwner.foreign);
      expect(PushWebhooks.ownerOf(nameless, secret), WebhookOwner.foreign);
    });

    test('lists every webhook in a project, marked with who made it', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign(
        'p1',
        name: 'OpenRC · iOS · abcdef',
        url: 'https://old-notifier.example.com/revenuecat/abcdef',
      );
      final webhooks = PushWebhooks(rc.api());
      await webhooks.add('p1', secret, sandbox: false, kinds: PushKind.all);

      final found = await webhooks.allFor('p1', secret);
      expect(
        found.map((w) => w.owner),
        [WebhookOwner.foreign, WebhookOwner.openRcOther, WebhookOwner.thisDevice],
      );
      expect(found.first.title, 'Slack');
      expect(found.first.webhook.host, 'hooks.example.com');
      // The one this device made sends every kind.
      expect(found.last.eventTypeCount, greaterThan(0));
    });

    test('deletes a set of webhooks, counting a gone one as done', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign('p1', name: 'Zapier', url: 'https://zapier.com/y');
      final webhooks = PushWebhooks(rc.api());
      final ids = [for (final w in rc.webhooks['p1']!) w['id'] as String];

      expect(await webhooks.removeMany('p1', ids), isEmpty);
      expect(rc.webhooks['p1'], isEmpty);

      // Already gone: the outcome asked for, not a failure.
      expect(await webhooks.removeMany('p1', ids), isEmpty);
    });

    test('reports the webhooks it could not delete', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      final webhooks = PushWebhooks(rc.api());
      rc.offline = true;
      final ids = [for (final w in rc.webhooks['p1']!) w['id'] as String];
      expect(await webhooks.removeMany('p1', ids), ids);
    });

    test('sweeps every webhook but this device\'s, in every project',
        () async {
      final rc = FakeRevenueCat(projects: ['p1', 'p2']);
      for (final id in ['p1', 'p2']) {
        rc.addForeign(id, name: 'Slack', url: 'https://hooks.example.com/x');
        rc.addForeign(
          id,
          name: 'OpenRC · iOS · abcdef',
          url: 'https://old.example.com/revenuecat/abcdef',
        );
      }
      final webhooks = PushWebhooks(rc.api());
      for (final id in ['p1', 'p2']) {
        await webhooks.add(id, secret, sandbox: false, kinds: PushKind.all);
      }

      final result = await webhooks.sweep(
        secret,
        projects: await webhooks.projects(),
      );
      expect(result.deleted, 4);
      expect(result.failed, 0);
      expect(result.ok, isTrue);
      // Only this device's webhook is left in each project.
      for (final id in ['p1', 'p2']) {
        expect(rc.webhooks[id], hasLength(1));
        expect(rc.webhooks[id]!.single['url'], PushWebhooks.urlFor(secret));
      }
    });

    test('a sweep leaves a project with nothing to delete alone', () async {
      final rc = FakeRevenueCat(projects: ['p1', 'p2']);
      final webhooks = PushWebhooks(rc.api());
      await webhooks.add('p1', secret, sandbox: false, kinds: PushKind.all);

      final result = await webhooks.sweep(
        secret,
        projects: await webhooks.projects(),
      );
      expect(result.deleted, 0);
      expect(result.failed, 0);
      expect(rc.requests.where((r) => r.startsWith('DELETE')), isEmpty);
    });

    test('a sweep counts what RevenueCat refused to delete', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      final webhooks = PushWebhooks(rc.api());
      final projects = await webhooks.projects();
      // The projects are known, but reading their webhooks fails.
      rc.offline = true;
      final result = await webhooks.sweep(secret, projects: projects);
      // The project couldn't even be read, so it counts as failed.
      expect(result.deleted, 0);
      expect(result.failed, greaterThan(0));
      expect(result.ok, isFalse);
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

    test('names the project in the URL for the notifier', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      final webhooks = PushWebhooks(rc.api());
      final id = await webhooks.add(
        'p1',
        secret,
        sandbox: false,
        kinds: PushKind.all,
        projectName: 'My App',
      );
      final hook = rc.webhooks['p1']!.single;
      expect(hook['url'], '${PushWebhooks.urlFor(secret)}?project=My+App');
      // The tag still finds it, whatever the query.
      expect(await webhooks.find('p1', secret), id);
    });

    test('carries product names for the notifier', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      final webhooks = PushWebhooks(rc.api());
      final id = await webhooks.add(
        'p1',
        secret,
        sandbox: false,
        kinds: PushKind.all,
        names: PushNames({'com.acme.pro': 'Pro'}),
      );
      final hook = rc.webhooks['p1']!.single;
      expect(hook['url'], endsWith('?names=com.acme.pro%0APro'));
      // The tag still finds it, whatever the query.
      expect(await webhooks.find('p1', secret), id);
    });

    test('carries the project\'s icon for the notifier', () async {
      final rc = FakeRevenueCat(projects: ['p1']);
      final webhooks = PushWebhooks(rc.api());
      final id = await webhooks.add(
        'p1',
        secret,
        sandbox: false,
        kinds: PushKind.all,
        projectIcon: 'https://is1-ssl.mzstatic.com/image/thumb/App/512x512bb.png',
      );
      final hook = rc.webhooks['p1']!.single;
      expect(
        hook['url'],
        endsWith(
          '?icon=https%3A%2F%2Fis1-ssl.mzstatic.com%2Fimage%2Fthumb%2FApp%2F512x512bb.png',
        ),
      );
      expect(await webhooks.find('p1', secret), id);
    });

    test('only carries icons a push can fetch', () {
      expect(PushWebhooks.iconParam(null), isNull);
      expect(PushWebhooks.iconParam('   '), isNull);
      expect(PushWebhooks.iconParam('http://example.com/a.png'), isNull);
      expect(PushWebhooks.iconParam('https://'), isNull);
      expect(PushWebhooks.iconParam('javascript:alert(1)'), isNull);
      expect(PushWebhooks.iconParam('https://example.com/a b.png'), isNull);
      expect(
        PushWebhooks.iconParam('https://example.com/${'a' * 1024}'),
        isNull,
      );
      expect(
        PushWebhooks.iconParam(' https://example.com/a.png '),
        'https://example.com/a.png',
      );
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
      await notifier.firstLoad;
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

    test('adds product names to a webhook that has none', () async {
      final secret = container.read(pushSettingsProvider).secret!;
      await container
          .read(pushSettingsProvider.notifier)
          .setNames(PushNames({'com.acme.pro': 'Pro'}));
      // Written straight in, as an older app version left it: no names.
      rc.webhooks['p2']!.add({
        ...PushWebhooks.inputFor(
          secret,
          sandbox: false,
          kinds: PushKind.all,
        ).toJson(),
        'id': 'own-p2',
      });
      expect(rc.webhooks['p2']!.single['url'], isNot(contains('names=')));

      await loaded();
      expect(
        rc.webhooks['p2']!.single['url'],
        contains('names=com.acme.pro%0APro'),
      );
    });

    test('connecting a project sends every setting the push reads', () async {
      // A webhook written without these reads raw product ids and US dollars
      // until something else refreshes it: connecting is the moment a device
      // hands its settings to the notifier.
      await container
          .read(pushSettingsProvider.notifier)
          .setNames(PushNames({'com.acme.pro': 'Pro'}));
      await container
          .read(pushSettingsProvider.notifier)
          .setDisplay(
            const PushDisplay(currency: 'EUR', language: 'de', rate: 0.92),
          );

      final notifier = await loaded();
      expect(await notifier.apply({'p2'}), 0);

      final url = rc.webhooks['p2']!.single['url'] as String;
      expect(url, contains('names=com.acme.pro%0APro'));
      expect(url, contains('lang=de'));
      expect(url, contains('currency=EUR'));
      expect(url, contains('project=Project+p2'));
    });

    test('says when the project list can\'t load', () async {
      rc.offline = true;
      await loaded();
      expect(container.read(pushProjectsProvider).failed, isTrue);
    });

    test('names the project in a webhook from before URLs did', () async {
      final secret = container.read(pushSettingsProvider).secret!;
      await PushWebhooks(
        rc.api(),
      ).add('p2', secret, sandbox: false, kinds: PushKind.all);
      expect(rc.webhooks['p2']!.single['url'], isNot(contains('project=')));

      await loaded();
      expect(rc.webhooks['p2']!.single['url'], endsWith('?project=Project+p2'));
    });

    test('adds the project\'s icon to a webhook that has none', () async {
      rc.icons['p2'] = 'https://is1-ssl.mzstatic.com/image/thumb/App/512x512bb.png';
      final secret = container.read(pushSettingsProvider).secret!;
      await PushWebhooks(
        rc.api(),
      ).add('p2', secret, sandbox: false, kinds: PushKind.all);
      expect(rc.webhooks['p2']!.single['url'], isNot(contains('icon=')));

      await loaded();
      expect(
        rc.webhooks['p2']!.single['url'],
        contains('icon=https%3A%2F%2Fis1-ssl.mzstatic.com'),
      );
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

  group('project webhooks manager', () {
    late FakeRevenueCat rc;
    late ProviderContainer container;

    setUp(() async {
      rc = FakeRevenueCat(projects: ['p1', 'p2']);
      container = ProviderContainer(
        overrides: [
          pushMessagingProvider.overrideWithValue(FakePushMessaging()),
          rcApiServiceProvider.overrideWithValue(rc.api()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(pushSettingsProvider.notifier).enable();
    });

    Future<ProjectWebhooksNotifier> opened() async {
      container.listen(projectWebhooksProvider('p1'), (_, _) {});
      final notifier = container.read(projectWebhooksProvider('p1').notifier);
      await notifier.firstLoad;
      return notifier;
    }

    test('lists a project\'s webhooks by owner', () async {
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign(
        'p1',
        name: 'OpenRC · iOS · abcdef',
        url: 'https://old.example.com/revenuecat/abcdef',
      );
      final secret = container.read(pushSettingsProvider).secret!;
      await PushWebhooks(
        rc.api(),
      ).add('p1', secret, sandbox: false, kinds: PushKind.all);

      await opened();
      final state = container.read(projectWebhooksProvider('p1'));
      expect(state.loading, isFalse);
      expect(state.ownedBy(WebhookOwner.thisDevice), hasLength(1));
      expect(state.ownedBy(WebhookOwner.openRcOther), hasLength(1));
      expect(state.ownedBy(WebhookOwner.foreign), hasLength(1));
    });

    test('deletes one webhook and drops it from the list', () async {
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      final notifier = await opened();
      final id = container
          .read(projectWebhooksProvider('p1'))
          .webhooks
          .single
          .id;

      expect(await notifier.delete(id), isTrue);
      expect(rc.webhooks['p1'], isEmpty);
      expect(container.read(projectWebhooksProvider('p1')).webhooks, isEmpty);
      expect(
        rc.requests,
        contains('DELETE /me/projects/p1/integrations/webhooks/$id'),
      );
    });

    test('deletes other OpenRC webhooks and keeps the rest', () async {
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign(
        'p1',
        name: 'OpenRC · iOS · abcdef',
        url: 'https://old.example.com/revenuecat/abcdef',
      );
      final secret = container.read(pushSettingsProvider).secret!;
      await PushWebhooks(
        rc.api(),
      ).add('p1', secret, sandbox: false, kinds: PushKind.all);

      final notifier = await opened();
      expect(
        await notifier.deleteOwnedBy(WebhookOwner.openRcOther),
        isTrue,
      );
      final names = rc.webhooks['p1']!.map((w) => w['name']).toList();
      expect(names, hasLength(2));
      expect(names, isNot(contains('OpenRC · iOS · abcdef')));
      expect(
        container
            .read(projectWebhooksProvider('p1'))
            .ownedBy(WebhookOwner.openRcOther),
        isEmpty,
      );
    });

    test('losing this device\'s webhook makes the project read as off',
        () async {
      final secret = container.read(pushSettingsProvider).secret!;
      await PushWebhooks(
        rc.api(),
      ).add('p1', secret, sandbox: false, kinds: PushKind.all);
      container.listen(pushProjectsProvider, (_, _) {});
      await container.read(pushProjectsProvider.notifier).firstLoad;
      expect(
        container.read(pushProjectsProvider).projects.first.connected,
        isTrue,
      );

      final notifier = await opened();
      await notifier.deleteOwnedBy(WebhookOwner.thisDevice);
      // The notification list refreshes itself, so let that finish.
      for (var i = 0; i < 200; i++) {
        final projects = container.read(pushProjectsProvider);
        if (!projects.loading && projects.projects.isNotEmpty) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        container.read(pushProjectsProvider).projects.first.connected,
        isFalse,
      );
    });

    test('says when a deletion failed and keeps the row', () async {
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      final notifier = await opened();
      final id = container
          .read(projectWebhooksProvider('p1'))
          .webhooks
          .single
          .id;

      rc.offline = true;
      expect(await notifier.delete(id), isFalse);
      final state = container.read(projectWebhooksProvider('p1'));
      expect(state.deleteFailed, isTrue);
      expect(state.webhooks, hasLength(1));
      expect(state.deleting, isEmpty);
      expect(rc.webhooks['p1'], hasLength(1));
    });

    test('says when the webhooks can\'t be read', () async {
      rc.offline = true;
      await opened();
      final state = container.read(projectWebhooksProvider('p1'));
      expect(state.failed, isTrue);
      expect(state.loading, isFalse);
    });
  });

  group('webhook sweep', () {
    late FakeRevenueCat rc;
    late ProviderContainer container;

    setUp(() async {
      rc = FakeRevenueCat(projects: ['p1', 'p2']);
      container = ProviderContainer(
        overrides: [
          pushMessagingProvider.overrideWithValue(FakePushMessaging()),
          rcApiServiceProvider.overrideWithValue(rc.api()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(pushSettingsProvider.notifier).enable();
    });

    Future<WebhookSweepNotifier> opened() async {
      container.listen(webhookSweepProvider, (_, _) {});
      final notifier = container.read(webhookSweepProvider.notifier);
      await notifier.firstLoad;
      return notifier;
    }

    /// This device's webhook, written straight in: a request would wait on
    /// the test's fake clock.
    void addOwn(String projectId) {
      final secret = container.read(pushSettingsProvider).secret!;
      rc.webhooks[projectId]!.add({
        ...PushWebhooks.inputFor(
          secret,
          sandbox: false,
          kinds: PushKind.all,
        ).toJson(),
        'id': 'own-$projectId',
      });
    }

    test('counts what a sweep would delete, project by project', () async {
      addOwn('p1');
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign(
        'p1',
        name: 'OpenRC · iOS · abcdef',
        url: 'https://old.example.com/revenuecat/abcdef',
      );

      await opened();
      final state = container.read(webhookSweepProvider);
      expect(state.loading, isFalse);
      expect(state.mine, 1);
      expect(state.others, 2);
      final p1 = state.projects.firstWhere((p) => p.id == 'p1');
      expect(p1.mine, 1);
      expect(p1.others, 2);
    });

    test('sweeps and keeps this device\'s webhooks', () async {
      addOwn('p1');
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      rc.addForeign('p2', name: 'Zapier', url: 'https://zapier.com/y');

      final notifier = await opened();
      expect(container.read(webhookSweepProvider).others, 2);
      await notifier.sweep();

      expect(rc.webhooks['p1']!.single['id'], 'own-p1');
      expect(rc.webhooks['p2'], isEmpty);
      final result = container.read(webhookSweepProvider).result;
      expect(result?.deleted, 2);
      expect(result?.ok, isTrue);
      // The counts are read again after a sweep; let that land.
      for (var i = 0; i < 200; i++) {
        final state = container.read(webhookSweepProvider);
        if (!state.loading && state.others == 0) break;
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(webhookSweepProvider).others, 0);
    });

    test('says when a sweep could not delete everything', () async {
      rc.addForeign('p1', name: 'Slack', url: 'https://hooks.example.com/x');
      final notifier = await opened();
      rc.offline = true;
      await notifier.sweep();

      final state = container.read(webhookSweepProvider);
      expect(state.result?.ok, isFalse);
      expect(rc.webhooks['p1'], hasLength(1));
    });

    test('a sweep with nothing to delete asks RevenueCat nothing', () async {
      addOwn('p1');
      final notifier = await opened();
      expect(container.read(webhookSweepProvider).others, 0);
      await notifier.sweep();
      expect(container.read(webhookSweepProvider).result?.deleted, 0);
      expect(rc.requests.where((r) => r.startsWith('DELETE')), isEmpty);
    });
  });
}
