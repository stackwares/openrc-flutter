import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:revenuecat/services/talker_service.dart';
import 'package:talker/talker.dart';

enum RcEndpoint {
  login,
  logout,
  me,
  projects,
  overview,
  transactions,
}

final rcApiServiceProvider = Provider<RcApiService>((ref) {
  final talker = ref.read(talkerProvider);
  return RcApiService(talker);
});

class RcApiService {
  final Talker _talker;
  late final Dio _dio;
  String? _authToken;

  RcApiService(this._talker) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.rcApiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'X-Requested-With': AppConstants.headerXRequestedWith,
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => _talker.info('[Dio] $obj'),
    ));
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
    RcTransactionsRequest request,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/me/transactions',
      queryParameters: request.toQueryParameters(),
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
