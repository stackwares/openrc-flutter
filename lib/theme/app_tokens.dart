import 'package:flutter/material.dart';

/// Spacing scale shared by every screen.
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter for cards and lists.
  static const double gutter = 16;
}

/// Corner radii shared by every screen.
abstract final class AppRadius {
  static const double card = 18;
  static const double tile = 14;
  static const double row = 12;
  static const double icon = 10;
  static const double pill = 999;

  static BorderRadius get cardAll => BorderRadius.circular(card);
  static BorderRadius get tileAll => BorderRadius.circular(tile);
}

/// Text helpers for numbers that change (amounts, counts).
abstract final class AppText {
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Large money / count values: San Francisco, bold, tight, tabular digits.
  static TextStyle amount(
    BuildContext context, {
    double size = 34,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: 'SanFrancisco',
      fontSize: size,
      fontWeight: weight,
      height: 1.1,
      letterSpacing: size >= 24 ? -0.6 : -0.2,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFeatures: tabular,
    );
  }
}
