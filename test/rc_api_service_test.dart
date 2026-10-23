import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/rc_api_service.dart';

/// Answers every request with [status] and [body] without touching the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, [this.body = '']);
  final int status;
  final String body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('empty body throws DioException instead of crashing', () async {
    final dio = Dio()..httpClientAdapter = _FakeAdapter(200);
    final api = RcApiService(dio: dio, internalDio: Dio());
    await expectLater(api.me(), throwsA(isA<DioException>()));
  });

  test('401 on authenticated call reports once per token', () async {
    final dio = Dio()..httpClientAdapter = _FakeAdapter(401, '{"code":7224}');
    final api = RcApiService(dio: dio, internalDio: Dio());
    var hits = 0;
    api.onUnauthorized = () => hits++;
    api.setAuthToken('t1');
    await expectLater(api.me(), throwsA(isA<DioException>()));
    await expectLater(api.overview(), throwsA(isA<DioException>()));
    expect(hits, 1);
    api.setAuthToken('t2');
    await expectLater(api.me(), throwsA(isA<DioException>()));
    expect(hits, 2);
  });

  test(
    '401 without a token (e.g. bad login) does not trigger sign out',
    () async {
      final dio = Dio()..httpClientAdapter = _FakeAdapter(401, '{"code":7002}');
      final api = RcApiService(dio: dio, internalDio: Dio());
      var hits = 0;
      api.onUnauthorized = () => hits++;
      await expectLater(api.me(), throwsA(isA<DioException>()));
      expect(hits, 0);
    },
  );

  test('parseError tolerates unexpected shapes', () {
    final ro = RequestOptions(path: '/x');
    final e = DioException(
      requestOptions: ro,
      response: Response(requestOptions: ro, data: {'code': 'not-int'}),
    );
    expect(RcApiService(dio: Dio(), internalDio: Dio()).parseError(e), isNull);
  });
}
