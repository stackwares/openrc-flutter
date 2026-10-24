import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/models/rc_chart_response.dart';
import 'package:openrc/models/rc_error_response.dart';
import 'package:openrc/models/rc_login_request.dart';
import 'package:openrc/models/rc_login_response.dart';
import 'package:openrc/models/rc_me_response.dart';
import 'package:openrc/models/rc_overview_response.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/models/rc_transaction_detail.dart';
import 'package:openrc/models/rc_transaction_detail_activity.dart';
import 'package:openrc/models/rc_webhook.dart';
import 'package:openrc/services/demo/demo_adapter.dart';

/// [Options.extra] key: short label for debug logging (e.g. `transactions:scroll`).
const kRcApiRequestContextExtraKey = 'rc_api_request_context';

final _log = Logger('RcApiService');

/// Most chart series + paginated tx loads: FINE only ([configureAppLogging] caps RcApiService at INFO).
bool _rcApiQuietPath(String path, String? requestContext) {
  if (path.contains('/charts_v2/') && !path.endsWith('/overview')) {
    return true;
  }
  final ctx = requestContext ?? '';
  if (path.endsWith('/me/transactions')) {
    return ctx != 'transactions:initial';
  }
  return false;
}

String? _rcApiContextSuffix(String? ctx) {
  if (ctx == null || ctx.isEmpty) return null;
  return switch (ctx) {
    'transactions:initial' => 'tx initial',
    'transactions:scroll' => 'tx scroll',
    _ => ctx,
  };
}

void _rcApiLogSuccess(Response<dynamic> response) {
  final ro = response.requestOptions;
  final path = ro.path;
  final ctx = ro.extra[kRcApiRequestContextExtraKey] as String?;
  final code = response.statusCode ?? 0;
  final label = _rcApiContextSuffix(ctx);
  final tail = label != null ? ' — $label' : '';
  final line = '[API] $code ${ro.method} $path$tail';
  if (_rcApiQuietPath(path, ctx)) {
    _log.fine(line);
  } else {
    _log.info(line);
  }
}

void _rcApiLogError(DioException e) {
  final ro = e.requestOptions;
  final code = e.response?.statusCode;
  final kind = code?.toString() ?? e.type.name;
  _log.warning('[API] $kind ${ro.method} ${ro.path}');
}

enum RcEndpoint { login, logout, me, projects, overview, transactions }

final rcApiServiceProvider = Provider<RcApiService>((ref) {
  if (AppConstants.demoMode) {
    return RcApiService(
      dio: Dio()..httpClientAdapter = DemoAdapter(),
      internalDio: Dio()..httpClientAdapter = DemoAdapter(),
    );
  }
  return RcApiService();
});

/// Throws a [DioException] when a successful response has no usable body,
/// instead of crashing on a null-check.
T requireBody<T>(Response<T> response) {
  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      error: 'Empty response body',
    );
  }
  return data;
}

class RcApiService {
  late final Dio _dio;
  late final Dio _internal;
  String? _authToken;

  /// Called once per token when an authenticated request returns 401, so the
  /// app can sign out instead of showing endless errors.
  void Function()? onUnauthorized;
  String? _unauthorizedReportedFor;

