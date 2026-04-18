import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/app/app.dart';
import 'package:revenuecat/app/app_startup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
