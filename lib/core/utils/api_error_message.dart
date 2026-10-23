import 'package:dio/dio.dart';

/// Short, user-facing message for a failed RevenueCat API call.
///
/// Prefers the server's own message, then explains network problems in plain
/// words instead of a generic "Request failed".
String friendlyApiErrorMessage(Object error, {String? serverMessage}) {
  final server = serverMessage?.trim();
  if (server != null && server.isNotEmpty) return server;
  if (error is! DioException) return 'Something went wrong. Please try again.';
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return 'RevenueCat is taking too long to respond. Please try again.';
    case DioExceptionType.connectionError:
      return 'No internet connection. Check your network and try again.';
    case DioExceptionType.cancel:
      return 'Request cancelled.';
    case DioExceptionType.badCertificate:
      return 'Secure connection failed.';
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      final code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return 'Your session has expired. Please sign in again.';
      }
      if (code == 429) return 'Too many requests. Please wait a moment.';
      if (code != null && code >= 500) {
        return 'RevenueCat is having trouble right now. Please try again later.';
      }
      return 'Request failed. Please try again.';
  }
}
