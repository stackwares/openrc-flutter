import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/transactions/transactions_common.dart';
import 'package:openrc/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Applied = (
  Set<String>?,
  Set<String>?,
  Set<TransactionPlatformFilter>?,
);

var _id = 0;

RcTransaction _tx(String app, String name, String store, String country) =>
    RcTransaction(
      app: RcTransactionApp(id: app, name: name),
      store: store,
      subscriberCountryCode: country,
      storeTransactionIdentifier: 'tx-${_id++}',
    );

final _transactions = [
  _tx('a', 'Stein AI', 'App Store', 'US'),
  _tx('a', 'Stein AI', 'App Store', 'US'),
  _tx('b', 'Orly', 'Play Store', 'JP'),
];

/// Opens the filters over [_transactions] in a window of [size] and returns
/// every change the sheet applies.
Future<List<_Applied>> _open(
  WidgetTester tester, {
  Size size = const Size(430, 1400),
  Set<String>? countries,
  Set<TransactionPlatformFilter>? platforms,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final applied = <_Applied>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(
          FlexScheme.indigoM3,
        ).copyWith(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTransactionsAppFilterSheet(
                context: context,
                filterSource: {'2026-10-23': _transactions},
                currentIncludeFilter: null,
                currentCountryCodes: countries,
                currentPlatforms: platforms,
                onApply: (apps, countries, platforms) =>
                    applied.add((apps, countries, platforms)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return applied;
}

/// Sets compare by identity inside records, so check each field.
void _expectApplied(
  _Applied applied,
  Set<String>? apps,
  Set<String>? countries,
  Set<TransactionPlatformFilter>? platforms,
) {
  expect(applied.$1, apps);
  expect(applied.$2, countries);
  expect(applied.$3, platforms);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the store filter offers only stores that can match', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
    // Sandbox rows are never loaded, so a test-purchase filter is gone.
    expect(find.text('Test'), findsNothing);
  });

  testWidgets('picking an app narrows to it and counts what matches', (
    tester,
  ) async {
    final applied = await _open(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Show 3 transactions'), findsOneWidget);
    expect(find.text('Reset'), findsNothing);

    await tester.tap(find.text('Orly'));
    await tester.pumpAndSettle();

    _expectApplied(applied.last, {'b'}, null, null);
    expect(find.text('Show 1 transaction'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('a store pick counts each app by what it would show', (
    tester,
  ) async {
    final applied = await _open(tester);

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();

    _expectApplied(applied.last, null, null, {
      TransactionPlatformFilter.google,
    });
    expect(find.text('Show 1 transaction'), findsOneWidget);
  });

  testWidgets('reset shows only while filtered and removes every filter', (
    tester,
  ) async {
    final applied = await _open(
      tester,
      countries: {'us'},
      platforms: {TransactionPlatformFilter.apple},
    );
    expect(find.text('Show 2 transactions'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    _expectApplied(applied.last, null, null, null);
    expect(find.text('Show 3 transactions'), findsOneWidget);
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('large windows get a two-column dialog', (tester) async {
    final applied = await _open(tester, size: const Size(1280, 900));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    // Countries sit beside stores and apps, not below them.
    final store = tester.getTopLeft(find.text('Store'));
    final country = tester.getTopLeft(find.text('Country'));
    expect(country.dx, greaterThan(store.dx + 200));
    expect((country.dy - store.dy).abs(), lessThan(4));

    await tester.enterText(
      find.widgetWithText(TextField, 'Search countries'),
      'japan',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japan'));
    await tester.pumpAndSettle();
    _expectApplied(applied.last, null, {'JP'}, null);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
