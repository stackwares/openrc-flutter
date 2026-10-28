import 'dart:async';

import 'package:core_analytics_flutter/core_analytics_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Whether this install shares anonymous usage and crash reports (Settings).
final telemetryEnabledProvider = StateProvider<bool>(
  (ref) => Telemetry.enabled,
);

/// Anonymous usage events and crash reports, sent to PostHog.
///
/// Thin OpenRC vocabulary over the shared `core_analytics_flutter` client, so
/// every Stackwares app reports through one implementation. Builds send
/// nothing unless they pass a project token
/// (`--dart-define=POSTHOG_PROJECT_TOKEN=phc_...`), so a build from source is
/// silent by default. Events never carry RevenueCat account details, app
/// names, product names or amounts, and no person profiles are created.
abstract final class Telemetry {
  /// True when this build has a PostHog project token.
  static bool get isAvailable => AppAnalytics.isConfigured;

  /// The user's choice; true until they turn it off.
  static bool get enabled => AppAnalytics.enabled;

  /// `production`, `internal` or `development`: recorded on every event, so a
  /// dashboard or funnel can be filtered to one build channel. Official
  /// builds pass `--dart-define=POSTHOG_ENVIRONMENT=production`; a build
  /// without it reports `development`, and a release build without it reports
  /// `production` rather than lying about being a dev build.
  static String get environment {
    const configured = String.fromEnvironment(
      AnalyticsConfig.environmentEnvironmentKey,
    );
    if (configured.isNotEmpty) return configured;
    return kReleaseMode ? 'production' : 'development';
  }

  /// The screen most recently reported, so a rebuilt screen (or a tab reported
  /// twice in one frame) is not counted twice.
  static String? _lastScreen;
  static DateTime? _lastScreenAt;

  /// Starts PostHog with error autocapture, session replay (every text node and
  /// image masked) and this build's environment. Safe to call when unavailable.
  static Future<void> start() async {
    final config = AnalyticsConfig.fromEnvironment(
      appName: 'openrc',
      environment: environment,
      // Session replay is masked by the SDK: text, images and custom-painted
      // content (charts) are replaced before a frame leaves the device, so a
      // replay shows layout and navigation, never a project, a product or an
      // amount.
      sessionReplay: true,
      maskCustomPaint: true,
      captureErrors: true,
      // A fresh install in a debug build starts opted out: a developer's own
      // runs should not land in the same charts as shipped builds. Release
      // installs still start opted in, and Settings can flip either.
      defaultEnabled: !kDebugMode,
    );
    await AppAnalytics.start(await _withVersion(config));
  }

  /// Adds this build's version and number, which the web dashboard cannot read
  /// from a browser the way the native SDKs read them from the app bundle.
  static Future<AnalyticsConfig> _withVersion(AnalyticsConfig config) async {
    try {
      final info = await PackageInfo.fromPlatform();
      return config.copyWith(
        appVersion: info.version,
        buildNumber: info.buildNumber,
      );
    } catch (_) {
      return config;
    }
  }

  /// Turns sharing on or off and remembers the choice.
  static Future<void> setEnabled(bool value) => AppAnalytics.setEnabled(value);

  /// Reports a screen view, and (on the web) a page view for web analytics.
  static void screen(String name) {
    final now = DateTime.now();
    final last = _lastScreenAt;
    if (name == _lastScreen && last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastScreen = name;
    _lastScreenAt = now;
    unawaited(AppAnalytics.screen(name));
  }

  static void event(String name, [Map<String, Object>? properties]) {
    unawaited(AppAnalytics.logEvent(name, properties));
  }

  /// Sends what is queued now, so closing or backgrounding the app doesn't
  /// drop the last events (or the one that led to a crash).
  static void flush() {
    unawaited(AppAnalytics.flush());
  }

  /// A sign-in was attempted. [method] is `password` or `two_factor`.
  static void signInStarted({required String method}) =>
      event('sign_in_started', {'method': method});

  /// A sign-in failed, by kind of failure only: RevenueCat's message can carry
  /// an email or an account id, so it never leaves the device.
  static void signInFailed({required String reason}) =>
      event('sign_in_failed', {'reason': reason});

  /// The first load after signing in finished, or failed.
  static void dataLoaded({
    required String result,
    required String source,
    required int durationMs,
  }) => event('data_loaded', {
    'result': result,
    'source': source,
    'duration_bucket': _bucket(durationMs),
  });

  /// Turning notifications on ended in [result]: enabled, blocked or failed.
  static void notificationsEnabled({required String result}) =>
      event('notifications_enabled', {'result': result});

  static void notificationsDisabled() => event('notifications_disabled');

  /// A project was added to, or removed from, what notifies this device.
  static void notificationsProjectToggled({required bool on}) =>
      event('notifications_project_toggled', {'on': on});

  /// Which kinds of event notify this device, as a count: the kinds themselves
  /// are the app's own vocabulary (`trial`, `refund`, ...), never user data.
  static void notificationKindsChanged({required int count}) =>
      event('notification_kinds_changed', {'kinds': count});

  /// A store product got a name, by how it was given: `manual` or `ai`.
  static void productNamed({required String source}) =>
      event('product_named', {'source': source});

  /// A question was sent to Ask. Whether it carried a transaction or a chart
  /// is useful; the question itself, and the numbers, are not sent.
  static void askMessageSent({required bool withContext}) =>
      event('ask_message_sent', {'with_context': withContext});

  /// A display preference changed: `language`, `currency`, `theme`, `fees`.
  static void preferenceChanged({required String setting}) =>
      event('preference_changed', {'setting': setting});

  /// `fast` under 500 ms, `medium` under 2 s, `slow` beyond.
  static String _bucket(int ms) => ms < 500
      ? 'fast'
      : ms < 2000
      ? 'medium'
      : 'slow';
}

/// Reports named routes (e.g. Settings) as screen views.
class TelemetryRouteObserver extends AnalyticsRouteObserver {
  TelemetryRouteObserver() : super(names: const {'/settings': 'Settings'});
}
