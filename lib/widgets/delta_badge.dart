import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';

enum DeltaDirection { up, down, flat }

/// Change versus an earlier value: arrow + label, colored by whether the
/// change is good ([higherIsBetter]) rather than by direction alone.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({
    super.key,
    required this.label,
    required this.direction,
    required this.semanticsLabel,
    this.higherIsBetter = true,
    this.filled = true,
    this.showArrow = true,
  });

  /// Signed count difference, e.g. `+15`, `−5`, `same`.
  factory DeltaBadge.count({
    Key? key,
    required int current,
    required int previous,
    bool higherIsBetter = true,
    bool filled = false,
    String? comparison,
  }) {
    final diff = current - previous;
    final compared = comparison ?? 'common.yesterday'.tr();
    final direction = diff > 0
        ? DeltaDirection.up
        : diff < 0
        ? DeltaDirection.down
        : DeltaDirection.flat;
    final label = switch (direction) {
      DeltaDirection.up => '+$diff',
      DeltaDirection.down => '−${diff.abs()}',
      DeltaDirection.flat => 'common.same'.tr(),
    };
    final semantics = switch (direction) {
      DeltaDirection.up => 'common.countMoreThan'.tr(
        namedArgs: {'count': '$diff', 'comparison': compared},
      ),
      DeltaDirection.down => 'common.countFewerThan'.tr(
        namedArgs: {'count': '${diff.abs()}', 'comparison': compared},
      ),
      DeltaDirection.flat => 'common.sameAs'.tr(
        namedArgs: {'comparison': compared},
      ),
    };
    return DeltaBadge(
      key: key,
      label: label,
      direction: direction,
      semanticsLabel: semantics,
      higherIsBetter: higherIsBetter,
      filled: filled,
      showArrow: false,
    );
  }

  /// Percent change from [previous] to [current]; [previous] must be non-zero.
  factory DeltaBadge.percent({
    Key? key,
    required double current,
    required double previous,
    bool higherIsBetter = true,
    bool filled = true,
    String? comparison,
  }) {
    final pct = (current - previous) / previous.abs() * 100;
    final compared = comparison ?? 'common.yesterday'.tr();
    final rounded = pct.abs() >= 10
        ? pct.abs().round().toString()
        : pct.abs().toStringAsFixed(1);
    final direction = rounded == '0' || rounded == '0.0'
        ? DeltaDirection.flat
        : pct > 0
        ? DeltaDirection.up
        : DeltaDirection.down;
    final label = direction == DeltaDirection.flat
        ? 'common.same'.tr()
        : '$rounded%';
    final semantics = switch (direction) {
      DeltaDirection.up => 'common.percentUpFrom'.tr(
        namedArgs: {'value': rounded, 'comparison': compared},
      ),
      DeltaDirection.down => 'common.percentDownFrom'.tr(
        namedArgs: {'value': rounded, 'comparison': compared},
      ),
      DeltaDirection.flat => 'common.sameAs'.tr(
        namedArgs: {'comparison': compared},
      ),
    };
    return DeltaBadge(
      key: key,
      label: label,
      direction: direction,
      semanticsLabel: semantics,
      higherIsBetter: higherIsBetter,
      filled: filled,
    );
  }

  final String label;
  final DeltaDirection direction;
  final String semanticsLabel;
  final bool higherIsBetter;

  /// Tinted pill when true, plain colored text when false.
  final bool filled;

  /// Off when the label already carries a sign (`+15`).
  final bool showArrow;

  Color color(BuildContext context) {
    final colors = context.appColors;
    if (direction == DeltaDirection.flat) return colors.neutralDelta;
    final improved = (direction == DeltaDirection.up) == higherIsBetter;
    return improved ? colors.positive : colors.negative;
  }

  @override
  Widget build(BuildContext context) {
    final accent = color(context);
    final icon = switch (direction) {
      DeltaDirection.up => Icons.arrow_upward_rounded,
      DeltaDirection.down => Icons.arrow_downward_rounded,
      DeltaDirection.flat => null,
    };
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.labelMedium?.copyWith(
        color: accent,
        fontWeight: FontWeight.w700,
        height: 1.1,
        fontFeatures: AppText.tabular,
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null && showArrow) ...[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 2),
        ],
        Flexible(child: text),
      ],
    );
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: filled
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: content,
              ),
            )
          : content,
    );
  }
}
