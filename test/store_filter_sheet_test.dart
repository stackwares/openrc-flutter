import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/features/transactions/widgets/transactions_app_filter_sheet.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the store filter offers only stores that can match', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
                  filterSource: const {
                    '2026-10-23': [
                      RcTransaction(
                        app: RcTransactionApp(id: 'a', name: 'Stein AI'),
                        store: 'App Store',
                      ),
                    ],
                  },
                  currentIncludeFilter: null,
                  onApply: (_, _, _) {},
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

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
    // Sandbox rows are never loaded, so a test-purchase filter is gone.
    expect(find.text('Test'), findsNothing);
  });
}
