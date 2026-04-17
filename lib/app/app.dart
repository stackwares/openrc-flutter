import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/router/app_router.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/theme/app_theme.dart';

class RevenueCatApp extends ConsumerStatefulWidget {
  const RevenueCatApp({super.key});

  @override
  ConsumerState<RevenueCatApp> createState() => _RevenueCatAppState();
}

class _RevenueCatAppState extends ConsumerState<RevenueCatApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = ref.watch(colorSchemeProvider);
    final effectiveThemeMode = defaultTargetPlatform == TargetPlatform.macOS
        ? ThemeMode.light
        : themeMode;
    final effectiveColorScheme = defaultTargetPlatform == TargetPlatform.macOS
        ? FlexScheme.greyLaw
        : colorScheme;

    return MaterialApp.router(
      title: 'RevenueCat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(effectiveColorScheme),
      darkTheme: AppTheme.dark(effectiveColorScheme),
      themeMode: effectiveThemeMode,
      color: AppTheme.light(effectiveColorScheme).scaffoldBackgroundColor,
      routerConfig: router,
    );
  }
}
