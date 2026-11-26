import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/push/push_config.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/store_review_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
      version: '1.0.4',
      buildNumber: '11',
      buildSignature: '',
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('Windows push notifications', () {
    test('skips FCM initialization and reports unsupported on Windows', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      expect(PushNotifications.isPlatformSupported, isFalse);
      expect(PushNotifications.isAvailable, isFalse);
      expect(PushNotifications.isSupported, isFalse);
      expect(PushConfig.firebaseOptions, isNull);

      // Must complete cleanly without touching FirebaseMessaging.
      await PushNotifications.start();
      expect(PushNotifications.isAvailable, isFalse);
      expect(await PushNotifications.initialMessage(), isNull);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pushMessagingProvider), isNull);
    });

    testWidgets('hides sale-alert push settings on Windows', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // Even if a push messaging instance is injected, Windows must hide
              // the FCM sale-alert section.
              pushMessagingProvider.overrideWithValue(FakePushMessaging()),
              rcApiServiceProvider.overrideWithValue(FakeRevenueCat().api()),
              rcMeProvider.overrideWith(
                (ref) => const RcMeResponse(
                  name: 'Ada Lovelace',
                  email: 'ada@example.com',
                  currentPlan: 'pro',
                  distinctId: 'win123',
                ),
              ),
              rcAccountProjectsProvider.overrideWith(
                (ref) async => const [RcProject(name: 'A')],
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

        expect(find.text('Notifications'), findsNothing);
        expect(find.text('Push notifications'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Windows Microsoft Store review', () {
    test('builds expected ms-windows-store review URI', () {
      final uri = StoreReviewService.microsoftStoreReviewUri();
      expect(
        uri.toString(),
        'ms-windows-store://review/?ProductId=$kMicrosoftStoreProductId',
      );
      expect(uri.scheme, 'ms-windows-store');
      expect(uri.host, 'review');
      expect(uri.queryParameters['ProductId'], 'TODO_OPENRC_MS_STORE_ID');
    });

    test('requestReview opens ms-windows-store URI on Windows', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      Uri? launched;
      final ok = await StoreReviewService.requestReview(
        launchUri: (uri) async {
          launched = uri;
          return true;
        },
      );

      expect(ok, isTrue);
      expect(
        launched,
        Uri.parse(
          'ms-windows-store://review/?ProductId=TODO_OPENRC_MS_STORE_ID',
        ),
      );
    });
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
