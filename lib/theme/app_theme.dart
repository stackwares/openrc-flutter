import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:openrc/theme/app_colors.dart';
import 'package:openrc/theme/app_tokens.dart';
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
  inputDecoratorRadius: 14.0,
  chipRadius: 20.0,
  cardRadius: AppRadius.card,
  dialogRadius: 22.0,
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

  /// Neutral surfaces whatever the chosen scheme: the accent colors controls
  /// and selection, never the page or the cards.
  static ColorScheme _neutralSurfaces(ColorScheme scheme) {
    if (scheme.brightness == Brightness.dark) {
      return scheme.copyWith(
        surface: const Color(0xFF0D0E10),
        surfaceDim: const Color(0xFF0D0E10),
        surfaceBright: const Color(0xFF2A2D33),
        surfaceContainerLowest: const Color(0xFF0A0B0C),
        surfaceContainerLow: const Color(0xFF16171A),
        surfaceContainer: const Color(0xFF1C1E22),
        surfaceContainerHigh: const Color(0xFF23252A),
        surfaceContainerHighest: const Color(0xFF2A2D33),
        onSurface: const Color(0xFFEEF0F3),
        onSurfaceVariant: const Color(0xFF9095A0),
        outline: const Color(0xFF4A4E57),
        outlineVariant: const Color(0xFF25272B),
        surfaceTint: Colors.transparent,
      );
    }
    return scheme.copyWith(
      surface: const Color(0xFFF4F5F7),
      surfaceDim: const Color(0xFFE6E8EB),
      surfaceBright: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFFFFFF),
      surfaceContainer: const Color(0xFFEEF0F3),
      surfaceContainerHigh: const Color(0xFFE8EAEE),
      surfaceContainerHighest: const Color(0xFFE1E4E8),
      onSurface: const Color(0xFF111317),
      onSurfaceVariant: const Color(0xFF5F6570),
      outline: const Color(0xFFA0A5AE),
      outlineVariant: const Color(0xFFE3E5E8),
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _finish(ThemeData base) {
    final scheme = _neutralSurfaces(base.colorScheme);
    final isDark = scheme.brightness == Brightness.dark;
    final colors = isDark ? AppColors.dark : AppColors.light;
    final body = base.textTheme.apply(fontFamily: 'SanFrancisco');
    final primary = base.primaryTextTheme.apply(fontFamily: 'SanFrancisco');
    final textTheme = _nunitoHeadlines(
      body,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final sheetColor = isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;
    final selectedTint = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
      sheetColor,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: textTheme,
      primaryTextTheme: _nunitoHeadlines(primary),
      extensions: [colors],
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: colors.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: sheetColor,
        modalBackgroundColor: sheetColor,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: isDark ? scheme.surfaceContainer : scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceBright,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: scheme.onSurfaceVariant,
      ),
      // Selection is a soft accent tint, not a saturated block.
      chipTheme: base.chipTheme.copyWith(
        selectedColor: selectedTint,
        secondarySelectedColor: selectedTint,
        checkmarkColor: scheme.primary,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? scheme.primary.withValues(alpha: 0.6)
                : colors.hairline,
          ),
        ),
      ),
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
