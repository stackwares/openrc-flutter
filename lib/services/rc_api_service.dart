import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/models/rc_chart_response.dart';
import 'package:revenuecat/models/rc_error_response.dart';
import 'package:revenuecat/models/rc_login_request.dart';
import 'package:revenuecat/models/rc_login_response.dart';
import 'package:revenuecat/models/rc_me_response.dart';
import 'package:revenuecat/models/rc_overview_response.dart';
import 'package:revenuecat/models/rc_project.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/models/rc_transaction_detail.dart';
import 'package:revenuecat/models/rc_transaction_detail_activity.dart';
import 'package:revenuecat/models/rc_webhook.dart';

/// [Options.extra] key: short label for debug logging (e.g. `transactions:scroll`).
const kRcApiRequestContextExtraKey = 'rc_api_request_context';

final _log = Logger('RcApiService');

enum RcEndpoint {
  login,
  logout,
  me,
  projects,
  overview,
  transactions,
}

final rcApiServiceProvider = Provider<RcApiService>((ref) {
  return RcApiService();
});

class RcApiService {
  late final Dio _dio;
  String? _authToken;

  RcApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.rcApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'X-Requested-With': AppConstants.headerXRequestedWith,
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final ctx = options.extra[kRcApiRequestContextExtraKey] as String?;
          final q = _compactQueryForLog(options.queryParameters);
          final line = StringBuffer('━━━ RC API ━━━ ${options.method} ${options.path}');
          if (ctx != null && ctx.isNotEmpty) {
            line.write(' │ ');
            line.write(ctx);
          }
          if (q != null) {
            line.write(' │ ');
            line.write(q);
          }
          _log.info(line.toString());
          handler.next(options);
        },
        onResponse: (response, handler) {
          _log.fine(
            '[Dio] ${response.statusCode} ${response.requestOptions.uri}',
          );
          handler.next(response);
        },
        onError: (e, handler) {
          final code = e.response?.statusCode;
          _log.fine(
            '[Dio] ${code ?? e.type} ${e.requestOptions.uri}',
          );
          handler.next(e);
        },
      ));
    }
  }

  /// Pagination / filter-related query keys only (keeps logs short).
  static String? _compactQueryForLog(Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return null;
    const keys = ['limit', 'start_from', 'end_date', 'sandbox_mode'];
    final parts = <String>[];
    for (final k in keys) {
      if (query.containsKey(k)) {
        parts.add('$k=${query[k]}');
      }
    }
    if (parts.isNotEmpty) return parts.join(' ');
    return query.entries
        .take(4)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
  }

  void setAuthToken(String token) {
    _authToken = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearAuthToken() {
    _authToken = null;
    _dio.options.headers.remove('Authorization');
  }

  String? get authToken => _authToken;

  Future<RcLoginResponse> login(RcLoginRequest request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/login',
      data: request.toJson(),
    );
    return RcLoginResponse.fromJson(response.data!);
  }

  Future<void> logout() async {
    await _dio.post(
      '/logout',
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Future<RcMeResponse> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return RcMeResponse.fromJson(response.data!);
  }

  Future<List<RcProject>> projects() async {
    final response = await _internalDio().get<List<dynamic>>('/me/projects');
    return (response.data ?? [])
        .map((e) => RcProject.fromJson(e as Map<String, dynamic>))
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
    return RcTransactionsResponse.fromJson(response.data!);
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
    return RcTransactionDetailResponse.fromJson(response.data!);
  }

  Future<RcTransactionDetailActivityResponse> transactionDetailActivity({
    required String projectId,
    required String subscriberId,
    bool sandboxMode = false,
  }) async {
    final response = await _internalDio().get<Map<String, dynamic>>(
      '/me/apps/$projectId/subscribers/$subscriberId/activity',
      queryParameters: {'sandbox_mode': sandboxMode},
    );
    return RcTransactionDetailActivityResponse.fromJson(response.data!);
  }

  /// RevenueCat dashboard overview (same contract as [Kedi `charts_v2/overview`](https://github.com/sereisoglu/Kedi)).
  Future<RcOverviewResponse> overview() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/charts_v2/overview',
    );
    return RcOverviewResponse.fromJson(response.data!);
  }

  /// Chart series under `charts_v2` (public `/v1/developers` base). [resolution] is the API enum int (0 = day per Kedi).
  Future<RcChartResponse> charts({
    required String name,
    int resolution = 0,
    String? startDate,
    String? endDate,
    String? revenueType,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/charts_v2/$name',
      queryParameters: <String, dynamic>{
        'resolution': resolution,
        'start_date': ?startDate,
        'end_date': ?endDate,
        'revenue_type': ?revenueType,
      },
    );
    return RcChartResponse.fromJson(response.data!);
  }

  Future<List<RcWebhook>> listWebhooks(String projectId) async {
    final response = await _internalDio().get<List<dynamic>>(
      '/me/projects/$projectId/integrations/webhooks',
    );
    return (response.data ?? [])
        .map((e) => RcWebhook.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RcWebhook> createWebhook({
    required String projectId,
    required RcCreateWebhookRequest request,
  }) async {
    final response = await _internalDio().post<Map<String, dynamic>>(
      '/me/projects/$projectId/integrations/webhooks',
      data: request.toJson(),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return RcWebhook.fromJson(response.data!);
  }

  Future<RcWebhook> updateWebhook({
    required String projectId,
    required String webhookId,
    required RcUpdateWebhookRequest request,
  }) async {
    final response = await _internalDio().put<Map<String, dynamic>>(
      '/me/projects/$projectId/integrations/webhooks/$webhookId',
      data: request.toJson(),
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return RcWebhook.fromJson(response.data!);
  }

  Future<void> deleteWebhook({
    required String projectId,
    required String webhookId,
  }) async {
    await _internalDio().delete(
      '/me/projects/$projectId/integrations/webhooks/$webhookId',
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  Future<void> testWebhook({
    required String projectId,
    required String webhookId,
  }) async {
    await _internalDio().post(
      '/me/projects/$projectId/integrations/webhooks/$webhookId/test_webhook',
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
  }

  /// Internal-only endpoints (projects list, subscriber activity, …).
  Dio _internalDio() => Dio(BaseOptions(
        baseUrl: AppConstants.rcApiInternalBaseUrl,
        headers: {
          'X-Requested-With': AppConstants.headerXRequestedWith,
          if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        },
      ));

  RcErrorResponse? parseError(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        return RcErrorResponse.fromJson(data);
      }
    }
    return null;
  }
}
