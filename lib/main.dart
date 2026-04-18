import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/app/app.dart';
import 'package:revenuecat/app/app_startup.dart';
import 'package:revenuecat/core/logging/app_logging.dart';
import 'package:revenuecat/firebase_options.dart';

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
}
