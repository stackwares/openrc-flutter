import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/app/app.dart';
import 'package:revenuecat/app/app_startup.dart';
import 'package:revenuecat/core/logging/app_logging.dart';
import 'package:revenuecat/firebase_options.dart';
import 'package:revenuecat/services/firestore_service.dart';
import 'package:revenuecat/services/push_registration_service.dart';

final _mainLog = Logger('main');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureAppLogging();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _installCrashReporting();
  } catch (e, st) {
    _mainLog.severe('Firebase init failed', e, st);
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final container = ProviderContainer();

  try {
    await AppStartup(container).initialize();
  } catch (e, st) {
    // Never block the first frame: the app falls back to signed-out defaults.
    _mainLog.severe('App startup failed', e, st);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RevenueCatApp(),
    ),
  );

  // Firebase Auth / Messaging touch Pigeon channels; doing that before the
  // first frame can yield PlatformException(channel-error, ...) on Android.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializePushAfterFirstFrame(container));
  });
}

bool get _crashlyticsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Sends uncaught Flutter and async errors to Crashlytics (release builds).
void _installCrashReporting() {
  if (!_crashlyticsSupported) return;
  final crashlytics = FirebaseCrashlytics.instance;
  unawaited(crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode));
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    crashlytics.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}

Future<void> _initializePushAfterFirstFrame(ProviderContainer container) async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  try {
    await PushRegistrationService.instance.initialize();
    // Let Pigeon / Firestore channels settle after auth + messaging init.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await container.read(firestoreServiceProvider).syncDeviceProfile();
  } catch (e, st) {
    _mainLog.warning('Push registration init failed: $e\n$st');
  }
}
