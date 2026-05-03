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
        onResponse: (response, handler) {
          _rcApiLogSuccess(response);
          handler.next(response);
        },
        onError: (e, handler) {
          _rcApiLogError(e);
          handler.next(e);
        },
      ));
    }
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
