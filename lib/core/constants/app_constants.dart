import 'package:flutter/foundation.dart';

abstract class AppConstants {
  static const String appName = 'OpenRC';

  static const String repoUrl = 'https://github.com/stackwares/openrc';
  static const String newIssueUrl = '$repoUrl/issues/new/choose';

  /// The OpenRC relay (`relay/`). RevenueCat's API answers browsers only
  /// from its own dashboard, so the web app reaches it through this. Point
  /// `--dart-define=OPENRC_RELAY_URL=...` at your own deployment.
  static const String relayUrl = String.fromEnvironment(
    'OPENRC_RELAY_URL',
    defaultValue: 'https://openrc-relay.stackwares.workers.dev',
  );

  static String get _rcApiOrigin =>
      kIsWeb ? relayUrl : 'https://api.revenuecat.com';
  static String get rcApiBaseUrl => '$_rcApiOrigin/v1/developers';
  static String get rcApiInternalBaseUrl =>
      '$_rcApiOrigin/internal/v1/developers';

  static const String supportEmail = 'support@revenuecat.com';

  static const String prefAuthToken = 'rc_auth_token';
  static const String prefAuthTokenExpiresAt = 'rc_auth_token_expires_at';

  static const int rcErrorInvalidEmailOrPassword = 7002;
  static const int rcErrorOtpNeeded = 7008;
  static const int rcErrorInvalidOtp = 7011;
  static const int rcErrorTooManyRequests = 7114;
  static const int rcErrorInvalidAuthToken = 7224;
  static const int rcErrorInvalidXRequestedWith = 7632;
  static const int rcErrorExpiredAuthToken = 7667;

  static const String headerXRequestedWith = 'XMLHttpRequest';

  /// Looks up App Store / Google Play icons for the web app. Native builds
  /// ask the stores directly; browsers are blocked by CORS.
  static String get appIconLookupUrl => '$relayUrl/icon';
}
