import 'package:flutter/material.dart';
import 'package:revenuecat/core/animations/app_motion.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/widgets/wipe_in.dart';

class SplitSegment {
  const SplitSegment({
    required this.value,
    required this.color,
    required this.label,
  });

  final double value;
  final Color color;
  final String label;
}

/// Thin stacked bar showing how a whole splits into weighted parts.
///
/// Wipes in on first show; segments glide to new widths when shares change.
class SplitBar extends StatelessWidget {
  const SplitBar({
    super.key,
    required this.segments,
    this.height = 4,
    this.gap = 2,
  });

  final List<SplitSegment> segments;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((s) => s.value > 0).toList();
    final total = visible.fold<double>(0, (sum, s) => sum + s.value);
    final semantics = total <= 0
        ? null
        : visible
              .map((s) => '${s.label} ${(s.value / total * 100).round()}%')
              .join(', ');
    final duration = AppMotion.of(context, const Duration(milliseconds: 420));

    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: total <= 0
              ? ColoredBox(color: context.appColors.hairline)
              : WipeIn(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final usable =
                          constraints.maxWidth - gap * (visible.length - 1);
                      var left = 0.0;
                      return Stack(
                        children: [
                          for (final s in segments)
                            () {
                              final width = s.value > 0
                                  ? usable * s.value / total
                                  : 0.0;
                              final segment = AnimatedPositioned(
                                key: ValueKey(s.label),
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                left: left,
                                top: 0,
                                bottom: 0,
                                width: width,
                                child: ColoredBox(color: s.color),
                              );
                              if (width > 0) left += width + gap;
                              return segment;
                            }(),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
