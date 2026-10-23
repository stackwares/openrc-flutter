import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/theme/app_tokens.dart';
import 'package:revenuecat/widgets/pressable_scale.dart';

/// Neutral card with a hairline border; the base surface for every section.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: borderColor ?? context.appColors.hairline,
        width: borderWidth,
      ),
    );
    final content = Padding(padding: padding, child: child);
    return Padding(
      padding: margin,
      child: PressableScale(
        enabled: onTap != null,
        scale: 0.985,
        child: Card(
          color: color ?? context.colorScheme.surfaceContainerLow,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: onTap == null
              ? content
              : InkWell(onTap: onTap, customBorder: shape, child: content),
        ),
      ),
    );
  }
}
