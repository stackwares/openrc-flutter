import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_push_messaging.dart';
import 'fake_revenuecat.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'OpenRC',
      packageName: 'com.openrc.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    PushMessaging? push,
    RcApiService? api,
  }) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (push != null) pushMessagingProvider.overrideWithValue(push),
          if (api != null) rcApiServiceProvider.overrideWithValue(api),
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
          agentSettingsProvider.overrideWith(_FakeAgentSettings.new),
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
    // Builds without a PostHog token send nothing, so there is no toggle.
    expect(find.text('Share anonymous usage'), findsNothing);
    // Nor are there notifications without Firebase settings.
    expect(find.text('Push notifications'), findsNothing);
  });

  testWidgets('the notifications row shows its status and opens the screen', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await pump(tester, push: FakePushMessaging(), api: FakeRevenueCat().api());
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('Push notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Know the moment you make a sale'), findsOneWidget);
  });

  testWidgets('store fee rows appear when fees are subtracted', (tester) async {
    await pump(tester);
    expect(find.text('Apple fee'), findsNothing);
    await tester.tap(find.text('Subtract store fees'));
    await tester.pumpAndSettle();
    expect(find.text('Apple fee'), findsOneWidget);
    expect(find.text('A \$9.99 sale counts as \$8.49'), findsNWidgets(2));
  });

  testWidgets('a custom fee is validated, saved, and explained', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Subtract store fees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apple fee'));
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

  testWidgets('Language follows the device until one is picked', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Language'), findsOneWidget);
    // The theme picker has its own "System" option too.
    expect(find.text('System'), findsNWidgets(2));

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.text('Same as your device'), findsOneWidget);
    for (final name in ['Deutsch', '日本語', 'العربية', 'Português (Brasil)']) {
      expect(find.text(name), findsOneWidget);
    }

    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(appLanguageProvider), 'de');
    expect(find.text('Deutsch'), findsOneWidget);
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

class _FakeAgentSettings extends AgentSettingsNotifier {
  @override
  Future<AgentSettings> build() async => const AgentSettings(
        providerId: AgentProviderId.openrouter,
        model: '',
        customBaseUrl: '',
        customStyle: AgentApiStyle.openAi,
        useFasterModel: false,
        hasKey: false,
      );
}
