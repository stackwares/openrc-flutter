import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final secondaryCurrencyProvider =
    StateNotifierProvider<SecondaryCurrencyNotifier, String?>((ref) {
  return SecondaryCurrencyNotifier();
});

class SecondaryCurrencyNotifier extends StateNotifier<String?> {
  static const _prefsKey = 'secondary_currency_iso_v1';

  SecondaryCurrencyNotifier() : super(null) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey)?.trim().toUpperCase();
    if (code != null && code.isNotEmpty) {
      state = code;
    }
  }

  Future<void> setCurrency(String? isoCode) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = isoCode?.trim().toUpperCase();
    if (trimmed == null || trimmed.isEmpty) {
      state = null;
      await prefs.remove(_prefsKey);
      return;
    }
    state = trimmed;
    await prefs.setString(_prefsKey, trimmed);
  }
}

/// ISO 4217 options for the secondary display currency (USD is always primary).
/// [flagEmoji] is a regional-indicator pair (e.g. 🇵🇭) for the main economy using that currency.
const List<SecondaryCurrencyOption> kSecondaryCurrencyOptions = [
  SecondaryCurrencyOption(code: 'EUR', label: 'Euro', flagEmoji: '🇪🇺'),
  SecondaryCurrencyOption(code: 'GBP', label: 'British pound', flagEmoji: '🇬🇧'),
  SecondaryCurrencyOption(code: 'JPY', label: 'Japanese yen', flagEmoji: '🇯🇵'),
  SecondaryCurrencyOption(code: 'CAD', label: 'Canadian dollar', flagEmoji: '🇨🇦'),
  SecondaryCurrencyOption(code: 'AUD', label: 'Australian dollar', flagEmoji: '🇦🇺'),
  SecondaryCurrencyOption(code: 'CHF', label: 'Swiss franc', flagEmoji: '🇨🇭'),
  SecondaryCurrencyOption(code: 'SEK', label: 'Swedish krona', flagEmoji: '🇸🇪'),
  SecondaryCurrencyOption(code: 'NOK', label: 'Norwegian krone', flagEmoji: '🇳🇴'),
  SecondaryCurrencyOption(code: 'DKK', label: 'Danish krone', flagEmoji: '🇩🇰'),
  SecondaryCurrencyOption(code: 'PLN', label: 'Polish złoty', flagEmoji: '🇵🇱'),
  SecondaryCurrencyOption(code: 'INR', label: 'Indian rupee', flagEmoji: '🇮🇳'),
  SecondaryCurrencyOption(code: 'BRL', label: 'Brazilian real', flagEmoji: '🇧🇷'),
  SecondaryCurrencyOption(code: 'MXN', label: 'Mexican peso', flagEmoji: '🇲🇽'),
  SecondaryCurrencyOption(code: 'KRW', label: 'South Korean won', flagEmoji: '🇰🇷'),
  SecondaryCurrencyOption(code: 'SGD', label: 'Singapore dollar', flagEmoji: '🇸🇬'),
  SecondaryCurrencyOption(code: 'HKD', label: 'Hong Kong dollar', flagEmoji: '🇭🇰'),
  SecondaryCurrencyOption(code: 'NZD', label: 'New Zealand dollar', flagEmoji: '🇳🇿'),
  SecondaryCurrencyOption(code: 'PHP', label: 'Philippine peso', flagEmoji: '🇵🇭'),
  SecondaryCurrencyOption(code: 'CNY', label: 'Chinese yuan', flagEmoji: '🇨🇳'),
];

class SecondaryCurrencyOption {
  final String code;
  final String label;
  final String flagEmoji;

  const SecondaryCurrencyOption({
    required this.code,
    required this.label,
    required this.flagEmoji,
  });
}
