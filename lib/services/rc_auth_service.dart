import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/features/ask/ask_notifier.dart';
import 'package:openrc/models/rc_login_request.dart';
import 'package:openrc/models/rc_login_response.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/services/payout_history_cache.dart';
import 'package:openrc/services/push/push_notifications.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/services/widget_data_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('RcAuthService');

final rcAuthServiceProvider = Provider<RcAuthService>((ref) {
  final api = ref.read(rcApiServiceProvider);
  final service = RcAuthService(api, ref);
  api.onUnauthorized = () {
    _log.warning('Auth token rejected by API (401), signing out');
    unawaited(service.signOut(reason: SignOutReason.sessionExpired));
  };
  return service;
});

final isSignedInProvider = StateProvider<bool>((ref) => false);
final rcMeProvider = StateProvider<RcMeResponse?>((ref) => null);

/// Why the app signed out on its own; the sign-in screen explains it.
enum SignOutReason { sessionExpired }

/// Set when the app signs out without being asked (e.g. an expired token);
/// cleared on the next successful sign-in.
final signOutReasonProvider = StateProvider<SignOutReason?>((ref) => null);

class RcAuthService {
  final RcApiService _api;
  final Ref _ref;
  // On macOS the login keychain needs no keychain-sharing entitlement, so
  // builds signed without a development team (from source) keep the session.
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  RcAuthService(this._api, this._ref);

  static const _lastEmailKey = 'last_sign_in_email';

  /// Email of the last account that signed in on this device, to prefill.
  static Future<String?> lastSignInEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_lastEmailKey)?.trim();
      return email == null || email.isEmpty ? null : email;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _rememberEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastEmailKey, email.trim());
    } catch (_) {}
  }

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
        _ref.read(signOutReasonProvider.notifier).state = null;
        _ref.read(isSignedInProvider.notifier).state = true;
        unawaited(_rememberEmail(email));
        _log.info('Signed in as ${response.email}');
        Telemetry.event('signed_in', {'two_factor': otpCode != null});

        try {
          final me = await _api.me();
          _ref.read(rcMeProvider.notifier).state = me;
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
  SignOutReason? _pendingReason;

  /// Idempotent: concurrent callers (e.g. several 401s) share one sign-out.
  /// Pass [reason] when the app signs out on its own, so the sign-in screen
  /// can say why.
  Future<void> signOut({SignOutReason? reason}) {
    _pendingReason ??= reason;
    return _signOutInFlight ??= _signOut().whenComplete(
      () => _signOutInFlight = null,
    );
  }

  Future<void> _signOut() async {
    // Someone else may sign in next, so this device's webhooks go while the
    // session can still remove them. An expired session is still this
    // person's, so notifications keep coming until they log out.
    if (_pendingReason == null) {
      try {
        await _ref
            .read(pushSettingsProvider.notifier)
            .clear()
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        _log.warning('Turning off notifications failed: $e');
      }
    }
    try {
      await _api.logout();
    } catch (e) {
      _log.warning('Logout API call failed: $e');
    }

    try {
      await WidgetDataChannel.clearWidgetData();
    } catch (e) {
      _log.warning('Clearing widget data failed: $e');
    }
    try {
      await PayoutHistoryCache.clear();
    } catch (e) {
      _log.warning('Clearing saved payouts failed: $e');
    }
    // Ask answers hold this account's revenue; the next account mustn't see them.
    try {
      await _ref.read(askNotifierProvider.notifier).clearThread();
    } catch (e) {
      _log.warning('Clearing the Ask thread failed: $e');
    }
    try {
      await _clearToken();
    } catch (e) {
      _log.warning('Clearing stored token failed: $e');
    }
    _api.clearAuthToken();
    Telemetry.event('signed_out', {
      'reason': _pendingReason == SignOutReason.sessionExpired
          ? 'session_expired'
          : 'user',
    });
    _ref.read(signOutReasonProvider.notifier).state = _pendingReason;
    _pendingReason = null;
    _ref.read(isSignedInProvider.notifier).state = false;
    _ref.read(rcMeProvider.notifier).state = null;
    _log.info('Signed out');
  }

  Future<bool> restoreSession() async {
    if (AppConstants.demoMode) {
      _api.setAuthToken('demo-token');
      _ref.read(isSignedInProvider.notifier).state = true;
      _ref.read(rcMeProvider.notifier).state = await _api.me();
      return true;
    }
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
            _ref.read(signOutReasonProvider.notifier).state =
                SignOutReason.sessionExpired;
            return false;
          }
        }
      }

      _api.setAuthToken(token);
      _ref.read(isSignedInProvider.notifier).state = true;

      try {
        final me = await _api.me();
        _ref.read(rcMeProvider.notifier).state = me;
      } on DioException catch (e) {
        final rcError = _api.parseError(e);
        if (e.response?.statusCode == 401 ||
            rcError?.code == AppConstants.rcErrorInvalidAuthToken ||
            rcError?.code == AppConstants.rcErrorExpiredAuthToken) {
          _log.warning('Stored token invalid/expired, signing out');
          await signOut(reason: SignOutReason.sessionExpired);
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
}
