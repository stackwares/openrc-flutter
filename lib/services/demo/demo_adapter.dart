import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:openrc/services/demo/demo_data.dart';

/// Answers the RevenueCat endpoints the app calls from [DemoData], so a demo
/// build runs without a network or an account.
class DemoAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final query = options.queryParameters;
    final data = DemoData.instance;
    final Object? body;
    if (path.endsWith('/login')) {
      body = {
        'authentication_token': 'demo-token',
        'authentication_token_expiration': DateTime.now()
            .add(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
        'distinct_id': 'demo-distinct-id',
        'email': 'alex@example.com',
      };
    } else if (path.endsWith('/logout')) {
      body = <String, dynamic>{};
    } else if (path.endsWith('/me/projects')) {
      body = [
        for (final p in DemoData.projects)
          {'id': p.id, 'name': p.name, 'icon_url': null},
      ];
    } else if (path.endsWith('/me/transactions')) {
      body = data.transactionsPage(
        limit: int.tryParse('${query['limit']}') ?? 20,
        startFromMs: int.tryParse('${query['start_from']}'),
        startDate: _queryString(query['start_date']),
        endDate: _queryString(query['end_date']),
      );
    } else if (path.endsWith('/charts_v2/overview')) {
      body = data.overview();
    } else if (path.contains('/charts_v2/')) {
      final now = DateTime.now();
      final end = DateTime.tryParse('${query['end_date']}') ?? now;
      final start =
          DateTime.tryParse('${query['start_date']}') ??
          end.subtract(const Duration(days: 29));
      final store = '${query['store'] ?? ''}';
      body = data.chart(
        path.split('/').last,
        start,
        end,
        revenueType: query['revenue_type'] as String?,
        storeShare: store.contains('play')
            ? 0.36
            : store.contains('app_store')
            ? 0.60
            : 1,
      );
    } else if (path.endsWith('/me')) {
      body = {
        'distinct_id': 'demo-distinct-id',
        'email': 'alex@example.com',
        'name': 'Alex Morgan',
        'first_transaction_at': DateTime.now()
            .subtract(const Duration(days: 900))
            .toUtc()
            .toIso8601String(),
        'current_plan': 'Pro',
        'billing_info': {'current_mtr': 612400, 'trailing_30day_mtr': 598000},
        'apps': [
          for (final p in DemoData.projects) {'id': p.id, 'name': p.name},
        ],
      };
    } else {
      return ResponseBody.fromString(
        jsonEncode({'code': 7000, 'message': 'Not in the demo data'}),
        404,
        headers: _json,
      );
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

String? _queryString(Object? value) {
  if (value == null) return null;
  final text = '$value';
  if (text.isEmpty || text == 'null') return null;
  return text;
}
