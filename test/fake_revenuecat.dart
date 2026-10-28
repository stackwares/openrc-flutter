import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:openrc/services/rc_api_service.dart';

/// RevenueCat's project and webhook endpoints, in memory. Like the real API
/// it masks authorization headers when webhooks are read back.
class FakeRevenueCat implements HttpClientAdapter {
  FakeRevenueCat({List<String> projects = const ['p1', 'p2']})
    : webhooks = {for (final id in projects) id: <Map<String, dynamic>>[]};

  /// Webhooks by project id, as stored (headers unmasked).
  final Map<String, List<Map<String, dynamic>>> webhooks;

  /// Icon URLs by project id, as `/me/projects` reports them.
  final icons = <String, String>{};

  /// "METHOD path" for every request.
  final requests = <String>[];

  /// Every request fails as if the network were down.
  bool offline = false;

  /// Creating a webhook fails with this message, as for a plan without
  /// webhooks.
  String? refuseCreate;

  /// How the notifier answers RevenueCat's test event.
  int testResponseCode = 200;

  int _nextId = 1;

  RcApiService api() => RcApiService(
    dio: Dio()..httpClientAdapter = this,
    internalDio: Dio()..httpClientAdapter = this,
  );

  static final _webhookPath = RegExp(
    r'^/me/projects/([^/]+)/integrations/webhooks(?:/([^/]+))?(/test_webhook)?$',
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method;
    final path = options.path;
    requests.add('$method $path');
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (method == 'GET' && path == '/me/projects') {
      return _json(200, [
        for (final id in webhooks.keys)
          {
            'id': id,
            'name': 'Project $id',
            'icon_url': ?icons[id],
          },
      ]);
    }
    final match = _webhookPath.firstMatch(path);
    final hooks = match == null ? null : webhooks[match[1]];
    if (match == null || hooks == null) {
      return _json(404, {'code': 7000, 'message': 'Not found'});
    }
    final id = match[2];
    final index = hooks.indexWhere((w) => w['id'] == id);
    switch ((method, id, match[3])) {
      case ('GET', null, _):
        return _json(200, hooks.map(_masked).toList());
      case ('POST', null, _):
        if (refuseCreate != null) {
          return _json(403, {'code': 7600, 'message': refuseCreate});
        }
        final input = options.data as Map<String, dynamic>;
        // RevenueCat allows one webhook per URL in a project.
        if (hooks.any((w) => w['url'] == input['url'])) {
          return _json(400, {
            'code': 7225,
            'message':
                'There is another webhook integration the same url in this project',
          });
        }
        final hook = {...input, 'id': 'wh${_nextId++}', 'project_id': match[1]};
        hooks.add(hook);
        return _json(201, _masked(hook));
      case ('POST', _, '/test_webhook') when index >= 0:
        return _json(200, {
          'successful_response': testResponseCode == 200,
          'response_code': testResponseCode,
        });
      case ('PUT', _, null) when index >= 0:
        hooks[index] = {
          ...hooks[index],
          ...options.data as Map<String, dynamic>,
        };
        return _json(200, {});
      case ('DELETE', _, null) when index >= 0:
        hooks.removeAt(index);
        return _json(200, {});
      default:
        return _json(404, {'code': 7000, 'message': 'Not found'});
    }
  }

  /// A webhook another device or service added.
  void addForeign(
    String projectId, {
    required String name,
    required String url,
  }) {
    webhooks[projectId]!.add({
      'id': 'wh${_nextId++}',
      'name': name,
      'url': url,
      'authorization_header': 'Bearer someone-else',
    });
  }

  static Map<String, dynamic> _masked(Map<String, dynamic> hook) => {
    ...hook,
    'authorization_header': hook['authorization_header'] == null
        ? null
        : 'Bea••••••••',
  };

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
