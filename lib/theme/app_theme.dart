import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

const _subThemes = FlexSubThemesData(
  blendOnLevel: 10,
  blendOnColors: false,
  useMaterial3Typography: true,
  useM2StyleDividerInM3: true,
  alignedDropdown: true,
  useInputDecoratorThemeInDialogs: true,
  fabUseShape: true,
  interactionEffects: true,
  bottomNavigationBarElevation: 0,
  inputDecoratorBorderType: FlexInputBorderType.outline,
  inputDecoratorRadius: 12.0,
  chipRadius: 20.0,
  cardRadius: 16.0,
  dialogRadius: 20.0,
  bottomSheetRadius: 28.0,
  filledButtonRadius: 40.0,
  elevatedButtonRadius: 40.0,
  outlinedButtonRadius: 40.0,
  textButtonRadius: 40.0,
);

abstract class AppTheme {
  /// AppBar titles: plain [Text] in each screen — no per-title [TextStyle];
  /// uses Flex + Material 3 default [AppBarTheme] / framework fallbacks.
  static ThemeData light(FlexScheme scheme) {
    return _finish(
      FlexThemeData.light(
        scheme: scheme,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
        subThemesData: _subThemes,
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
      ),
    );
  }

  static ThemeData dark(FlexScheme scheme) {
    return _finish(
      FlexThemeData.dark(
        scheme: scheme,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 13,
        subThemesData: _subThemes.copyWith(blendOnLevel: 20),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
      ),
    );
  }

  static ThemeData _finish(ThemeData base) {
    final body = base.textTheme.apply(fontFamily: 'SanFrancisco');
    final primary = base.primaryTextTheme.apply(fontFamily: 'SanFrancisco');
    return base.copyWith(
      textTheme: _nunitoHeadlines(body),
      primaryTextTheme: _nunitoHeadlines(primary),
    );
  }

  /// Bones follow the app theme, not the device brightness.
  static SkeletonizerConfigData skeletonizer(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final base = dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerHighest;
    final highlight = Color.alphaBlend(
      scheme.onSurface.withValues(alpha: dark ? 0.16 : 0.08),
      dark ? scheme.surfaceContainerHighest : scheme.surface,
    );
    return SkeletonizerConfigData(
      brightness: scheme.brightness,
      effectResolver: (_) =>
          ShimmerEffect(baseColor: base, highlightColor: highlight),
      containersColor: dark
          ? scheme.surfaceContainer
          : scheme.surfaceContainerLow,
    );
  }

  /// Display, headline, and title styles. Body and labels stay San Francisco.
  static TextTheme _nunitoHeadlines(TextTheme theme) {
    TextStyle? nunito(TextStyle? style) => style?.copyWith(
      fontFamily: 'Nunito',
      fontFamilyFallback: const ['SanFrancisco'],
    );
    return theme.copyWith(
      displayLarge: nunito(theme.displayLarge),
      displayMedium: nunito(theme.displayMedium),
      displaySmall: nunito(theme.displaySmall),
      headlineLarge: nunito(theme.headlineLarge),
      headlineMedium: nunito(theme.headlineMedium),
      headlineSmall: nunito(theme.headlineSmall),
      titleLarge: nunito(theme.titleLarge),
      titleMedium: nunito(theme.titleMedium),
    );
  }
}
