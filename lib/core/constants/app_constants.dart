abstract class AppConstants {
  static const String appName = 'RevenueCat';

  static const String rcApiBaseUrl = 'https://api.revenuecat.com/v1/developers';
  static const String rcApiInternalBaseUrl =
      'https://api.revenuecat.com/internal/v1/developers';

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

  /// Full HTTPS URL of the deployed `revenueCatWebhook` Cloud Function (no `?` query), e.g.
  /// `https://us-central1-PROJECT.cloudfunctions.net/revenueCatWebhook`
  static const String rcWebhookRelayUrl = String.fromEnvironment(
    'RC_WEBHOOK_RELAY_URL',
    defaultValue: '',
  );

  /// Region for [registerFcmToken] and relay deployment (default `us-central1`).
  static const String firebaseFunctionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );
}
