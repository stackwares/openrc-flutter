import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommissionSettings {
  final bool adjustmentEnabled;
  final double appleCommissionPercent;
  final double googleCommissionPercent;

  const CommissionSettings({
    this.adjustmentEnabled = false,
    this.appleCommissionPercent = 15,
    this.googleCommissionPercent = 15,
  });

  CommissionSettings copyWith({
    bool? adjustmentEnabled,
    double? appleCommissionPercent,
    double? googleCommissionPercent,
  }) {
    return CommissionSettings(
      adjustmentEnabled: adjustmentEnabled ?? this.adjustmentEnabled,
      appleCommissionPercent:
          appleCommissionPercent ?? this.appleCommissionPercent,
      googleCommissionPercent:
          googleCommissionPercent ?? this.googleCommissionPercent,
    );
  }
}

final commissionSettingsProvider =
    StateNotifierProvider<CommissionSettingsNotifier, CommissionSettings>((ref) {
  return CommissionSettingsNotifier();
});

class CommissionSettingsNotifier extends StateNotifier<CommissionSettings> {
  static const _keyEnabled = 'store_commission_enabled_v1';
  static const _keyApple = 'store_commission_apple_pct_v1';
  static const _keyGoogle = 'store_commission_google_pct_v1';

  CommissionSettingsNotifier() : super(const CommissionSettings()) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final apple = _readPct(prefs, _keyApple, 15);
    final google = _readPct(prefs, _keyGoogle, 15);
    state = CommissionSettings(
      adjustmentEnabled: enabled,
      appleCommissionPercent: apple,
      googleCommissionPercent: google,
    );
  }

  double _readPct(SharedPreferences prefs, String key, double fallback) {
    final s = prefs.getString(key);
    if (s == null || s.isEmpty) return fallback;
    final v = double.tryParse(s);
    if (v == null) return fallback;
    return v.clamp(0.0, 100.0);
  }

  Future<void> setAdjustmentEnabled(bool value) async {
    state = state.copyWith(adjustmentEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  Future<void> setAppleCommissionPercent(double value) async {
    final v = value.clamp(0.0, 100.0);
    state = state.copyWith(appleCommissionPercent: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApple, v.toString());
  }

  Future<void> setGoogleCommissionPercent(double value) async {
    final v = value.clamp(0.0, 100.0);
    state = state.copyWith(googleCommissionPercent: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGoogle, v.toString());
  }
}
