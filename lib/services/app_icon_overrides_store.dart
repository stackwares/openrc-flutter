import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appIconOverridesProvider =
    StateNotifierProvider<AppIconOverridesNotifier, Map<String, String>>((ref) {
  return AppIconOverridesNotifier();
});

class AppIconOverridesNotifier extends StateNotifier<Map<String, String>> {
  static const _prefsKey = 'app_icon_overrides_v1';

  AppIconOverridesNotifier() : super({}) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
  }

  Future<void> setOverride(String appId, String? url) async {
    final trimmed = url?.trim();
    final next = Map<String, String>.from(state);
    if (trimmed == null || trimmed.isEmpty) {
      next.remove(appId);
    } else {
      next[appId] = trimmed;
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(next));
    }
  }
}

bool isValidHttpIconUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  return uri.scheme == 'http' || uri.scheme == 'https';
}
