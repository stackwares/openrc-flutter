import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:openrc/app/app_navigator.dart';
import 'package:openrc/app/mac_menu_bar.dart';
import 'package:openrc/app/main_shell.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/core/l10n/app_locales.dart';
import 'package:openrc/features/onboarding/onboarding_screen.dart';
import 'package:openrc/features/settings/settings_screen.dart';
import 'package:openrc/features/sign_in/sign_in_screen.dart';
import 'package:openrc/services/onboarding_prefs_store.dart';
import 'package:openrc/services/exchange_rate_provider.dart';
import 'package:openrc/services/rc_auth_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/services/utilities_service.dart';
import 'package:openrc/theme/app_theme.dart';
import 'package:skeletonizer/skeletonizer.dart';

class OpenRcApp extends ConsumerStatefulWidget {
  const OpenRcApp({super.key});

  @override
  ConsumerState<OpenRcApp> createState() => _OpenRcAppState();
}

class _OpenRcAppState extends ConsumerState<OpenRcApp>
    with WidgetsBindingObserver {
  final _telemetryObserver = TelemetryRouteObserver();

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
    // The OS may stop the app from here; a crash report is only useful if the
    // events that led to it left the device first.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      Telemetry.flush();
    }
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
        appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });
    final signedIn = ref.watch(isSignedInProvider);
    final onboardingCompleted = ref.watch(onboardingPrefsProvider).completed;
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = ref.watch(colorSchemeProvider);

    final l10n = EasyLocalization.of(context);

    final app = MaterialApp(
      navigatorKey: appNavigatorKey,
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // English without an EasyLocalization ancestor (widget tests).
      localizationsDelegates:
          l10n?.delegates ?? GlobalMaterialLocalizations.delegates,
      supportedLocales: l10n?.supportedLocales ?? const [AppLocales.fallback],
      locale: l10n?.locale,
      theme: AppTheme.light(colorScheme),
      darkTheme: AppTheme.dark(colorScheme),
      themeMode: themeMode,
      color: AppTheme.light(colorScheme).scaffoldBackgroundColor,
      builder: (context, child) {
        // Dates and month names follow the app's language.
        Intl.defaultLocale = (l10n?.locale ?? AppLocales.fallback)
            .toLanguageTag();
        final content = SkeletonizerConfig(
          data: AppTheme.skeletonizer(Theme.of(context).colorScheme),
          child: child ?? const SizedBox.shrink(),
        );
        if (!_hasTransparentTitleBar) return content;
        // Keeps headers and the sidebar clear of the window controls.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(top: _macTitleBarHeight),
            viewPadding: media.viewPadding.copyWith(top: _macTitleBarHeight),
          ),
          child: content,
        );
      },
      navigatorObservers: [_telemetryObserver],
      routes: {SettingsScreen.routeName: (_) => const SettingsScreen()},
      home: _AuthGate(
        signedIn: signedIn,
        onboardingCompleted: onboardingCompleted,
      ),
    );
    // Session replay is captured here: the plugin's Flutter-side capturer
    // needs this root, and the text/image/custom-paint masks that keep a
    // replay anonymous only apply through it. Mounted after `Telemetry.start`
    // (which awaits the setup) in `main`, as the plugin requires.
    final captured = Telemetry.isAvailable
        ? PostHogWidget(child: app)
        : app;
    if (!_hasTransparentTitleBar) return captured;
    return MacMenuBar(navigatorKey: appNavigatorKey, child: captured);
  }
}

/// The macOS window draws content under a transparent title bar
/// (`MainFlutterWindow.swift`).
bool get _hasTransparentTitleBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

const double _macTitleBarHeight = 28;

/// Cross-fades between the wizard, sign-in and the app instead of an instant swap.
class _AuthGate extends StatelessWidget {
  const _AuthGate({
    required this.signedIn,
    required this.onboardingCompleted,
  });

  final bool signedIn;
  final bool onboardingCompleted;

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
          : onboardingCompleted
          ? const SignInScreen(key: ValueKey('signed-out'))
          : const OnboardingScreen(key: ValueKey('onboarding')),
    );
  }
}
