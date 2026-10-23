import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/theme/app_tokens.dart';

/// One part of a whole: leading mark, label, amount, and a share bar with %.
class ShareRow extends StatelessWidget {
  const ShareRow({
    super.key,
    required this.label,
    required this.amount,
    required this.pct,
    required this.barColor,
    this.leading,
    this.details = const [],
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpace.md,
      vertical: AppSpace.sm,
    ),
  });

  final String label;
  final Widget amount;

  /// 0–100.
  final double pct;
  final Color barColor;
  final Widget? leading;

  /// Extra lines under the label (dates, captions).
  final List<Widget> details;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final v = (pct / 100).clamp(0.0, 1.0);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[
            SizedBox(width: 36, child: Center(child: leading)),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    DefaultTextStyle.merge(
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        fontFeatures: AppText.tabular,
                      ),
                      child: amount,
                    ),
                  ],
                ),
                ...details,
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: '${pct.toStringAsFixed(1)}% of total',
                        excludeSemantics: true,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: v,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(barColor),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${pct.toStringAsFixed(1)}%',
                        textAlign: TextAlign.end,
                        style: context.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontFeatures: AppText.tabular,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
