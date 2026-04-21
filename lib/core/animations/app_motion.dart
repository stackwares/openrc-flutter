import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Shared motion timing for list and card entrances ([flutter_animate]).
abstract final class AppMotion {
  static const Duration duration = Duration(milliseconds: 320);
  /// Capped so builder rows that mount while scrolling are not delayed ~1s+.
  static const int staggerMs = 18;
  static const int maxStaggerIndex = 8;
  static const Curve curve = Curves.easeOutCubic;

  static int cappedIndex(int index) =>
      index < maxStaggerIndex ? index : maxStaggerIndex;

  static Duration staggerDelay(int index) =>
      Duration(milliseconds: cappedIndex(index) * staggerMs);
}

extension AppMotionWidget on Widget {
  /// Staggered fade + slight upward slide for list/grid rows.
  Widget appListItemEntrance(int index, {Key? key}) {
    final delay = AppMotion.staggerDelay(index);
    return animate(key: key, delay: delay)
        .fadeIn(duration: AppMotion.duration, curve: AppMotion.curve)
        .slide(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
          duration: AppMotion.duration,
          curve: AppMotion.curve,
        );
  }

  /// Full-width card block: fade + subtle scale.
  Widget appCardEntrance({Duration delay = Duration.zero, Key? key}) {
    return animate(key: key, delay: delay)
        .fadeIn(duration: AppMotion.duration, curve: AppMotion.curve)
        .scaleXY(
          begin: 0.98,
          end: 1.0,
          duration: AppMotion.duration,
          curve: AppMotion.curve,
          alignment: Alignment.center,
        );
  }

  /// Headline metric text: use with [ValueKey] so day/range changes replay once.
  Widget appValueReveal({Key? key}) {
    const d = Duration(milliseconds: 280);
    return animate(key: key)
        .fadeIn(duration: d, curve: AppMotion.curve)
        .scaleXY(
          begin: 0.96,
          end: 1.0,
          duration: d,
          curve: AppMotion.curve,
          alignment: Alignment.center,
        );
  }
}
