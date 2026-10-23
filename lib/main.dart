import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:openrc/app/app.dart';
import 'package:openrc/app/app_startup.dart';
import 'package:openrc/core/l10n/app_locales.dart';
import 'package:openrc/core/logging/app_logging.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/theme/app_tokens.dart';

final _mainLog = Logger('main');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppLogging();
  await EasyLocalization.ensureInitialized();
  // Crash reports and anonymous usage; a no-op in builds without a token.
  await Telemetry.start();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  // Phones stay upright; tablets rotate and share the screen with other apps.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (isPhoneSized(view.physicalSize / view.devicePixelRatio)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  final container = ProviderContainer();

  try {
    await AppStartup(container).initialize();
  } catch (e, st) {
    // Never block the first frame: the app falls back to signed-out defaults.
    _mainLog.severe('App startup failed', e, st);
  }

  runApp(
    // Follows the device language unless one is picked in Settings;
    // English fills in anything missing.
    EasyLocalization(
      supportedLocales: AppLocales.supported,
      path: AppLocales.path,
      fallbackLocale: AppLocales.fallback,
      useOnlyLangCode: false,
      saveLocale: true,
      child: UncontrolledProviderScope(
        container: container,
        child: const OpenRcApp(),
      ),
    ),
  );
}
