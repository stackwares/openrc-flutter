import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final displayCurrencyProvider =
    StateNotifierProvider<DisplayCurrencyNotifier, String>((ref) {
  return DisplayCurrencyNotifier();
});

class DisplayCurrencyNotifier extends StateNotifier<String> {
  static const _prefsKey = 'display_currency_iso_v2';
  static const _legacySecondaryKey = 'secondary_currency_iso_v1';

  DisplayCurrencyNotifier() : super('USD') {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString(_prefsKey)?.trim().toUpperCase();

    if (code == null || code.isEmpty) {
      final legacy = prefs.getString(_legacySecondaryKey)?.trim().toUpperCase();
      if (legacy != null && legacy.isNotEmpty) {
        code = legacy;
        await prefs.setString(_prefsKey, legacy);
      } else {
        code = 'USD';
      }
    }

    if (code.isEmpty) code = 'USD';
    state = code;
    await prefs.remove(_legacySecondaryKey);
  }

  /// [isoCode] is normalized to uppercase (e.g. EUR, USD).
  Future<void> setCurrency(String isoCode) async {
    final trimmed = isoCode.trim().toUpperCase();
    if (trimmed.isEmpty) return;
    state = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, trimmed);
  }
}

/// [flagEmoji] is a regional-indicator pair for the main economy using that currency.
const List<DisplayCurrencyOption> kDisplayCurrencyOptions = [
  DisplayCurrencyOption(code: 'USD', label: 'US dollar', flagEmoji: '🇺🇸'),
  DisplayCurrencyOption(code: 'EUR', label: 'Euro', flagEmoji: '🇪🇺'),
  DisplayCurrencyOption(code: 'GBP', label: 'British pound', flagEmoji: '🇬🇧'),
  DisplayCurrencyOption(code: 'JPY', label: 'Japanese yen', flagEmoji: '🇯🇵'),
  DisplayCurrencyOption(code: 'CAD', label: 'Canadian dollar', flagEmoji: '🇨🇦'),
  DisplayCurrencyOption(code: 'AUD', label: 'Australian dollar', flagEmoji: '🇦🇺'),
  DisplayCurrencyOption(code: 'CHF', label: 'Swiss franc', flagEmoji: '🇨🇭'),
  DisplayCurrencyOption(code: 'SEK', label: 'Swedish krona', flagEmoji: '🇸🇪'),
  DisplayCurrencyOption(code: 'NOK', label: 'Norwegian krone', flagEmoji: '🇳🇴'),
  DisplayCurrencyOption(code: 'DKK', label: 'Danish krone', flagEmoji: '🇩🇰'),
  DisplayCurrencyOption(code: 'PLN', label: 'Polish złoty', flagEmoji: '🇵🇱'),
  DisplayCurrencyOption(code: 'INR', label: 'Indian rupee', flagEmoji: '🇮🇳'),
  DisplayCurrencyOption(code: 'BRL', label: 'Brazilian real', flagEmoji: '🇧🇷'),
  DisplayCurrencyOption(code: 'MXN', label: 'Mexican peso', flagEmoji: '🇲🇽'),
  DisplayCurrencyOption(code: 'KRW', label: 'South Korean won', flagEmoji: '🇰🇷'),
  DisplayCurrencyOption(code: 'SGD', label: 'Singapore dollar', flagEmoji: '🇸🇬'),
  DisplayCurrencyOption(code: 'HKD', label: 'Hong Kong dollar', flagEmoji: '🇭🇰'),
  DisplayCurrencyOption(code: 'NZD', label: 'New Zealand dollar', flagEmoji: '🇳🇿'),
  DisplayCurrencyOption(code: 'PHP', label: 'Philippine peso', flagEmoji: '🇵🇭'),
  DisplayCurrencyOption(code: 'CNY', label: 'Chinese yuan', flagEmoji: '🇨🇳'),
];

class DisplayCurrencyOption {
  final String code;
  final String label;
  final String flagEmoji;

  const DisplayCurrencyOption({
    required this.code,
    required this.label,
    required this.flagEmoji,
  });
}
