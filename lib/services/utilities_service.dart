import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final utilitiesServiceProvider = Provider<UtilitiesService>((ref) {
  return UtilitiesService();
});

final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => _defaultThemeMode(),
);
final colorSchemeProvider = StateProvider<FlexScheme>(
  (ref) => _defaultColorScheme,
);

ThemeMode _defaultThemeMode() {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return ThemeMode.system;
  }
  return ThemeMode.dark;
}

final FlexScheme _defaultColorScheme = _resolveDefaultColorScheme();

FlexScheme _resolveDefaultColorScheme() {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    for (final scheme in FlexScheme.values) {
      if (scheme.name == 'greyLaw') {
        return scheme;
      }
    }
    return FlexScheme.indigo;
  }

  for (final scheme in FlexScheme.values) {
    if (scheme.name == 'blackWhite') {
      return scheme;
    }
  }
  for (final scheme in FlexScheme.values) {
    if (scheme.name == 'greyLaw') {
      return scheme;
    }
  }
  return FlexScheme.indigo;
}

class UtilitiesService {
  static const String _themeModeKey = 'theme_mode';
  static const String _colorSchemeKey = 'color_scheme';

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultMode = _defaultThemeMode();
    final index = prefs.getInt(_themeModeKey) ?? defaultMode.index;
    if (index < 0 || index >= ThemeMode.values.length) {
      return defaultMode;
    }
    final mode = ThemeMode.values[index];
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        mode == ThemeMode.dark) {
      return ThemeMode.system;
    }
    return mode;
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<FlexScheme> loadColorScheme() async {
    final prefs = await SharedPreferences.getInstance();
    final schemeName = prefs.getString(_colorSchemeKey);
    if (schemeName == null || schemeName.isEmpty) {
      return _defaultColorScheme;
    }
    final scheme = FlexScheme.values.firstWhere(
      (scheme) => scheme.name == schemeName,
      orElse: () => _defaultColorScheme,
    );
    if (defaultTargetPlatform == TargetPlatform.macOS &&
        scheme.name == 'blackWhite') {
      return _defaultColorScheme;
    }
    return scheme;
  }

  Future<void> saveColorScheme(FlexScheme scheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorSchemeKey, scheme.name);
  }

  static void hapticLight() => HapticFeedback.lightImpact();
  static void hapticMedium() => HapticFeedback.mediumImpact();
  static void hapticHeavy() => HapticFeedback.heavyImpact();
  static void hapticSelection() => HapticFeedback.selectionClick();

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
