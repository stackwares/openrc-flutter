import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:openrc/core/constants/app_constants.dart';

/// Build settings for push notifications.
///
/// Notifications need a Firebase project for Cloud Messaging, passed with
/// `--dart-define-from-file=dart_defines/firebase.json` (see
/// `dart_defines/firebase.example.json`). Builds without it have no
/// notifications, the way builds without a PostHog token send no telemetry.
abstract final class PushConfig {
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _appleApiKey = String.fromEnvironment('FIREBASE_APPLE_API_KEY');
  static const _appleAppId = String.fromEnvironment('FIREBASE_APPLE_APP_ID');

  /// The notifier (`notifier/`) that turns RevenueCat webhooks into pushes.
  /// It must send through the same Firebase project as this build.
  static const String notifierUrl = String.fromEnvironment(
    'OPENRC_NOTIFIER_URL',
    defaultValue: 'https://openrc-notifier.stackwares.workers.dev',
  );

  /// What to paste into RevenueCat as the webhook URL.
  static String get webhookUrl => '$notifierUrl/revenuecat';

  /// Firebase settings for this platform, or null when the build has none
  /// or the platform gets no notifications (the web, Windows, Linux).
  ///
  /// macOS waits too: its builds are signed ad hoc, and the push entitlement
  /// (`com.apple.developer.aps-environment`) needs a team's provisioning
  /// profile. Once they're signed with one, add the entitlement to both
  /// `macos/Runner/*.entitlements` and macOS here.
  static FirebaseOptions? get firebaseOptions {
    if (kIsWeb || AppConstants.demoMode) return null;
    final (apiKey, appId) = switch (defaultTargetPlatform) {
      TargetPlatform.android => (_androidApiKey, _androidAppId),
      TargetPlatform.iOS => (_appleApiKey, _appleAppId),
      _ => ('', ''),
    };
    if ([apiKey, appId, _projectId, _senderId].any((v) => v.isEmpty)) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      iosBundleId: 'com.openrc.app',
    );
  }
}
