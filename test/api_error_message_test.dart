import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/api_error_message.dart';

DioException _err(DioExceptionType type, {int? status}) {
  final ro = RequestOptions(path: '/x');
  return DioException(
    requestOptions: ro,
    type: type,
    response: status == null
        ? null
        : Response(requestOptions: ro, statusCode: status),
  );
}

void main() {
  test('prefers server message', () {
    expect(
      friendlyApiErrorMessage(
        _err(DioExceptionType.badResponse, status: 400),
        serverMessage: 'Bad OTP',
      ),
      'Bad OTP',
    );
  });

  test('explains offline and timeouts', () {
    expect(
      friendlyApiErrorMessage(_err(DioExceptionType.connectionError)),
      contains('internet'),
    );
    expect(
      friendlyApiErrorMessage(_err(DioExceptionType.receiveTimeout)),
      contains('too long'),
    );
  });

  test('maps status codes', () {
    expect(
      friendlyApiErrorMessage(_err(DioExceptionType.badResponse, status: 401)),
      contains('sign in'),
    );
    expect(
      friendlyApiErrorMessage(_err(DioExceptionType.badResponse, status: 503)),
      contains('trouble'),
    );
    expect(friendlyApiErrorMessage(StateError('x')), contains('went wrong'));
  });
}
