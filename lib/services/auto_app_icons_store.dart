import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:revenuecat/core/constants/app_constants.dart';
import 'package:revenuecat/models/rc_transaction.dart';
import 'package:revenuecat/services/app_icon_lookup.dart';
import 'package:revenuecat/services/app_icon_overrides_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('AutoAppIcons');

/// One RevenueCat app (per-store app inside a project) we can look up.
class AppIconIdentity {
  const AppIconIdentity({
    required this.appId,
    required this.bundleId,
    required this.hint,
  });

  final String appId;
  final String bundleId;
  final AppIconStoreHint hint;

  static AppIconIdentity? fromTransaction(RcTransaction tx) {
    final appId = tx.app?.id?.trim();
    final bundleId = tx.app?.bundleId?.trim();
    if (appId == null || appId.isEmpty || !isLookupableBundleId(bundleId)) {
      return null;
    }
    return AppIconIdentity(
      appId: appId,
      bundleId: bundleId!,
      hint: storeHintFor(tx.store),
    );
  }
}

class _CacheEntry {
  const _CacheEntry(this.url, this.fetchedAtMs);
  final String? url;
  final int fetchedAtMs;

  Map<String, dynamic> toJson() => {'u': url, 't': fetchedAtMs};

  static _CacheEntry? fromJson(Object? v) {
    if (v is! Map) return null;
    final t = v['t'];
    final u = v['u'];
    if (t is! int) return null;
    return _CacheEntry(u is String && u.isNotEmpty ? u : null, t);
  }
}

final appIconLookupProvider = Provider<AppIconLookup>((ref) {
  return AppIconLookup(
    proxyBaseUrl: kIsWeb ? AppConstants.appIconLookupUrl : null,
  );
});

/// Icons found automatically from the App Store / Google Play, keyed by
/// RevenueCat app id. Results (including misses) are cached on device.
final autoAppIconsProvider =
    StateNotifierProvider<AutoAppIconsNotifier, Map<String, String>>((ref) {
  return AutoAppIconsNotifier(ref.read(appIconLookupProvider));
});

/// What the UI should show: a manual override wins, then the auto icon.
final resolvedAppIconsProvider = Provider<Map<String, String>>((ref) {
  final auto = ref.watch(autoAppIconsProvider);
  final overrides = ref.watch(appIconOverridesProvider);
  if (overrides.isEmpty) return auto;
  return {...auto, ...overrides};
});

class AutoAppIconsNotifier extends StateNotifier<Map<String, String>> {
  AutoAppIconsNotifier(this._lookup, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(const {}) {
    _hydrated = _hydrate();
  }

  static const _prefsKey = 'auto_app_icons_v1';
  static const hitTtl = Duration(days: 14);
  static const missTtl = Duration(days: 1);
  static const _maxConcurrent = 3;

  final AppIconLookup _lookup;
  final DateTime Function() _clock;
  late final Future<void> _hydrated;

  /// Cache key is bundle id + store, so a renamed/republished app refetches.
  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<void>> _inFlight = {};

  String _key(AppIconIdentity a) => '${a.hint.name}|${a.bundleId}';

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        final e = _CacheEntry.fromJson(v);
        if (k is String && e != null) _cache[k] = e;
      });
    } catch (e) {
      _log.fine('Icon cache unreadable, starting fresh: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_cache.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (e) {
      _log.fine('Icon cache write failed: $e');
    }
  }

  bool _isFresh(_CacheEntry e) {
    final age = _clock().millisecondsSinceEpoch - e.fetchedAtMs;
    return age < (e.url != null ? hitTtl : missTtl).inMilliseconds;
  }

  /// Shows cached icons immediately and looks up anything missing or stale.
  Future<void> ensure(Iterable<AppIconIdentity> apps) async {
    await _hydrated;
    final unique = <String, AppIconIdentity>{};
    for (final a in apps) {
      unique.putIfAbsent(a.appId, () => a);
    }
    final next = Map<String, String>.from(state);
    final toFetch = <AppIconIdentity>[];
    for (final a in unique.values) {
      final cached = _cache[_key(a)];
      if (cached?.url != null) next[a.appId] = cached!.url!;
      if (cached == null || !_isFresh(cached)) toFetch.add(a);
    }
    _publish(next);

    for (var i = 0; i < toFetch.length; i += _maxConcurrent) {
      final chunk = toFetch.skip(i).take(_maxConcurrent);
      await Future.wait(chunk.map(_fetchOnce));
    }
  }

  Future<void> _fetchOnce(AppIconIdentity a) {
    final key = _key(a);
    return _inFlight[key] ??= _fetch(a, key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<void> _fetch(AppIconIdentity a, String key) async {
    String? url;
    try {
      url = await _lookup.find(a.bundleId, a.hint);
    } catch (e) {
      _log.fine('Icon lookup error for ${a.bundleId}: $e');
    }
    final previous = _cache[key];
    // Keep a previously found icon if a refresh misses (e.g. offline).
    if (url == null && previous?.url != null) {
      url = previous!.url;
    }
    _cache[key] = _CacheEntry(url, _clock().millisecondsSinceEpoch);
    unawaited(_persist());
    if (!mounted) return;
    final next = Map<String, String>.from(state);
    if (url != null) {
      next[a.appId] = url;
    } else {
      next.remove(a.appId);
    }
    _publish(next);
  }

  void _publish(Map<String, String> next) {
    if (!mounted) return;
    if (next.length == state.length &&
        next.entries.every((e) => state[e.key] == e.value)) {
      return;
    }
    state = next;
  }
}
