import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/settings/product_inventory.dart';
import 'package:openrc/features/settings/product_names_screen.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/product_labels_store.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSettings extends AgentSettingsNotifier {
  _FakeSettings({this.hasKey = false});

  final bool hasKey;

  @override
  Future<AgentSettings> build() async => AgentSettings(
    providerId: AgentProviderId.openrouter,
    model: 'openai/gpt-4o',
    customBaseUrl: '',
    customStyle: AgentApiStyle.openAi,
    useFasterModel: false,
    hasKey: hasKey,
  );

  @override
  Future<String?> readApiKey(AgentProviderId providerId) async =>
      hasKey ? 'sk-test' : null;
}

const _acme = RcTransactionApp(
  id: 'app1',
  name: 'Acme',
  bundleId: 'com.acme.app',
);

const _orly = RcTransactionApp(
  id: 'app2',
  name: 'Orly',
  bundleId: 'com.orly.app',
);

final _transactions = [
  const RcTransaction(
    app: _acme,
    productIdentifier: 'com.acme.pro_monthly',
    store: 'App Store',
  ),
  const RcTransaction(
    app: _acme,
    productIdentifier: 'com.acme.pro_monthly',
    store: 'App Store',
  ),
  const RcTransaction(
    app: _acme,
    productIdentifier: 'com.acme.max_yearly',
    store: 'Play Store',
  ),
  // No product id: not a product row.
  const RcTransaction(app: _acme, store: 'App Store'),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Size size = const Size(430, 900),
  bool hasKey = false,
  bool multiApp = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final txs = [
    ..._transactions,
    if (multiApp)
      const RcTransaction(
        app: _orly,
        productIdentifier: 'com.orly.pro_yearly',
        store: 'Play Store',
      ),
  ];
  final container = ProviderContainer(
    overrides: [
      productInventoryProvider.overrideWithValue(buildProductInventory(txs)),
      agentSettingsProvider.overrideWith(() => _FakeSettings(hasKey: hasKey)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(FlexScheme.indigoM3),
        home: const ProductNamesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists products with their sales and naming progress', (
    tester,
  ) async {
    await _pump(tester);

    // One app means no tabs: its icon, name and progress head the list.
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('0 of 2 named'), findsOneWidget);
    expect(find.textContaining('com.acme.pro_monthly'), findsWidgets);
    expect(find.textContaining('2 sales'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('two apps get icon tabs that switch lists', (tester) async {
    final container = await _pump(tester, multiApp: true);

    // Tabs carry the app name and the unnamed count.
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Orly'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // Naming progress is per app.
    expect(find.text('0 of 2 named'), findsOneWidget);

    // The second tab's list is one tap away; the first tab stays mounted
    // but offstage, so assertions target what is actually visible.
    await tester.tap(find.text('Orly'));
    await tester.pumpAndSettle();

    expect(find.text('0 of 1 named').hitTestable(), findsOneWidget);
    expect(
      find.textContaining('com.orly.pro_yearly').hitTestable(),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('com.acme.pro_monthly').hitTestable(),
      findsNothing,
    );

    // Search filters the visible tab only.
    await tester.enterText(find.byType(TextField), 'lifetime');
    await tester.pumpAndSettle();
    expect(find.text('No matching products.').hitTestable(), findsOneWidget);

    // Clearing the query brings the tab's rows back.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('com.orly.pro_yearly').hitTestable(),
      findsNWidgets(2),
    );
    expect(container.read(productLabelsProvider).namedCount, 0);
  });

  testWidgets('the sheet is titled in title case and offers both paths', (
    tester,
  ) async {
    await _pump(tester, hasKey: true);

    await tester.tap(find.byTooltip('Suggest names'));
    await tester.pumpAndSettle();

    expect(find.text('Suggest Names'), findsOneWidget);
    expect(find.text('2 products have no name yet'), findsOneWidget);
    expect(find.text('Suggest with AI'), findsOneWidget);
    expect(find.text('OpenRouter · openai/gpt-4o'), findsOneWidget);
    expect(find.text('Built-in names'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    // The privacy line sits on the AI card, above the built-in option.
    expect(find.textContaining('Only product IDs are sent'), findsOneWidget);
  });

  testWidgets('without a key the sheet offers to connect a model', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Suggest names'));
    await tester.pumpAndSettle();

    expect(find.text('Suggest Names'), findsOneWidget);
    expect(find.text('Connect a model'), findsOneWidget);
    expect(find.text('Built-in names'), findsOneWidget);
  });

  testWidgets('with AI off for the app the AI option only explains why', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pump(tester, hasKey: true);

      await tester.tap(find.byTooltip('Suggest names'));
      await tester.pumpAndSettle();

      expect(find.textContaining('AI is turned off'), findsOneWidget);
      expect(find.text('Built-in names'), findsOneWidget);
      // The parser path still works.
      await tester.tap(find.text('Built-in names'));
      await tester.pumpAndSettle();
      expect(find.text('2 suggestions ready'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('built-in names can be applied to every product', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.byTooltip('Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();

    expect(find.text('2 suggestions ready'), findsOneWidget);

    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();

    final labels = container.read(productLabelsProvider);
    // Built-in names are only the billing period the id names.
    expect(labels.displayName('app1', 'com.acme.pro_monthly'), 'Monthly');
    expect(labels.displayName('app1', 'com.acme.max_yearly'), 'Yearly');
    expect(find.text('2 suggestions ready'), findsNothing);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
  });

  testWidgets('suggestions fit a small phone', (tester) async {
    await _pump(tester, size: const Size(360, 780));

    await tester.tap(find.byTooltip('Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2 suggestions ready'), findsOneWidget);
  });

  testWidgets('a name typed by hand replaces the id on the row', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.textContaining('com.acme.pro_monthly').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Pro Monthly',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(productLabelsProvider)
          .displayName('app1', 'com.acme.pro_monthly'),
      'Pro Monthly',
    );
    expect(find.text('Pro Monthly'), findsOneWidget);
    // The raw id stays visible under the name.
    expect(find.textContaining('com.acme.pro_monthly'), findsOneWidget);
  });

  testWidgets('undo takes back an applied run', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.byTooltip('Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();

    expect(container.read(productLabelsProvider).namedCount, 2);

    await container.read(productLabelsProvider.notifier).undo();
    await tester.pumpAndSettle();

    expect(container.read(productLabelsProvider).namedCount, 0);
    expect(find.textContaining('com.acme.pro_monthly'), findsWidgets);
  });
}
