import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';

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
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      Expanded(
                        flex: (visible[i].value / total * 1000).round().clamp(
                          1,
                          1000,
                        ),
                        child: ColoredBox(color: visible[i].color),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
