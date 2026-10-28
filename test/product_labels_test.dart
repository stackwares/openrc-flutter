import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/models/product_labels.dart';
import 'package:openrc/services/product_labels_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProductLabels model', () {
    test('survives a JSON round trip', () {
      const labels = ProductLabels(
        apps: {
          'app1': AppProductLabels(
            products: {
              'pro_monthly': ProductLabel(name: 'Pro', planId: 'pro'),
              'max_yearly': ProductLabel(name: 'Max'),
            },
            plans: {'pro': ProductPlan(id: 'pro', name: 'Pro')},
          ),
        },
      );
      final decoded = ProductLabels.fromJson(
        jsonDecode(jsonEncode(labels.toJson())),
      );
      final app = decoded.forApp('app1');
      expect(app.nameOf('pro_monthly'), 'Pro');
      expect(app.planName(app.planIdOf('pro_monthly')), 'Pro');
      expect(app.nameOf('max_yearly'), 'Max');
      expect(app.planIdOf('max_yearly'), isNull);
    });

    test('a plan that is no longer stored leaves the name behind', () {
      final labels = ProductLabels.fromJson({
        'apps': {
          'app1': {
            'products': {
              'p1': {'name': 'Pro', 'plan': 'gone'},
            },
            'plans': <String, dynamic>{},
          },
        },
      });
      expect(labels.displayName('app1', 'p1'), 'Pro');
      expect(labels.forApp('app1').planIdOf('p1'), isNull);
    });

    test('blank labels are dropped and blanks read as no name', () {
      final labels = ProductLabels.fromJson({
        'apps': {
          'app1': {
            'products': {
              'p1': {'name': '   '},
            },
          },
        },
      });
      expect(labels.isEmpty, isTrue);
      expect(labels.displayName('app1', 'p1'), isNull);
      expect(labels.displayName('app1', null), isNull);
    });

    test('an emptied app is removed from the map', () {
      const labels = ProductLabels(apps: {'a': AppProductLabels(plans: {})});
      expect(labels.withApp('a', const AppProductLabels()).apps, isEmpty);
    });

    test('plan slugs read like ids', () {
      expect(productPlanSlug('Pro Annual'), 'pro-annual');
      expect(productPlanSlug('  '), 'plan');
    });
  });

  group('ProductLabelsNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('names are per app', () async {
      final notifier = ProductLabelsNotifier();
      await notifier.ready;
      await notifier.setName('app1', 'pro_monthly', 'Pro');
      await notifier.setName('app2', 'pro_monthly', 'Basic');

      expect(notifier.state.displayName('app1', 'pro_monthly'), 'Pro');
      expect(notifier.state.displayName('app2', 'pro_monthly'), 'Basic');
    });

    test('a plan is shared by name and renamed once', () async {
      final notifier = ProductLabelsNotifier();
      await notifier.ready;
      await notifier.setPlan('app1', 'pro_monthly', 'Pro');
      await notifier.setPlan('app1', 'pro_yearly', 'pro');

      final app = notifier.state.forApp('app1');
      expect(app.plans, hasLength(1));
      expect(app.planIdOf('pro_yearly'), app.planIdOf('pro_monthly'));

      await notifier.renamePlan('app1', app.planIdOf('pro_monthly')!, 'Plus');
      expect(notifier.state.planName('app1', 'pro_yearly'), 'Plus');
    });

    test('deleting a plan keeps the product names', () async {
      final notifier = ProductLabelsNotifier();
      await notifier.ready;
      await notifier.setName('app1', 'p1', 'Pro');
      await notifier.setPlan('app1', 'p1', 'Pro');
      await notifier.deletePlan('app1', 'pro');

      final app = notifier.state.forApp('app1');
      expect(app.plans, isEmpty);
      expect(app.nameOf('p1'), 'Pro');
      expect(app.planIdOf('p1'), isNull);
    });

    test('one undo takes back a run across apps', () async {
      final notifier = ProductLabelsNotifier();
      await notifier.ready;
      await notifier.applyAll({
        'app1': {'p1': const ProductLabelUpdate(name: 'Pro')},
        'app2': {'p2': const ProductLabelUpdate(name: 'Max')},
      });
      expect(notifier.state.namedCount, 2);

      await notifier.undo();
      expect(notifier.state.isEmpty, isTrue);
    });

    test('labels load again in a new notifier', () async {
      final first = ProductLabelsNotifier();
      await first.ready;
      await first.setName('app1', 'p1', 'Pro');

      final second = ProductLabelsNotifier();
      await second.ready;
      expect(second.state.displayName('app1', 'p1'), 'Pro');
    });

    test(
      'clearing every app forgets every name, and undo brings them back',
      () async {
        final notifier = ProductLabelsNotifier();
        await notifier.ready;
        await notifier.setName('app1', 'p1', 'Pro');
        await notifier.setName('app2', 'p2', 'Max');

        await notifier.clearAll();
        expect(notifier.state.isEmpty, isTrue);
        expect(notifier.state.displayName('app1', 'p1'), isNull);
        expect(notifier.state.displayName('app2', 'p2'), isNull);
        expect(notifier.canUndo, isTrue);

        await notifier.undo();
        expect(notifier.state.displayName('app1', 'p1'), 'Pro');
        expect(notifier.state.displayName('app2', 'p2'), 'Max');
      },
    );

    test('clearing every app is a no-op when nothing is named', () async {
      final notifier = ProductLabelsNotifier();
      await notifier.ready;
      await notifier.clearAll();
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.canUndo, isFalse);
    });

    test('clearing an app keeps the others', () async {
      final notifier = ProductLabelsNotifier();
      await notifier.ready;
      await notifier.setName('app1', 'p1', 'Pro');
      await notifier.setName('app2', 'p2', 'Max');
      await notifier.clearApp('app1');

      expect(notifier.state.displayName('app1', 'p1'), isNull);
      expect(notifier.state.displayName('app2', 'p2'), 'Max');
    });
  });
}
