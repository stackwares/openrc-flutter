import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'OpenRC',
      packageName: 'com.openrc.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  /// Settings opened from a wide window, where it's a dialog.
  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rcMeProvider.overrideWith(
            (ref) => const RcMeResponse(name: 'Ada', email: 'ada@example.com'),
          ),
          rcAccountProjectsProvider.overrideWith((ref) async => const []),
          pushMessagingProvider.overrideWithValue(FakePushMessaging()),
          rcApiServiceProvider.overrideWithValue(FakeRevenueCat().api()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.indigoM3),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => SettingsScreen.open(context),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  }

  Finder inDialog(Finder finder) =>
      find.descendant(of: find.byType(Dialog), matching: finder);

  testWidgets('pickers slide in inside the dialog, with a back button', (
    tester,
  ) async {
    await openSettings(tester);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    // Still one dialog: the picker is a page in it, not a dialog on top.
    expect(find.byType(Dialog), findsOneWidget);
    expect(inDialog(find.text('Same as your device')), findsOneWidget);
    expect(inDialog(find.byType(BackButton)), findsOneWidget);

    await tester.tap(inDialog(find.byType(BackButton)));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Settings')), findsOneWidget);
    expect(find.text('Same as your device'), findsNothing);
  });

  testWidgets('Notifications opens as a page in the dialog', (tester) async {
    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Push notifications'),
      200,
      scrollable: inDialog(find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Push notifications'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      inDialog(find.text('Know the moment you make a sale')),
      findsOneWidget,
    );
    expect(inDialog(find.byType(BackButton)), findsOneWidget);
  });

  testWidgets('the close button closes the whole dialog', (tester) async {
    await openSettings(tester);
    await tester.tap(inDialog(find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);
  });
}
