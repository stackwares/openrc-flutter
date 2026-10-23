import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('PayoutHistoryCache');

/// Paid payouts saved on this device, so each is fetched from RevenueCat once.
///
/// Holds one USD total per payout (no customers or transactions) for a single
/// account, and is cleared on sign out. On the web it saves nothing: shared
/// preferences there are the browser's local storage.
class PayoutHistoryCache {
  const PayoutHistoryCache();

  static const _key = 'payout_history_v1';

  /// Saved totals by payout id, or empty when they belong to another account.
  Future<Map<String, double>> read(String? account) async {
    if (kIsWeb || account == null || account.isEmpty) return const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['account'] != account) return const {};
      final amounts = decoded['amounts'];
      if (amounts is! Map) return const {};
      return {
        for (final e in amounts.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toDouble(),
      };
    } catch (e) {
      _log.fine('Payout cache unreadable, starting fresh: $e');
      return const {};
    }
  }

  Future<void> write(String? account, Map<String, double> amounts) async {
    if (kIsWeb || account == null || account.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({'account': account, 'amounts': amounts}),
      );
    } catch (e) {
      _log.fine('Payout cache write failed: $e');
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
