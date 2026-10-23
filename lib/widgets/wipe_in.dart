import 'package:flutter/material.dart';
import 'package:openrc/core/animations/app_motion.dart';

/// Reveals its child left to right the first time it is built (charts, bars).
/// Layout is unaffected; only the visible area grows.
class WipeIn extends StatelessWidget {
  const WipeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 700),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, duration),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) =>
          ClipRect(clipper: _RevealClipper(t), child: child),
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
