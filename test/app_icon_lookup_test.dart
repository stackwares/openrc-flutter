import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revenuecat/services/app_icon_lookup.dart';
import 'package:revenuecat/services/auto_app_icons_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);
  final Map<String, (int, String)> routes;
  final hits = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    hits.add(o.uri.host);
    final r = routes[o.uri.host];
    if (r == null) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    return ResponseBody.fromString(r.$2, r.$1);
  }

  @override
  void close({bool force = false}) {}
}

const _itunes =
    '{"resultCount":1,"results":[{"artworkUrl100":"https://is1.mzstatic.com/a/100x100bb.jpg","artworkUrl512":"https://is1.mzstatic.com/a/512x512bb.jpg"}]}';
const _play =
    '<html><meta property="og:image" content="https://play-lh.googleusercontent.com/abc=s0-br30"></html>';

AppIconLookup _lookup(Map<String, (int, String)> routes) => AppIconLookup(
  dio: Dio()..httpClientAdapter = _RouteAdapter(routes),
  enabled: true,
);

void main() {
  group('parsers', () {
    test('iTunes picks largest artwork and tolerates junk', () {
      expect(
        parseItunesLookupIcon(_itunes),
        'https://is1.mzstatic.com/a/512x512bb.jpg',
      );
      expect(parseItunesLookupIcon('{"resultCount":0,"results":[]}'), isNull);
      expect(parseItunesLookupIcon('not json'), isNull);
    });

    test('Play reads og:image, resizes, and rejects other hosts', () {
      expect(
        parseGooglePlayIcon(_play),
        'https://play-lh.googleusercontent.com/abc=s256-br30',
      );
      expect(
        parseGooglePlayIcon(
          '<meta property="og:image" content="https://evil.com/x.png">',
        ),
        isNull,
      );
      expect(parseGooglePlayIcon(''), isNull);
    });

    test('store hints and bundle validation', () {
      expect(storeHintFor('App Store'), AppIconStoreHint.apple);
      expect(storeHintFor('MAC_APP_STORE'), AppIconStoreHint.apple);
      expect(storeHintFor('Play Store'), AppIconStoreHint.google);
      expect(storeHintFor('Stripe'), AppIconStoreHint.unknown);
      expect(isLookupableBundleId('com.example.app'), isTrue);
      expect(isLookupableBundleId('app'), isFalse);
      expect(isLookupableBundleId('com.x/../y'), isFalse);
    });
  });

  group('lookup', () {
    test('Play hint tries Google first', () async {
      final l = _lookup({
        'play.google.com': (200, _play),
        'itunes.apple.com': (200, _itunes),
      });
      expect(
        await l.find('com.a.b', AppIconStoreHint.google),
        contains('googleusercontent'),
      );
    });

    test('falls back to the other store', () async {
      final l = _lookup({'play.google.com': (404, '')});
      expect(await l.find('com.a.b', AppIconStoreHint.apple), isNull);
      final l2 = _lookup({
        'itunes.apple.com': (200, '{"results":[]}'),
        'play.google.com': (200, _play),
      });
      expect(
        await l2.find('com.a.b', AppIconStoreHint.apple),
        contains('googleusercontent'),
      );
    });

    test('disabled lookup (web) never hits the network', () async {
      final adapter = _RouteAdapter({});
      final l = AppIconLookup(
        dio: Dio()..httpClientAdapter = adapter,
        enabled: false,
      );
      expect(await l.find('com.a.b', AppIconStoreHint.apple), isNull);
      expect(adapter.hits, isEmpty);
    });
  });

  group('AutoAppIconsNotifier', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    const app = AppIconIdentity(
      appId: 'app1',
      bundleId: 'com.a.b',
      hint: AppIconStoreHint.apple,
    );

    test('fetches once, caches, and dedupes concurrent requests', () async {
      final adapter = _RouteAdapter({'itunes.apple.com': (200, _itunes)});
      final n = AutoAppIconsNotifier(
        AppIconLookup(dio: Dio()..httpClientAdapter = adapter, enabled: true),
      );
      await Future.wait([
        n.ensure([app]),
        n.ensure([app]),
      ]);
      expect(n.state['app1'], 'https://is1.mzstatic.com/a/512x512bb.jpg');
      expect(adapter.hits.length, 1);
      await n.ensure([app]);
      expect(adapter.hits.length, 1, reason: 'fresh cache hit');
    });

    test('keeps a previously found icon when a refresh fails', () async {
      var now = DateTime(2026, 1, 1);
      final routes = {'itunes.apple.com': (200, _itunes)};
      final n = AutoAppIconsNotifier(
        AppIconLookup(
          dio: Dio()..httpClientAdapter = _RouteAdapter(routes),
          enabled: true,
        ),
        clock: () => now,
      );
      await n.ensure([app]);
      routes.clear(); // offline
      now = now.add(const Duration(days: 30));
      await n.ensure([app]);
      expect(n.state['app1'], isNotNull);
    });
  });
}
