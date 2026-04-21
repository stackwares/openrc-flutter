import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

abstract class AppTheme {
  /// AppBar titles: plain [Text] in each screen — no per-title [TextStyle];
  /// uses Flex + Material 3 default [AppBarTheme] / framework fallbacks.
  static ThemeData light(FlexScheme scheme) => FlexThemeData.light(
    scheme: scheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 7,
    subThemesData: const FlexSubThemesData(
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
      bottomSheetRadius: 20.0,
      filledButtonRadius: 12.0,
      elevatedButtonRadius: 12.0,
      outlinedButtonRadius: 12.0,
      textButtonRadius: 12.0,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
  );

  static ThemeData dark(FlexScheme scheme) => FlexThemeData.dark(
    scheme: scheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 13,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 20,
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
      bottomSheetRadius: 20.0,
      filledButtonRadius: 12.0,
      elevatedButtonRadius: 12.0,
      outlinedButtonRadius: 12.0,
      textButtonRadius: 12.0,
    ),
    visualDensity: FlexColorScheme.comfortablePlatformDensity,
    useMaterial3: true,
  );
}
