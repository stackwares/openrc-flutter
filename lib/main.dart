import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/app/app.dart';
import 'package:revenuecat/app/app_startup.dart';
import 'package:revenuecat/core/logging/app_logging.dart';
import 'package:revenuecat/firebase_options.dart';
import 'package:revenuecat/services/push_registration_service.dart';

final _mainLog = Logger('main');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  configureAppLogging();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final container = ProviderContainer();

  final startup = AppStartup(container);
  await startup.initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const RevenueCatApp(),
    ),
  );

  // Firebase Auth / Messaging touch Pigeon channels; doing that before the
  // first frame can yield PlatformException(channel-error, ...) on Android.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializePushAfterFirstFrame());
  });
}

Future<void> _initializePushAfterFirstFrame() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  try {
    await PushRegistrationService.instance.initialize();
  } catch (e, st) {
    _mainLog.warning('Push registration init failed: $e\n$st');
  }
}
