import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/models/rc_login_request.dart';
import 'package:revenuecat/models/rc_login_response.dart';
import 'package:revenuecat/models/rc_me_response.dart';
import 'package:revenuecat/services/firestore_service.dart';
import 'package:revenuecat/services/push_registration_service.dart';
import 'package:revenuecat/services/rc_api_service.dart';
import 'package:revenuecat/services/widget_data_channel.dart';

final _log = Logger('RcAuthService');

final rcAuthServiceProvider = Provider<RcAuthService>((ref) {
  final api = ref.read(rcApiServiceProvider);
  final service = RcAuthService(api, ref);
  api.onUnauthorized = () {
    _log.warning('Auth token rejected by API (401), signing out');
    unawaited(service.signOut());
  };
  return service;
});

final isSignedInProvider = StateProvider<bool>((ref) => false);
final rcMeProvider = StateProvider<RcMeResponse?>((ref) => null);

class RcAuthService {
  final RcApiService _api;
  final Ref _ref;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  RcAuthService(this._api, this._ref);

  Future<RcLoginResponse?> signIn({
    required String email,
    required String password,
    String? otpCode,
  }) async {
    try {
      final request = RcLoginRequest(
        email: email,
        password: password,
        otpCode: otpCode,
      );
      final response = await _api.login(request);

      if (response.authenticationToken != null) {
        await _storeToken(
          response.authenticationToken!,
          response.authenticationTokenExpiration,
        );
        _api.setAuthToken(response.authenticationToken!);
        _ref.read(isSignedInProvider.notifier).state = true;
        _log.info('Signed in as ${response.email}');

        await PushRegistrationService.instance.ensureFirebaseAuthForFirestore();

        try {
          final me = await _api.me();
          _ref.read(rcMeProvider.notifier).state = me;
          unawaited(_syncRevenueCatToFirestore(me));
        } catch (e) {
          _log.info('Profile fetch after sign in failed: $e');
        }

        return response;
      }
      return response;
    } on DioException catch (e) {
      final rcError = _api.parseError(e);
      if (rcError != null) {
        _log.warning(
          'Sign in error [${rcError.code}]: ${rcError.message}',
        );
      }
      rethrow;
    }
  }

  Future<void>? _signOutInFlight;

  /// Idempotent: concurrent callers (e.g. several 401s) share one sign-out.
  Future<void> signOut() => _signOutInFlight ??=
      _signOut().whenComplete(() => _signOutInFlight = null);

  Future<void> _signOut() async {
    try {
      await _api.logout();
    } catch (e) {
      _log.warning('Logout API call failed: $e');
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      _log.warning('Firebase sign out failed: $e');
    }

    try {
      await WidgetDataChannel.clearWidgetData();
    } catch (e) {
      _log.warning('Clearing widget data failed: $e');
    }
    try {
      await _clearToken();
    } catch (e) {
      _log.warning('Clearing stored token failed: $e');
    }
    _api.clearAuthToken();
    _ref.read(isSignedInProvider.notifier).state = false;
    _ref.read(rcMeProvider.notifier).state = null;
    _log.info('Signed out');
  }

  Future<bool> restoreSession() async {
    try {
      final token = await _secureStorage.read(key: AppConstants.prefAuthToken);
      final expiresAtStr = await _secureStorage.read(
        key: AppConstants.prefAuthTokenExpiresAt,
      );

      if (token == null || token.isEmpty) {
        _log.info('No stored auth token found');
        return false;
      }

      if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
        final expiresAt = int.tryParse(expiresAtStr);
        if (expiresAt != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (now >= expiresAt) {
            _log.info('Auth token expired');
            await _clearToken();
            return false;
          }
        }
      }

      _api.setAuthToken(token);
      _ref.read(isSignedInProvider.notifier).state = true;

      try {
        final me = await _api.me();
        _ref.read(rcMeProvider.notifier).state = me;
        unawaited(_syncRevenueCatToFirestore(me));
      } on DioException catch (e) {
        final rcError = _api.parseError(e);
        if (e.response?.statusCode == 401 ||
            rcError?.code == AppConstants.rcErrorInvalidAuthToken ||
            rcError?.code == AppConstants.rcErrorExpiredAuthToken) {
          _log.warning('Stored token invalid/expired, signing out');
          await signOut();
          return false;
        }
        // Offline or server error: keep the session, screens retry later.
        _log.info('Profile fetch failed during restore: ${e.type.name}');
      } catch (e) {
        _log.warning('Profile parse failed during restore: $e');
      }

      _log.info('Session restored');
      return true;
    } catch (e, st) {
      _log.severe('Failed to restore session', e, st);
      return false;
    }
  }

  Future<void> _storeToken(String token, String? expiration) async {
    await _secureStorage.write(key: AppConstants.prefAuthToken, value: token);
    if (expiration != null && expiration.isNotEmpty) {
      try {
        final dt = DateTime.tryParse(expiration);
        if (dt != null) {
          final epoch = dt.millisecondsSinceEpoch ~/ 1000;
          await _secureStorage.write(
            key: AppConstants.prefAuthTokenExpiresAt,
            value: epoch.toString(),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _clearToken() async {
    await _secureStorage.delete(key: AppConstants.prefAuthToken);
    await _secureStorage.delete(key: AppConstants.prefAuthTokenExpiresAt);
  }

  Future<void> _syncRevenueCatToFirestore(RcMeResponse me) async {
    try {
      await _ref.read(firestoreServiceProvider).syncRevenueCatProfile(
            email: me.email,
            distinctId: me.distinctId,
            name: me.name,
          );
    } catch (e, st) {
      _log.fine('Firestore RC sync skipped: $e\n$st');
    }
  }
}
