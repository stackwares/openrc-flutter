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

    try {
      final token = await messaging.getToken();
      if (token != null) {
        await registerFcmToken(token);
      }
    } catch (e, st) {
      _log.warning('FCM getToken: $e\n$st');
    }

    FirebaseMessaging.instance.onTokenRefresh.listen(
      registerFcmToken,
      onError: (Object e, StackTrace st) =>
          _log.warning('onTokenRefresh error: $e\n$st'),
    );
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

  /// Signs out and creates a new anonymous user. Caller must update RevenueCat webhooks.
  Future<User?> rotatePushUser() async {
    if (kIsWeb) return null;
    await FirebaseAuth.instance.signOut();
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await registerFcmToken(token);
    }
    return cred.user;
  }
}
