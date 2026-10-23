import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:revenuecat/app/main_shell.dart';
import 'package:revenuecat/features/settings/settings_screen.dart';
import 'package:revenuecat/features/sign_in/sign_in_screen.dart';
import 'package:revenuecat/services/exchange_rate_provider.dart';
import 'package:revenuecat/services/rc_auth_service.dart';
import 'package:revenuecat/services/utilities_service.dart';
import 'package:revenuecat/theme/app_theme.dart';
import 'package:skeletonizer/skeletonizer.dart';

class RevenueCatApp extends ConsumerStatefulWidget {
  const RevenueCatApp({super.key});

  @override
  ConsumerState<RevenueCatApp> createState() => _RevenueCatAppState();
}

class _RevenueCatAppState extends ConsumerState<RevenueCatApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rates that failed (e.g. launched offline) get another try on return.
    if (state == AppLifecycleState.resumed &&
        ref.read(usdExchangeRatesProvider).hasError) {
      ref.invalidate(usdExchangeRatesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Swapping `home` only replaces the root screen; anything pushed on top
    // (Settings, a transaction, a sheet) would stay visible after sign-out.
    ref.listen<bool>(isSignedInProvider, (previous, next) {
      if (previous == true && !next) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });
    final signedIn = ref.watch(isSignedInProvider);
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = ref.watch(colorSchemeProvider);
    final effectiveColorScheme = defaultTargetPlatform == TargetPlatform.macOS
        ? defaultAppColorScheme
        : colorScheme;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'RevenueCat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(effectiveColorScheme),
      darkTheme: AppTheme.dark(effectiveColorScheme),
      themeMode: themeMode,
      color: AppTheme.light(effectiveColorScheme).scaffoldBackgroundColor,
      builder: (context, child) {
        return SkeletonizerConfig(
          data: AppTheme.skeletonizer(Theme.of(context).colorScheme),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routes: {SettingsScreen.routeName: (_) => const SettingsScreen()},
      home: _AuthGate(signedIn: signedIn),
    );
  }
}

/// Cross-fades between sign-in and the app instead of an instant swap.
class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: signedIn
          ? const MainShell(key: ValueKey('signed-in'))
          : const SignInScreen(key: ValueKey('signed-out')),
    );
  }
}
