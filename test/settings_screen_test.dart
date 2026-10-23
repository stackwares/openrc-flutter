import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/models/rc_me_response.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/services/rc_account_projects_provider.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'RevenueCat',
      packageName: 'com.example.revenuecat',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rcMeProvider.overrideWith(
            (ref) => const RcMeResponse(
              name: 'Ada Lovelace',
              email: 'ada@example.com',
              currentPlan: 'pro',
              distinctId: 'abc123',
            ),
          ),
          rcAccountProjectsProvider.overrideWith(
            (ref) async => const [RcProject(name: 'A'), RcProject(name: 'B')],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(
            FlexScheme.indigoM3,
          ).copyWith(splashFactory: InkRipple.splashFactory),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows who is signed in and what currency is used', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('Pro plan'), findsOneWidget);
    expect(find.text('2 projects'), findsOneWidget);
    expect(find.text('US dollar · shown as \$1,234.56'), findsOneWidget);
    expect(find.text('abc123'), findsOneWidget);
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
  });

  testWidgets('store fee rows appear when fees are subtracted', (tester) async {
    await pump(tester);
    expect(find.text('App Store fee'), findsNothing);
    await tester.tap(find.text('Subtract store fees'));
    await tester.pumpAndSettle();
    expect(find.text('App Store fee'), findsOneWidget);
    expect(find.text('A \$9.99 sale counts as \$8.49'), findsNWidgets(2));
  });

  testWidgets('a custom fee is validated, saved, and explained', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Subtract store fees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App Store fee'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '15'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '120');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a fee between 0 and 100.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12.5');
    await tester.pump();
    expect(find.text('A \$9.99 sale counts as \$8.74'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('12.5%'), findsOneWidget);
    expect(find.text('A \$9.99 sale counts as \$8.74'), findsOneWidget);
  });

  testWidgets('tapping a swatch switches the accent color', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(FlexScheme.blueM3.data.name));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(colorSchemeProvider), FlexScheme.blueM3);
  });
}
