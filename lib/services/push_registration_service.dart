import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/core/constants/app_constants.dart';

final _log = Logger('PushRegistration');

/// Firebase anonymous auth + FCM token registration with [registerFcmToken] callable.
class PushRegistrationService {
  PushRegistrationService._();
  static final PushRegistrationService instance = PushRegistrationService._();

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
        region: AppConstants.firebaseFunctionsRegion,
      );

  /// Anonymous sign-in + ID token before any Firestore writes during [AppStartup]
  /// (e.g. RevenueCat restore). Post-frame [initialize] skips sign-in if already done.
  Future<void> ensureFirebaseAuthForFirestore() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e, st) {
      _log.warning('ensureFirebaseAuthForFirestore: $e\n$st');
    }
  }

  /// Ensures an anonymous Firebase user exists and registers the FCM token.
  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e, st) {
      _log.warning('Anonymous sign-in failed: $e\n$st');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e, st) {
      _log.warning('Notification permission: $e\n$st');
    }

    // Listen for token refresh before first fetch so we never miss a new token.
    FirebaseMessaging.instance.onTokenRefresh.listen(
      registerFcmToken,
      onError: (Object e, StackTrace st) =>
          _log.warning('onTokenRefresh error: $e\n$st'),
    );

    await _fetchAndRegisterToken(messaging);
  }

  Future<void> _fetchAndRegisterToken(FirebaseMessaging messaging) async {
    try {
      await _waitForApnsToken(messaging);
      final token = await messaging.getToken();
      if (token != null) {
        await registerFcmToken(token);
      }
    } on FirebaseException catch (e) {
      if (e.code == 'apns-token-not-set') {
        _log.info('APNS token not ready yet; will register via onTokenRefresh');
        return;
      }
      _log.warning('FCM getToken: $e\n${e.stackTrace}');
    } catch (e, st) {
      _log.warning('FCM getToken: $e\n$st');
    }
  }

  Future<void> registerFcmToken(String token) async {
    if (kIsWeb) return;
    if (FirebaseAuth.instance.currentUser == null) {
      _log.warning('registerFcmToken skipped: no Firebase user');
      return;
    }
    try {
      final callable = _functions.httpsCallable('registerFcmToken');
      await callable.call(<String, dynamic>{
        'token': token,
        'platform': defaultTargetPlatform.name,
      });
      _log.fine('FCM token registered');
    } catch (e, st) {
      _log.warning('registerFcmToken callable failed: $e\n$st');
    }
  }

  /// iOS requires the APNS token before FCM can generate a token.
  /// Polls `getAPNSToken()` up to ~5 seconds since it arrives asynchronously.
  Future<void> _waitForApnsToken(FirebaseMessaging messaging) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    for (var i = 0; i < 10; i++) {
      if (await messaging.getAPNSToken() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _log.warning('APNS token not available after 5s, proceeding anyway');
  }

  /// Signs out and creates a new anonymous user.
  Future<User?> rotatePushUser() async {
    if (kIsWeb) return null;
    await FirebaseAuth.instance.signOut();
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final messaging = FirebaseMessaging.instance;
    await _waitForApnsToken(messaging);
    final token = await messaging.getToken();
    if (token != null) {
      await registerFcmToken(token);
    }
    return cred.user;
  }
}