  RcApiService({Dio? dio, Dio? internalDio}) {
    _dio = dio ?? Dio(_baseOptions(AppConstants.rcApiBaseUrl));
    _internal =
        internalDio ?? Dio(_baseOptions(AppConstants.rcApiInternalBaseUrl));
    for (final client in [_dio, _internal]) {
      client.interceptors.add(
        InterceptorsWrapper(
          onError: (e, handler) {
            _maybeReportUnauthorized(e);
            handler.next(e);
          },
        ),
      );
    }

    if (kDebugMode) {
      _internal.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            _rcApiLogSuccess(response);
            handler.next(response);
          },
          onError: (e, handler) {
            _rcApiLogError(e);
            handler.next(e);
          },
        ),
      );
      _dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            _rcApiLogSuccess(response);
            handler.next(response);
          },
          onError: (e, handler) {
            _rcApiLogError(e);
            handler.next(e);
          },
        ),
      );
    }
  }

  static BaseOptions _baseOptions(String baseUrl) => BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 20),
    headers: {'X-Requested-With': AppConstants.headerXRequestedWith},
  );

  void _maybeReportUnauthorized(DioException e) {
    final token = _authToken;
    if (token == null || e.response?.statusCode != 401) return;
    if (e.requestOptions.path.endsWith('/login') ||
        e.requestOptions.path.endsWith('/logout')) {
      return;
    }
    if (_unauthorizedReportedFor == token) return;
    _unauthorizedReportedFor = token;
    onUnauthorized?.call();
  }

  void setAuthToken(String token) {
    _authToken = token;
    _unauthorizedReportedFor = null;
    for (final client in [_dio, _internal]) {
      client.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  void clearAuthToken() {
    _authToken = null;
    for (final client in [_dio, _internal]) {
      client.options.headers.remove('Authorization');
    }
  }

  String? get authToken => _authToken;

  Future<RcLoginResponse> login(RcLoginRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/login',
      data: request.toJson(),
    );
    return RcLoginResponse.fromJson(requireBody(response));
  }

  Future<void> logout() async {
    await _dio.post(
      '/logout',
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Future<RcMeResponse> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return RcMeResponse.fromJson(requireBody(response));
  }

  Future<List<RcProject>> projects() async {
    final response = await _internal.get<List<dynamic>>('/me/projects');
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RcProject.fromJson)
        .toList();
  }

  Future<RcTransactionsResponse> transactions(
    RcTransactionsRequest request, {
    String? requestContext,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/transactions',
      queryParameters: request.toQueryParameters(),
      options: Options(
        extra: requestContext != null && requestContext.isNotEmpty
            ? {kRcApiRequestContextExtraKey: requestContext}
            : const {},
      ),
    );
    return RcTransactionsResponse.fromJson(requireBody(response));
  }

  Future<RcTransactionDetailResponse> transactionDetail({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/apps/$projectId/subscribers/$subscriberId',
      queryParameters: {'sandbox_mode': sandboxMode},
    );
    return RcTransactionDetailResponse.fromJson(requireBody(response));
  }

  Future<RcTransactionDetailActivityResponse> transactionDetailActivity({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    final response = await _internal.get<Map<String, dynamic>>(
      '/me/apps/$projectId/subscribers/$subscriberId/activity',
      queryParameters: {'sandbox_mode': sandboxMode},
    );
    return RcTransactionDetailActivityResponse.fromJson(requireBody(response));
  }

  /// RevenueCat dashboard overview (same contract as [Kedi `charts_v2/overview`](https://github.com/sereisoglu/Kedi)).
  Future<RcOverviewResponse> overview() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/charts_v2/overview',
    );
    return RcOverviewResponse.fromJson(requireBody(response));
  }

  /// Chart series under `charts_v2` (public `/v1/developers` base). [resolution] is the API enum int (0 = day per Kedi).
  /// [filters] narrows the series by dimension, e.g. `{'store': ['app_store']}`.
  /// This API takes each dimension as its own parameter with values joined
  /// by commas (`store=app_store,mac_app_store`); a repeated parameter keeps
  /// only its first value, and the JSON `filters` of the v2 REST API is
  /// ignored.
  Future<RcChartResponse> charts({
    required String name,
    int resolution = 0,
    String? startDate,
    String? endDate,
    String? revenueType,
    Map<String, List<String>>? filters,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/charts_v2/$name',
      queryParameters: <String, dynamic>{
        'resolution': resolution,
        'start_date': ?startDate,
        'end_date': ?endDate,
        'revenue_type': ?revenueType,
        if (filters != null)
          for (final e in filters.entries) e.key: e.value.join(','),
      },
    );
    return RcChartResponse.fromJson(requireBody(response));
  }

  /// A project's webhook integrations (dashboard API, as used by Kedi).
  Future<List<RcWebhook>> webhooks(String projectId) async {
    final response = await _internal.get<List<dynamic>>(
      '/me/projects/$projectId/integrations/webhooks',
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RcWebhook.fromJson)
        .toList();
  }

  Future<RcWebhook> createWebhook(String projectId, RcWebhookInput input) async {
    final response = await _internal.post<Map<String, dynamic>>(
      '/me/projects/$projectId/integrations/webhooks',
      data: input.toJson(),
    );
    return RcWebhook.fromJson(requireBody(response));
  }

  Future<void> updateWebhook(
    String projectId,
    String webhookId,
    RcWebhookInput input,
  ) async {
    await _internal.put<dynamic>(
      '/me/projects/$projectId/integrations/webhooks/$webhookId',
      data: input.toJson(),
    );
  }

  Future<void> deleteWebhook(String projectId, String webhookId) async {
    await _internal.delete<dynamic>(
      '/me/projects/$projectId/integrations/webhooks/$webhookId',
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  /// Whether [error] is RevenueCat saying a resource is already gone, which
  /// for a deletion is the outcome asked for.
  bool isNotFound(Object error) =>
      error is DioException && error.response?.statusCode == 404;

  /// Has RevenueCat send its test event now; the result says how the
  /// webhook's endpoint answered.
  Future<RcWebhookTestResult> testWebhook(
    String projectId,
    String webhookId,
  ) async {
    final response = await _internal.post<Map<String, dynamic>>(
      '/me/projects/$projectId/integrations/webhooks/$webhookId/test_webhook',
      options: Options(contentType: Headers.jsonContentType),
    );
    return RcWebhookTestResult.fromJson(requireBody(response));
  }

  RcErrorResponse? parseError(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        try {
          return RcErrorResponse.fromJson(data);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }
}
