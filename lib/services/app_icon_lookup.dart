import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/core/constants/app_constants.dart';

final _log = Logger('AppIconLookup');

/// Which public store listing to try first for an app.
enum AppIconStoreHint { apple, google, unknown }

/// Maps a RevenueCat transaction `store` value to a lookup hint.
AppIconStoreHint storeHintFor(String? store) {
  final s = store?.toLowerCase().replaceAll(RegExp(r'[\s_]'), '') ?? '';
  if (s.contains('appstore') || s.contains('macappstore')) {
    return AppIconStoreHint.apple;
  }
  if (s.contains('playstore') || s.contains('google')) {
    return AppIconStoreHint.google;
  }
  return AppIconStoreHint.unknown;
}

/// Bundle IDs and package names share the reverse-DNS shape.
bool isLookupableBundleId(String? id) {
  if (id == null) return false;
  return RegExp(r'^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$').hasMatch(id.trim()) &&
      id.trim().length <= 255;
}

/// Finds a public app icon URL from the App Store (iTunes lookup API, by
/// bundle ID) or Google Play (store listing `og:image`, by package name).
///
/// Network failures return null; callers fall back to the default avatar.
/// On web both stores block cross-origin requests, so lookups go through
/// [proxyBaseUrl] (the `lookupAppIcon` Cloud Function) instead.
class AppIconLookup {
  AppIconLookup({Dio? dio, bool? enabled, this.proxyBaseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _enabled = enabled ?? (proxyBaseUrl == null && !kIsWeb);

  final Dio _dio;
  final bool _enabled;

  /// When set, [find] asks this HTTPS endpoint instead of the stores.
  /// The web app passes [AppConstants.appIconLookupUrl].
  final String? proxyBaseUrl;

  Future<String?> find(String bundleId, AppIconStoreHint hint) async {
    if (!isLookupableBundleId(bundleId)) return null;
    final id = bundleId.trim();
    final proxy = proxyBaseUrl;
    if (proxy != null) return _fromProxy(proxy, id, hint);
    if (!_enabled) return null;
    final order = hint == AppIconStoreHint.google
        ? [_fromGooglePlay, _fromAppStore]
        : [_fromAppStore, _fromGooglePlay];
    for (final source in order) {
      final url = await source(id);
      if (url != null) return url;
    }
    return null;
  }

  Future<String?> _fromProxy(
    String base,
    String bundleId,
    AppIconStoreHint hint,
  ) async {
    try {
      final res = await _dio.get<String>(
        base,
        queryParameters: {
          'bundleId': bundleId,
          'hint': switch (hint) {
            AppIconStoreHint.apple => 'apple',
            AppIconStoreHint.google => 'google',
            AppIconStoreHint.unknown => 'unknown',
          },
        },
        options: Options(responseType: ResponseType.plain),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.data ?? '');
      if (data is! Map) return null;
      final url = data['url'];
      if (url is String && url.startsWith('https://')) return url;
    } catch (e) {
      _log.fine('Icon proxy failed for $bundleId: $e');
    }
    return null;
  }

  Future<String?> _fromAppStore(String bundleId) async {
    for (final entity in const [null, 'macSoftware']) {
      try {
        final res = await _dio.get<String>(
          'https://itunes.apple.com/lookup',
          queryParameters: {
            'bundleId': bundleId,
            'entity': ?entity,
          },
          // Apple serves JSON as text/javascript, so decode it ourselves.
          options: Options(responseType: ResponseType.plain),
        );
        final url = parseItunesLookupIcon(res.data);
        if (url != null) return url;
      } catch (e) {
        _log.fine('iTunes lookup failed for $bundleId: $e');
        return null;
      }
    }
    return null;
  }

  Future<String?> _fromGooglePlay(String packageName) async {
    try {
      final res = await _dio.get<String>(
        'https://play.google.com/store/apps/details',
        queryParameters: {'id': packageName, 'hl': 'en'},
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode != 200) return null;
      return parseGooglePlayIcon(res.data);
    } catch (e) {
      _log.fine('Play lookup failed for $packageName: $e');
      return null;
    }
  }
}

/// Picks the largest artwork from an iTunes lookup response.
@visibleForTesting
String? parseItunesLookupIcon(dynamic data) {
  if (data is String) {
    try {
      data = jsonDecode(data);
    } on FormatException {
      return null;
    }
  }
  if (data is! Map) return null;
  final results = data['results'];
  if (results is! List || results.isEmpty) return null;
  final first = results.first;
  if (first is! Map) return null;
  for (final key in const ['artworkUrl512', 'artworkUrl100', 'artworkUrl60']) {
    final v = first[key];
    if (v is String && v.startsWith('https://')) return v;
  }
  return null;
}

/// Reads the app icon from a Google Play listing page.
@visibleForTesting
String? parseGooglePlayIcon(String? html) {
  if (html == null || html.isEmpty) return null;
  final patterns = [
    RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"'),
    RegExp(r'<meta[^>]+content="([^"]+)"[^>]+property="og:image"'),
    RegExp(r'<img[^>]+itemprop="image"[^>]+src="([^"]+)"'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(html);
    final url = m?.group(1)?.replaceAll('&amp;', '&');
    if (url != null &&
        url.startsWith('https://') &&
        Uri.tryParse(url)?.host.endsWith('googleusercontent.com') == true) {
      // `=s0` is the full-size original; ask for a list-friendly size.
      return url.replaceFirst(RegExp(r'=s\d+(?=(-|$))'), '=s256');
    }
  }
  return null;
}
