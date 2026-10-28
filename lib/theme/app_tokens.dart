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

/// Window size classes, after Material 3: phone, tablet, desktop.
enum WindowSize { compact, medium, expanded }

abstract final class AppBreakpoints {
  /// Tablets and narrow desktop windows: navigation rail.
  static const double medium = 600;

  /// Wide windows: sidebar and side-by-side columns.
  static const double expanded = 1024;

  /// Widest a single column of cards grows before it centers.
  static const double readableWidth = 720;

  /// Content width from which Transactions and Revenue become a dashboard:
  /// filter bar, cards in rows, then a transactions table.
  static const double dashboard = 900;

  /// Widest the dashboard grows before it centers.
  static const double dashboardMaxWidth = 1360;

  /// Dashboard side gutter.
  static const double dashboardGutter = 24;

  /// Widest Transactions' and Revenue's content grows in [width]: the
  /// dashboard on wide windows, a single column of cards otherwise.
  static double dashboardTabMaxWidth(double width) => width >= dashboard
      ? dashboardMaxWidth
      : readableWidth + 2 * AppSpace.gutter;

  static WindowSize of(double width) => width >= expanded
      ? WindowSize.expanded
      : width >= medium
      ? WindowSize.medium
      : WindowSize.compact;

  /// Side inset that centers a column of [maxWidth] in [available] width.
  static double centeringInset(
    double available, {
    double maxWidth = readableWidth,
  }) => available > maxWidth ? (available - maxWidth) / 2 : 0;
}

extension WindowSizeContext on BuildContext {
  /// Size class of the whole window, not of the pane this widget is in.
  WindowSize get windowSize => AppBreakpoints.of(MediaQuery.sizeOf(this).width);
}

/// A phone, by its shorter side; tablets and desktops are wider either way.
bool isPhoneSized(Size logicalSize) =>
    logicalSize.shortestSide < AppBreakpoints.medium;
