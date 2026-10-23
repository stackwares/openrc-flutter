import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:openrc/services/telemetry_web_stub.dart'
    if (dart.library.js_interop) 'package:openrc/services/telemetry_web.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('Telemetry');

/// Whether this install shares anonymous usage and crash reports (Settings).
final telemetryEnabledProvider = StateProvider<bool>(
  (ref) => Telemetry.enabled,
);

/// Anonymous usage events and crash reports, sent to PostHog.
///
/// Builds send nothing unless they pass a project token
/// (`--dart-define=POSTHOG_PROJECT_TOKEN=phc_...`), so a build from source is
/// silent by default. Events never carry RevenueCat account details, app
/// names or amounts, and no person profiles are created.
abstract final class Telemetry {
  static const _token = String.fromEnvironment('POSTHOG_PROJECT_TOKEN');
  static const _host = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );
  static const _enabledKey = 'telemetry_enabled';

  /// True when this build has a PostHog project token.
  static bool get isAvailable => _token.isNotEmpty;

  static bool _started = false;
  static bool _enabled = false;

  /// The user's choice; true until they turn it off.
  static bool get enabled => _enabled;

  static bool get _active => _started && _enabled;

  /// Starts PostHog with error autocapture. Safe to call when unavailable.
  static Future<void> start() async {
    if (!isAvailable || _started) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      // posthog-js is set up by the page; the Flutter plugin attaches to it.
      if (kIsWeb && !initPosthogJs(_token, _host, optOut: !_enabled)) return;
      final config = PostHogConfig(_token)
        ..host = _host
        ..debug = kDebugMode
        ..optOut = !_enabled
        ..personProfiles = PostHogPersonProfiles.never
        ..captureApplicationLifecycleEvents = true
        ..preloadFeatureFlags = false
        ..sessionReplay = false
        ..surveys = false
        ..capturePushNotificationSubscriptions = false
        ..capturePushNotificationOpened = false;
      config.errorTrackingConfig
        ..captureFlutterErrors = true
        ..capturePlatformDispatcherErrors = true
        ..captureNativeExceptions = true
        ..inAppIncludes.add('openrc');
      await Posthog().setup(config);
      _started = true;
    } catch (e, st) {
      _log.warning('PostHog setup failed', e, st);
    }
  }

  /// Turns sharing on or off and remembers the choice.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
      if (_started) await (value ? Posthog().optIn() : Posthog().optOut());
    } catch (e, st) {
      _log.warning('Updating telemetry choice failed', e, st);
    }
  }

  static void screen(String name) {
    if (!_active) return;
    unawaited(Posthog().screen(screenName: name).catchError(_ignore));
  }

  static void event(String name, [Map<String, Object>? properties]) {
    if (!_active) return;
    unawaited(
      Posthog()
          .capture(eventName: name, properties: properties)
          .catchError(_ignore),
    );
  }

  static void _ignore(Object e) => _log.fine('Telemetry call failed: $e');
}

/// Reports named routes (e.g. Settings) as screen views.
class TelemetryRouteObserver extends NavigatorObserver {
  static const _names = {'/settings': 'Settings'};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _names[route.settings.name];
    if (name != null) Telemetry.screen(name);
  }
}
