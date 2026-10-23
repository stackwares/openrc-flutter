import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Shared motion timing for list and card entrances ([flutter_animate]).
abstract final class AppMotion {
  static const Duration duration = Duration(milliseconds: 320);

  /// Capped so builder rows that mount while scrolling are not delayed ~1s+.
  static const int staggerMs = 18;
  static const int maxStaggerIndex = 8;
  static const Curve curve = Curves.easeOutCubic;

  /// Small state changes (colors, selection).
  static const Duration fast = Duration(milliseconds: 180);

  /// Values counting to a new number, bars growing.
  static const Duration counter = Duration(milliseconds: 650);

  static int cappedIndex(int index) =>
      index < maxStaggerIndex ? index : maxStaggerIndex;

  static Duration staggerDelay(int index) =>
      Duration(milliseconds: cappedIndex(index) * staggerMs);

  /// [duration], or zero when the system asks to reduce motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

extension AppMotionWidget on Widget {
  /// Staggered fade + slight upward slide for list/grid rows.
  Widget appListItemEntrance(int index, {Key? key}) {
    final delay = AppMotion.staggerDelay(index);
    return _MotionGate(
      key: key,
      effects: (child) => child
          .animate(delay: delay)
          .fadeIn(duration: AppMotion.duration, curve: AppMotion.curve)
          .slide(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
            duration: AppMotion.duration,
            curve: AppMotion.curve,
          ),
      child: this,
    );
  }

  /// Full-width card block: fade + subtle scale.
  Widget appCardEntrance({Duration delay = Duration.zero, Key? key}) {
    return _MotionGate(
      key: key,
      effects: (child) => child
          .animate(delay: delay)
          .fadeIn(duration: AppMotion.duration, curve: AppMotion.curve)
          .scaleXY(
            begin: 0.98,
            end: 1.0,
            duration: AppMotion.duration,
            curve: AppMotion.curve,
            alignment: Alignment.center,
          ),
      child: this,
    );
  }

  /// Headline metric text: use with [ValueKey] so day/range changes replay once.
  Widget appValueReveal({Key? key}) {
    const d = Duration(milliseconds: 280);
    return _MotionGate(
      key: key,
      effects: (child) => child
          .animate()
          .fadeIn(duration: d, curve: AppMotion.curve)
          .scaleXY(
            begin: 0.96,
            end: 1.0,
            duration: d,
            curve: AppMotion.curve,
            alignment: Alignment.center,
          ),
      child: this,
    );
  }
}

/// Skips decorative entrance effects when the system asks to reduce motion.
class _MotionGate extends StatelessWidget {
  const _MotionGate({super.key, required this.effects, required this.child});

  final Widget Function(Widget child) effects;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? child : effects(child);
}
