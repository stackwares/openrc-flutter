import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _log = Logger('FirestoreService');

/// Retries for [cloud_firestore/unknown] "Unable to establish connection on channel"
/// right after startup (Android Pigeon not ready yet).
const _kFirestoreWriteMaxAttempts = 4;
const _kFirestoreWriteBaseDelayMs = 120;

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService(FirebaseFirestore.instance);
});

/// Firestore `users/{firebaseUid}` — same pattern as SteinAI (`createOrUpdateUser`, fields, merge).
class FirestoreService {
  FirestoreService(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>>? _userDoc() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  /// Ensures the ID token is available so Firestore sends [request.auth] with writes/reads.
  Future<bool> _ensureAuthTokenForFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await user.getIdToken();
      return true;
    } catch (e, st) {
      _log.fine('Auth token not available for Firestore: $e\n$st');
      return false;
    }
  }

  /// Merges [data] into `users/{uid}`. No pre-read (avoids an extra Pigeon call
  /// while the Firestore channel is still coming up after startup).
  Future<void> createOrUpdateUser(Map<String, dynamic> data) async {
    final doc = _userDoc();
    if (doc == null) {
      _log.fine('createOrUpdateUser skipped: no Firebase user');
      return;
    }
    final payload = <String, dynamic>{
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _setWithRetries(doc, payload);
  }

  Future<void> _setWithRetries(
    DocumentReference<Map<String, dynamic>> doc,
    Map<String, dynamic> payload,
  ) async {
    if (!await _ensureAuthTokenForFirestore()) {
      _log.fine('Firestore set skipped: no Firebase user or token');
      return;
    }
    Object? lastError;
    StackTrace? lastSt;
    for (var attempt = 0; attempt < _kFirestoreWriteMaxAttempts; attempt++) {
      if (attempt > 0) {
        final delayMs = _kFirestoreWriteBaseDelayMs * (1 << (attempt - 1));
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      try {
        await doc.set(payload, SetOptions(merge: true));
        _log.fine('User document updated');
        return;
      } catch (e, st) {
        lastError = e;
        lastSt = st;
        final retry = _isFirestoreTransientChannelError(e);
        _log.fine(
          'Firestore set attempt ${attempt + 1}/$_kFirestoreWriteMaxAttempts: $e'
          '${retry ? ' (will retry)' : ''}',
        );
        if (!retry || attempt == _kFirestoreWriteMaxAttempts - 1) {
          break;
        }
      }
    }
    _log.warning('Failed to update user document: $lastError\n$lastSt');
  }

  bool _isFirestoreTransientChannelError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('connection on channel') ||
        s.contains('channel-error') ||
        s.contains('unavailable') ||
        s.contains('cloud_firestore/unknown');
  }

  Future<Map<String, dynamic>?> getUser() async {
    final doc = _userDoc();
    if (doc == null) return null;
    if (!await _ensureAuthTokenForFirestore()) return null;
    try {
      final snapshot = await doc.get();
      return snapshot.data();
    } catch (e, st) {
      _log.warning('Failed to get user document: $e\n$st');
      return null;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream() {
    final doc = _userDoc();
    return doc?.snapshots();
  }

  Future<void> updateUserField(String field, Object? value) async {
    final doc = _userDoc();
    if (doc == null) return;
    await _setWithRetries(doc, {
      field: value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Device / app metadata (SteinAI `_postAuthSetup` style).
  Future<void> syncDeviceProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final info = await _packageInfoOrUnknown();
    final localeName = _localeTag();
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : defaultTargetPlatform == TargetPlatform.macOS
                ? 'macos'
                : 'android';

    await createOrUpdateUser({
      'timezone': DateTime.now().timeZoneName,
      'locale': localeName,
      'version': info.version,
      'build': info.build,
      'platform': platform,
      'rcUserId': user.uid,
      'lastSigninTime': DateTime.now().toIso8601String(),
    });
  }

  /// Call when RevenueCat dashboard session is active ([RcMeResponse] loaded).
  Future<void> syncRevenueCatProfile({
    required String? email,
    required String? distinctId,
    required String? name,
  }) async {
    await createOrUpdateUser({
      'rcEmail': email,
      'rcDistinctId': distinctId,
      'rcName': name,
      'rcSignedIn': true,
      'lastRcSync': DateTime.now().toIso8601String(),
    });
  }

  /// Clears RC dashboard fields when logging out of RevenueCat (Firebase anon stays).
  Future<void> clearRevenueCatProfile() async {
    final doc = _userDoc();
    if (doc == null) return;
    await _setWithRetries(doc, {
      'rcEmail': FieldValue.delete(),
      'rcDistinctId': FieldValue.delete(),
      'rcName': FieldValue.delete(),
      'rcSignedIn': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static String _localeTag() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    } catch (_) {
      return PlatformDispatcher.instance.locale.toLanguageTag();
    }
  }

  static Future<({String version, String build})> _packageInfoOrUnknown() async {
    try {
      final pi = await PackageInfo.fromPlatform();
      return (version: pi.version, build: pi.buildNumber);
    } on MissingPluginException catch (_) {
      return (version: 'unknown', build: 'unknown');
    } catch (_) {
      return (version: 'unknown', build: 'unknown');
    }
  }
}
