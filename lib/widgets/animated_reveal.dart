import 'package:flutter/material.dart';

/// Grows open and fades in [child] when [visible], and closes when not.
class AnimatedReveal extends StatelessWidget {
  const AnimatedReveal({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // AnimatedSize with a zero duration throws during layout, so reduced
    // motion swaps instantly without it.
    if (MediaQuery.disableAnimationsOf(context)) {
      return visible ? child : const SizedBox(width: double.infinity);
    }
    const duration = Duration(milliseconds: 260);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: visible
            ? KeyedSubtree(key: const ValueKey('shown'), child: child)
            : const SizedBox(key: ValueKey('hidden'), width: double.infinity),
      ),
    );
  }
}
