import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/core/constants/app_constants.dart';

final _log = Logger('PushRegistration');

/// Firebase anonymous auth plus FCM registration with the
/// [registerFcmToken] callable.
///
/// firebase_messaging 17 registers an installation id (FID) via [FirebaseMessaging.register]
/// and [FirebaseMessaging.onRegistered]. The webhook relay sends to that id.
class PushRegistrationService {
  PushRegistrationService._();
  static final PushRegistrationService instance = PushRegistrationService._();

  StreamSubscription<String>? _registeredSub;
  StreamSubscription<String>? _unregisteredSub;

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

  /// Ensures an anonymous Firebase user exists and registers this install's FID.
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

    // Listen before register() so the FID emitted by this call is not missed.
    _registeredSub ??= messaging.onRegistered.listen(
      registerFcmToken,
      onError: (Object e, StackTrace st) =>
          _log.warning('onRegistered error: $e\n$st'),
    );
    _unregisteredSub ??= messaging.onUnregistered.listen(
      _unregisterFid,
      onError: (Object e, StackTrace st) =>
          _log.warning('onUnregistered error: $e\n$st'),
    );

    await _registerInstallation(messaging);
  }

  Future<void> _registerInstallation(FirebaseMessaging messaging) async {
    try {
      await _waitForApnsToken(messaging);
      await messaging.register();
    } on FirebaseException catch (e) {
      if (e.code == 'apns-token-not-set') {
        _log.info('APNS token not ready yet; will register via onRegistered');
        return;
      }
      _log.warning('FCM register: $e\n${e.stackTrace}');
    } catch (e, st) {
      _log.warning('FCM register: $e\n$st');
    }
  }

  /// Installation id last registered with the relay (current Firebase user).
  String? _lastFid;

  bool get _pushSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> registerFcmToken(String fid) async {
    _lastFid = fid;
    await _callTokenEndpoint(fid, remove: false);
  }

  Future<void> _unregisterFid(String fid) async {
    if (_lastFid == fid) _lastFid = null;
    await _callTokenEndpoint(fid, remove: true);
  }

  /// Stops this device receiving sale pushes for the signed-in account.
  /// Call before signing out of Firebase (the relay keys tokens by user).
  Future<void> unregisterForSignOut() async {
    if (!_pushSupported) return;
    final fid = _lastFid;
    if (fid == null) return;
    await _callTokenEndpoint(fid, remove: true);
  }

  /// Registers this device for the current Firebase user after a sign-in.
  Future<void> registerForSignedInUser() async {
    if (!_pushSupported) return;
    final fid = _lastFid;
    if (fid == null) {
      await initialize();
      return;
    }
    await _callTokenEndpoint(fid, remove: false);
  }

  Future<void> _callTokenEndpoint(String fid, {required bool remove}) async {
    if (kIsWeb) return;
    if (FirebaseAuth.instance.currentUser == null) {
      _log.warning('FCM registration skipped: no Firebase user');
      return;
    }
    try {
      final callable = _functions.httpsCallable('registerFcmToken');
      await callable.call(<String, dynamic>{
        'token': fid,
        'platform': defaultTargetPlatform.name,
        'remove': remove,
      });
      _log.fine(remove ? 'FCM installation removed' : 'FCM installation registered');
    } catch (e, st) {
      _log.warning('registerFcmToken callable failed: $e\n$st');
    }
  }

  /// iOS requires the APNS token before FCM can register the installation.
  /// Polls `getAPNSToken()` up to ~5 seconds since it arrives asynchronously.
  Future<void> _waitForApnsToken(FirebaseMessaging messaging) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    for (var i = 0; i < 10; i++) {
      if (await messaging.getAPNSToken() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _log.warning('APNS token not available after 5s, proceeding anyway');
  }

  /// Signs out and creates a new anonymous user, then registers that user's FID.
  Future<User?> rotatePushUser() async {
    if (kIsWeb) return null;
    await FirebaseAuth.instance.signOut();
    final cred = await FirebaseAuth.instance.signInAnonymously();
    await _registerInstallation(FirebaseMessaging.instance);
    return cred.user;
  }
}
