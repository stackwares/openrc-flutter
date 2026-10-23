import 'package:easy_localization/easy_localization.dart';
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
///
/// USD is first; remaining codes are alphabetical. Rates come from the exchange API
/// (lowercase keys); unsupported codes fall back to USD formatting in the UI.
const List<DisplayCurrencyOption> kDisplayCurrencyOptions = [
  DisplayCurrencyOption(code: 'USD', label: 'US dollar', flagEmoji: '🇺🇸'),
  DisplayCurrencyOption(code: 'AED', label: 'UAE dirham', flagEmoji: '🇦🇪'),
  DisplayCurrencyOption(code: 'ALL', label: 'Albanian lek', flagEmoji: '🇦🇱'),
  DisplayCurrencyOption(code: 'AMD', label: 'Armenian dram', flagEmoji: '🇦🇲'),
  DisplayCurrencyOption(code: 'ARS', label: 'Argentine peso', flagEmoji: '🇦🇷'),
  DisplayCurrencyOption(code: 'AUD', label: 'Australian dollar', flagEmoji: '🇦🇺'),
  DisplayCurrencyOption(code: 'AZN', label: 'Azerbaijani manat', flagEmoji: '🇦🇿'),
  DisplayCurrencyOption(code: 'BAM', label: 'Bosnia mark', flagEmoji: '🇧🇦'),
  DisplayCurrencyOption(code: 'BDT', label: 'Bangladeshi taka', flagEmoji: '🇧🇩'),
  DisplayCurrencyOption(code: 'BGN', label: 'Bulgarian lev', flagEmoji: '🇧🇬'),
  DisplayCurrencyOption(code: 'BHD', label: 'Bahraini dinar', flagEmoji: '🇧🇭'),
  DisplayCurrencyOption(code: 'BOB', label: 'Bolivian boliviano', flagEmoji: '🇧🇴'),
  DisplayCurrencyOption(code: 'BRL', label: 'Brazilian real', flagEmoji: '🇧🇷'),
  DisplayCurrencyOption(code: 'BYN', label: 'Belarusian ruble', flagEmoji: '🇧🇾'),
  DisplayCurrencyOption(code: 'BZD', label: 'Belize dollar', flagEmoji: '🇧🇿'),
  DisplayCurrencyOption(code: 'CAD', label: 'Canadian dollar', flagEmoji: '🇨🇦'),
  DisplayCurrencyOption(code: 'CHF', label: 'Swiss franc', flagEmoji: '🇨🇭'),
  DisplayCurrencyOption(code: 'CLP', label: 'Chilean peso', flagEmoji: '🇨🇱'),
  DisplayCurrencyOption(code: 'CNY', label: 'Chinese yuan', flagEmoji: '🇨🇳'),
  DisplayCurrencyOption(code: 'COP', label: 'Colombian peso', flagEmoji: '🇨🇴'),
  DisplayCurrencyOption(code: 'CRC', label: 'Costa Rican colón', flagEmoji: '🇨🇷'),
  DisplayCurrencyOption(code: 'CZK', label: 'Czech koruna', flagEmoji: '🇨🇿'),
  DisplayCurrencyOption(code: 'DKK', label: 'Danish krone', flagEmoji: '🇩🇰'),
  DisplayCurrencyOption(code: 'DOP', label: 'Dominican peso', flagEmoji: '🇩🇴'),
  DisplayCurrencyOption(code: 'DZD', label: 'Algerian dinar', flagEmoji: '🇩🇿'),
  DisplayCurrencyOption(code: 'EGP', label: 'Egyptian pound', flagEmoji: '🇪🇬'),
  DisplayCurrencyOption(code: 'ETB', label: 'Ethiopian birr', flagEmoji: '🇪🇹'),
  DisplayCurrencyOption(code: 'EUR', label: 'Euro', flagEmoji: '🇪🇺'),
  DisplayCurrencyOption(code: 'FJD', label: 'Fijian dollar', flagEmoji: '🇫🇯'),
  DisplayCurrencyOption(code: 'GBP', label: 'British pound', flagEmoji: '🇬🇧'),
  DisplayCurrencyOption(code: 'GEL', label: 'Georgian lari', flagEmoji: '🇬🇪'),
  DisplayCurrencyOption(code: 'GHS', label: 'Ghanaian cedi', flagEmoji: '🇬🇭'),
  DisplayCurrencyOption(code: 'GTQ', label: 'Guatemalan quetzal', flagEmoji: '🇬🇹'),
  DisplayCurrencyOption(code: 'HKD', label: 'Hong Kong dollar', flagEmoji: '🇭🇰'),
  DisplayCurrencyOption(code: 'HNL', label: 'Honduran lempira', flagEmoji: '🇭🇳'),
  DisplayCurrencyOption(code: 'HUF', label: 'Hungarian forint', flagEmoji: '🇭🇺'),
  DisplayCurrencyOption(code: 'IDR', label: 'Indonesian rupiah', flagEmoji: '🇮🇩'),
  DisplayCurrencyOption(code: 'ILS', label: 'Israeli new shekel', flagEmoji: '🇮🇱'),
  DisplayCurrencyOption(code: 'INR', label: 'Indian rupee', flagEmoji: '🇮🇳'),
  DisplayCurrencyOption(code: 'ISK', label: 'Icelandic króna', flagEmoji: '🇮🇸'),
  DisplayCurrencyOption(code: 'JMD', label: 'Jamaican dollar', flagEmoji: '🇯🇲'),
  DisplayCurrencyOption(code: 'JOD', label: 'Jordanian dinar', flagEmoji: '🇯🇴'),
  DisplayCurrencyOption(code: 'JPY', label: 'Japanese yen', flagEmoji: '🇯🇵'),
  DisplayCurrencyOption(code: 'KES', label: 'Kenyan shilling', flagEmoji: '🇰🇪'),
  DisplayCurrencyOption(code: 'KGS', label: 'Kyrgyzstani som', flagEmoji: '🇰🇬'),
  DisplayCurrencyOption(code: 'KHR', label: 'Cambodian riel', flagEmoji: '🇰🇭'),
  DisplayCurrencyOption(code: 'KRW', label: 'South Korean won', flagEmoji: '🇰🇷'),
  DisplayCurrencyOption(code: 'KWD', label: 'Kuwaiti dinar', flagEmoji: '🇰🇼'),
  DisplayCurrencyOption(code: 'KZT', label: 'Kazakhstani tenge', flagEmoji: '🇰🇿'),
  DisplayCurrencyOption(code: 'LAK', label: 'Lao kip', flagEmoji: '🇱🇦'),
  DisplayCurrencyOption(code: 'LBP', label: 'Lebanese pound', flagEmoji: '🇱🇧'),
  DisplayCurrencyOption(code: 'LKR', label: 'Sri Lankan rupee', flagEmoji: '🇱🇰'),
  DisplayCurrencyOption(code: 'MAD', label: 'Moroccan dirham', flagEmoji: '🇲🇦'),
  DisplayCurrencyOption(code: 'MDL', label: 'Moldovan leu', flagEmoji: '🇲🇩'),
  DisplayCurrencyOption(code: 'MKD', label: 'Macedonian denar', flagEmoji: '🇲🇰'),
  DisplayCurrencyOption(code: 'MMK', label: 'Myanmar kyat', flagEmoji: '🇲🇲'),
  DisplayCurrencyOption(code: 'MNT', label: 'Mongolian tögrög', flagEmoji: '🇲🇳'),
  DisplayCurrencyOption(code: 'MUR', label: 'Mauritian rupee', flagEmoji: '🇲🇺'),
  DisplayCurrencyOption(code: 'MXN', label: 'Mexican peso', flagEmoji: '🇲🇽'),
  DisplayCurrencyOption(code: 'MYR', label: 'Malaysian ringgit', flagEmoji: '🇲🇾'),
  DisplayCurrencyOption(code: 'NGN', label: 'Nigerian naira', flagEmoji: '🇳🇬'),
  DisplayCurrencyOption(code: 'NIO', label: 'Nicaraguan córdoba', flagEmoji: '🇳🇮'),
  DisplayCurrencyOption(code: 'NOK', label: 'Norwegian krone', flagEmoji: '🇳🇴'),
  DisplayCurrencyOption(code: 'NPR', label: 'Nepalese rupee', flagEmoji: '🇳🇵'),
  DisplayCurrencyOption(code: 'NZD', label: 'New Zealand dollar', flagEmoji: '🇳🇿'),
  DisplayCurrencyOption(code: 'OMR', label: 'Omani rial', flagEmoji: '🇴🇲'),
  DisplayCurrencyOption(code: 'PAB', label: 'Panamanian balboa', flagEmoji: '🇵🇦'),
  DisplayCurrencyOption(code: 'PEN', label: 'Peruvian sol', flagEmoji: '🇵🇪'),
  DisplayCurrencyOption(code: 'PGK', label: 'Papua New Guinean kina', flagEmoji: '🇵🇬'),
  DisplayCurrencyOption(code: 'PHP', label: 'Philippine peso', flagEmoji: '🇵🇭'),
  DisplayCurrencyOption(code: 'PKR', label: 'Pakistani rupee', flagEmoji: '🇵🇰'),
  DisplayCurrencyOption(code: 'PLN', label: 'Polish złoty', flagEmoji: '🇵🇱'),
  DisplayCurrencyOption(code: 'PYG', label: 'Paraguayan guaraní', flagEmoji: '🇵🇾'),
  DisplayCurrencyOption(code: 'QAR', label: 'Qatari riyal', flagEmoji: '🇶🇦'),
  DisplayCurrencyOption(code: 'RON', label: 'Romanian leu', flagEmoji: '🇷🇴'),
  DisplayCurrencyOption(code: 'RSD', label: 'Serbian dinar', flagEmoji: '🇷🇸'),
  DisplayCurrencyOption(code: 'RUB', label: 'Russian ruble', flagEmoji: '🇷🇺'),
  DisplayCurrencyOption(code: 'RWF', label: 'Rwandan franc', flagEmoji: '🇷🇼'),
  DisplayCurrencyOption(code: 'SAR', label: 'Saudi riyal', flagEmoji: '🇸🇦'),
  DisplayCurrencyOption(code: 'SEK', label: 'Swedish krona', flagEmoji: '🇸🇪'),
  DisplayCurrencyOption(code: 'SGD', label: 'Singapore dollar', flagEmoji: '🇸🇬'),
  DisplayCurrencyOption(code: 'THB', label: 'Thai baht', flagEmoji: '🇹🇭'),
  DisplayCurrencyOption(code: 'TJS', label: 'Tajikistani somoni', flagEmoji: '🇹🇯'),
  DisplayCurrencyOption(code: 'TRY', label: 'Turkish lira', flagEmoji: '🇹🇷'),
  DisplayCurrencyOption(code: 'TTD', label: 'Trinidad dollar', flagEmoji: '🇹🇹'),
  DisplayCurrencyOption(code: 'TWD', label: 'New Taiwan dollar', flagEmoji: '🇹🇼'),
  DisplayCurrencyOption(code: 'TZS', label: 'Tanzanian shilling', flagEmoji: '🇹🇿'),
  DisplayCurrencyOption(code: 'UAH', label: 'Ukrainian hryvnia', flagEmoji: '🇺🇦'),
  DisplayCurrencyOption(code: 'UGX', label: 'Ugandan shilling', flagEmoji: '🇺🇬'),
  DisplayCurrencyOption(code: 'UYU', label: 'Uruguayan peso', flagEmoji: '🇺🇾'),
  DisplayCurrencyOption(code: 'UZS', label: 'Uzbekistani som', flagEmoji: '🇺🇿'),
  DisplayCurrencyOption(code: 'VND', label: 'Vietnamese dong', flagEmoji: '🇻🇳'),
  DisplayCurrencyOption(code: 'VUV', label: 'Vanuatu vatu', flagEmoji: '🇻🇺'),
  DisplayCurrencyOption(code: 'XAF', label: 'Central African CFA franc', flagEmoji: '🇨🇲'),
  DisplayCurrencyOption(code: 'XCD', label: 'East Caribbean dollar', flagEmoji: '🇦🇬'),
  DisplayCurrencyOption(code: 'XOF', label: 'West African CFA franc', flagEmoji: '🇸🇳'),
  DisplayCurrencyOption(code: 'XPF', label: 'CFP franc', flagEmoji: '🇵🇫'),
  DisplayCurrencyOption(code: 'ZAR', label: 'South African rand', flagEmoji: '🇿🇦'),
  DisplayCurrencyOption(code: 'ZMW', label: 'Zambian kwacha', flagEmoji: '🇿🇲'),
];

class DisplayCurrencyOption {
  final String code;
  final String englishLabel;
  final String flagEmoji;

  const DisplayCurrencyOption({
    required this.code,
    required String label,
    required this.flagEmoji,
  }) : englishLabel = label;

  /// Currency name in the app's language (`currencies.<CODE>`).
  String get label {
    final key = 'currencies.$code';
    final localized = key.tr();
    return localized == key ? englishLabel : localized;
  }
}

/// Resolves a [kDisplayCurrencyOptions] entry for [isoCode], or null if unknown.
DisplayCurrencyOption? lookupDisplayCurrencyOption(String isoCode) {
  final c = isoCode.trim().toUpperCase();
  for (final o in kDisplayCurrencyOptions) {
    if (o.code == c) return o;
  }
  return null;
}
