import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/settings/product_inventory.dart';
import 'package:openrc/features/settings/product_names_screen.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
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
  List<RcTransaction> extra = const [],
  AgentLlmClient? aiClient,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final txs = [
    ..._transactions,
    ...extra,
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
      if (aiClient != null) agentLlmClientProvider.overrideWithValue(aiClient),
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

/// Answers every chunk with a name, holding the second reply until released,
/// so a test can look at the screen mid-run.
class _TwoStepClient extends AgentLlmClient {
  final second = Completer<void>();
  int calls = 0;

  @override
  Future<AgentLlmResponse> complete({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    calls++;
    final payload =
        jsonDecode(messages.last['content'] as String) as Map<String, dynamic>;
    final ids = [
      for (final product
          in (payload['products'] as List).cast<Map<String, dynamic>>())
        product['id'] as String,
    ];
    if (calls > 1) await second.future;
    return AgentLlmResponse(
      assistantText: jsonEncode({
        'labels': [
          for (final id in ids) {'id': id, 'name': 'Pro'},
        ],
      }),
    );
  }
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

  testWidgets('the way to name them is a button at the bottom', (tester) async {
    await _pump(tester);

    final cta = find.widgetWithText(FilledButton, 'Suggest names');
    expect(cta, findsOneWidget);
    expect(tester.widget<FilledButton>(cta).onPressed, isNotNull);
    // The app bar no longer hides it behind a bare icon.
    expect(find.byTooltip('Suggest names'), findsNothing);

    // It sits in the bottom action bar, below the list.
    final screen = tester.getRect(find.byType(ProductNamesScreen));
    final list = tester.getRect(find.byType(ListView).first);
    final button = tester.getRect(cta);
    expect(button.top, greaterThanOrEqualTo(list.bottom - 1));
    expect(button.bottom, lessThanOrEqualTo(screen.bottom));
    expect(
      screen.bottom - button.bottom,
      lessThan(80),
      reason: 'the action is at the bottom of the screen',
    );
  });

  testWidgets('nothing to suggest means no bottom action', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();

    expect(container.read(productLabelsProvider).namedCount, 2);
    expect(find.widgetWithText(FilledButton, 'Suggest names'), findsNothing);
    // The per-app progress still says everything is named.
    expect(find.text('2 of 2 named'), findsOneWidget);
  });

  testWidgets('pending suggestions take over the bottom action bar', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();

    expect(find.text('2 suggestions ready'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Apply all'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Dismiss'), findsOneWidget);
    // One action area, not an icon and a card competing with it.
    expect(find.widgetWithText(FilledButton, 'Suggest names'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('2 suggestions ready'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Suggest names'),
      findsOneWidget,
      reason: 'dismissing brings the run-it action back',
    );
  });

  testWidgets('the sheet is titled in title case and offers both paths', (
    tester,
  ) async {
    await _pump(tester, hasKey: true);

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();

    expect(find.text('Suggest Names'), findsOneWidget);
    expect(find.text('2 products have no name yet'), findsOneWidget);
    expect(find.text('Suggest with AI'), findsOneWidget);
    expect(find.text('OpenRouter · openai/gpt-4o'), findsOneWidget);
    expect(find.text('Built-in names'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    // The privacy line sits on the AI card, above the built-in option.
    expect(
      find.textContaining('Only product IDs and the billing period'),
      findsOneWidget,
    );
  });

  testWidgets('without a key the sheet offers to connect a model', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
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

      await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
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

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
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

  testWidgets('a product that does not renew is named by its term', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      extra: const [
        // Sold once, never renewed: a one-year pass, not a yearly plan.
        RcTransaction(
          app: _acme,
          productIdentifier: 'com.acme.pass_yearly',
          store: 'App Store',
          isAutoRenewing: false,
        ),
      ],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();

    final labels = container.read(productLabelsProvider);
    expect(labels.displayName('app1', 'com.acme.pass_yearly'), '1 Year');
    // A subscription keeps its cadence, and rows that say nothing keep it too.
    expect(labels.displayName('app1', 'com.acme.max_yearly'), 'Yearly');
    expect(find.text('1 Year'), findsOneWidget);
  });

  testWidgets("the model's names show up while it is still working", (
    tester,
  ) async {
    final client = _TwoStepClient();
    // Two replies: the first names 20 products, the second the last 5.
    await _pump(
      tester,
      hasKey: true,
      aiClient: client,
      extra: [
        for (var i = 0; i < 25; i++)
          RcTransaction(
            app: _acme,
            productIdentifier: 'com.acme.pro_monthly_$i',
            store: 'App Store',
          ),
      ],
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suggest with AI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Mid-run: the first chunk of 20 is already on the rows, the rest is
    // still in flight (the two fixture products round the total up to 27).
    expect(client.calls, 2);
    expect(find.textContaining('Naming 20 of 27'), findsOneWidget);
    expect(find.text('Pro'), findsWidgets, reason: 'names arrived already');
    expect(find.widgetWithText(FilledButton, 'Apply all'), findsNothing);

    client.second.complete();
    await tester.pumpAndSettle();
    expect(find.text('27 suggestions ready'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Apply all'), findsOneWidget);
  });

  testWidgets('suggestions fit a small phone', (tester) async {
    await _pump(tester, size: const Size(360, 780));

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2 suggestions ready'), findsOneWidget);
  });

  testWidgets('every name can be cleared at once, with undo', (tester) async {
    final container = await _pump(tester, multiApp: true);

    // Name both apps first.
    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Built-in names'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply all'));
    await tester.pumpAndSettle();
    expect(container.read(productLabelsProvider).namedCount, 3);
    // The "Named 3 products" snackbar is still up; let it go, so the next
    // one is not queued behind it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // The menu only offers to clear when there is something to clear.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Clear all names'), findsOneWidget);

    await tester.tap(find.text('Clear all names'));
    await tester.pumpAndSettle();
    expect(find.text('Clear every product name?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(
      container.read(productLabelsProvider).isEmpty,
      isTrue,
      reason: 'every app is cleared',
    );
  });

  testWidgets('the clear-all menu stays out of the way when nothing is named', (
    tester,
  ) async {
    await _pump(tester, multiApp: true);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
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

    await tester.tap(find.widgetWithText(FilledButton, 'Suggest names'));
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
