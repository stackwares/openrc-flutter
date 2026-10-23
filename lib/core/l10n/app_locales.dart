import 'package:flutter/widgets.dart';

/// Languages OpenRC ships in. `assets/translations/en.json` is the source;
/// every other file must have exactly its keys (see the key-parity test).
abstract final class AppLocales {
  static const String path = 'assets/translations';

  static const Locale fallback = Locale('en');

  static const List<Locale> supported = [
    Locale('en'),
    Locale('ar'),
    Locale('de'),
    Locale('es', 'ES'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('ja'),
    Locale('pt', 'BR'),
    Locale('ru'),
    Locale('zh', 'CN'),
  ];

  /// Each language's name in itself, for the language picker.
  static const Map<String, String> nativeNames = {
    'en': 'English',
    'ar': 'العربية',
    'de': 'Deutsch',
    'es-ES': 'Español',
    'fr': 'Français',
    'hi': 'हिन्दी',
    'id': 'Bahasa Indonesia',
    'ja': '日本語',
    'pt-BR': 'Português (Brasil)',
    'ru': 'Русский',
    'zh-CN': '简体中文',
  };

  /// The supported locale for a file stem such as `pt-BR`, or null.
  static Locale? fromStem(String stem) {
    for (final locale in supported) {
      if (fileStem(locale) == stem) return locale;
    }
    return null;
  }

  /// File name stem for [locale], e.g. `pt-BR`.
  static String fileStem(Locale locale) => locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}-${locale.countryCode}';
}
