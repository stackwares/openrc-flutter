import 'package:flutter/material.dart';
import 'package:revenuecat/core/extensions/context_extensions.dart';
import 'package:revenuecat/theme/app_tokens.dart';

/// Sentence-case section title with an optional muted count and trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpace.lg,
      AppSpace.lg,
      AppSpace.gutter,
      AppSpace.xs,
    ),
  });

  final String title;
  final String? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      letterSpacing: -0.1,
      color: context.colorScheme.onSurface,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  text: title,
                  children: [
                    if (count != null)
                      TextSpan(
                        text: '  $count',
                        style: TextStyle(
                          color: context.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          fontFeatures: AppText.tabular,
                        ),
                      ),
                  ],
                ),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
