// Captures 4K (3840x2160) desktop screenshots of OpenRC for the Microsoft Store
// using seeded demo data (`DemoAdapter`), a fixed 1920x1080 logical viewport,
// and an in-app `RepaintBoundary` rendered at pixelRatio 2.0.
//
// Run on Windows:
//   flutter test integration_test/windows_capture_test.dart -d windows
//
// Optional defines:
//   --dart-define=CAPTURE_LOCALE=en
//   --dart-define=CAPTURE_OUT_DIR=../Marketing/openrc/captures/windows/en
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openrc/app/app.dart';
import 'package:openrc/app/app_navigator.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/core/l10n/app_locales.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/services/demo/demo_adapter.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _locale = String.fromEnvironment('CAPTURE_LOCALE', defaultValue: 'en');
const _outDirOverride = String.fromEnvironment('CAPTURE_OUT_DIR');

/// Logical desktop viewport (16:9). Captured at pixelRatio 2.0 -> 3840x2160.
const _logicalSize = Size(1920, 1080);
const _capturePixelRatio = 2.0;

String get _outputDir => _outDirOverride.isNotEmpty
    ? _outDirOverride
    : '../Marketing/openrc/captures/windows/$_locale';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'captures 4K Windows Microsoft Store screenshots',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      await EasyLocalization.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'onboarding_completed_v1': true,
        'onboarding_focus_applied_v1': true,
      });

      final demoApi = RcApiService(
        dio: Dio()..httpClientAdapter = DemoAdapter(),
        internalDio: Dio()..httpClientAdapter = DemoAdapter(),
      )..setAuthToken('demo-token');

      final container = ProviderContainer(
        overrides: [
          rcApiServiceProvider.overrideWithValue(demoApi),
          isSignedInProvider.overrideWith((ref) => true),
          rcMeProvider.overrideWith(
            (ref) => const RcMeResponse(
              name: 'Alex Morgan',
              email: 'alex@example.com',
              currentPlan: 'Pro',
              distinctId: 'demo-distinct-id',
            ),
          ),
          themeModeProvider.overrideWith((ref) => ThemeMode.dark),
          colorSchemeProvider.overrideWith((ref) => FlexScheme.sakura),
        ],
      );
      addTearDown(container.dispose);

      await container.read(onboardingPrefsProvider.notifier).load();

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: AppLocales.supported,
          path: AppLocales.path,
          fallbackLocale: AppLocales.fallback,
          startLocale: AppLocales.fromStem(_locale) ?? AppLocales.fallback,
          useOnlyLangCode: false,
          saveLocale: false,
          child: UncontrolledProviderScope(
            container: container,
            child: Center(
              child: SizedBox(
                width: _logicalSize.width,
                height: _logicalSize.height,
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: _logicalSize,
                    devicePixelRatio: 1.0,
                  ),
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: const OpenRcApp(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);

      final outDir = Directory(_outputDir);
      await outDir.create(recursive: true);

      // 01: Transactions (dark)
      container.read(mainShellTabIndexProvider.notifier).state = 0;
      await _settle(tester);
      await _capture(boundaryKey, outDir, '01-transactions-dark.png');

      // 02: Revenue (dark)
      container.read(mainShellTabIndexProvider.notifier).state = 1;
      await _settle(tester);
      await _capture(boundaryKey, outDir, '02-revenue-dark.png');

      // 03: Charts (dark)
      container.read(mainShellTabIndexProvider.notifier).state = 2;
      await _settle(tester);
      await _capture(boundaryKey, outDir, '03-charts-dark.png');

      // 04: Ask (dark)
      container.read(mainShellTabIndexProvider.notifier).state = 3;
      await _settle(tester);
      await _capture(boundaryKey, outDir, '04-ask-dark.png');

      // 05: Settings dialog over Transactions (dark)
      container.read(mainShellTabIndexProvider.notifier).state = 0;
      await _settle(tester);
      final navContext = appNavigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        SettingsScreen.open(navContext);
        await _settle(tester);
        await _capture(boundaryKey, outDir, '05-settings-dark.png');
        appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
        await _settle(tester);
      }

      // 06: Transactions (light)
      container.read(themeModeProvider.notifier).state = ThemeMode.light;
      await _settle(tester);
      await _capture(boundaryKey, outDir, '06-transactions-light.png');
    },
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _capture(
  GlobalKey boundaryKey,
  Directory outDir,
  String filename,
) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('RepaintBoundary not mounted for $filename');
  }
  final image = await boundary.toImage(pixelRatio: _capturePixelRatio);
  final width = image.width;
  final height = image.height;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Failed to encode PNG for $filename');
  }
  final file = File('${outDir.path}/$filename');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  debugPrint('CAPTURE_SHOT ${file.path} (${width}x$height)');
}
