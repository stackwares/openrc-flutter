import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

/// Short, user-facing message for a failed RevenueCat API call.
///
/// Prefers the server's own message, then explains network problems in plain
/// words instead of a generic "Request failed".
String friendlyApiErrorMessage(Object error, {String? serverMessage}) {
  final server = serverMessage?.trim();
  if (server != null && server.isNotEmpty) return server;
  if (error is! DioException) return 'errors.generic'.tr();
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return 'errors.timeout'.tr();
    case DioExceptionType.connectionError:
      return 'errors.noInternet'.tr();
    case DioExceptionType.cancel:
      return 'errors.cancelled'.tr();
    case DioExceptionType.badCertificate:
      return 'errors.badCertificate'.tr();
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return 'errors.sessionExpired'.tr();
      }
      if (code == 429) return 'errors.tooManyRequests'.tr();
      if (code != null && code >= 500) {
        return 'errors.serverError'.tr();
      }
      return 'errors.requestFailed'.tr();
  }
}
